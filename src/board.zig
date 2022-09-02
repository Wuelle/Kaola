//! Defines the state of a chess board including a FEN parser

const std = @import("std");
const bitboard = @import("bitboard.zig");
const Bitboard = bitboard.Bitboard;
const bitops = @import("bitops.zig");
// const movegen = @import("movegen.zig");
const zobrist = @import("zobrist.zig");
// const Move = movegen.Move;
// const MoveType = movegen.MoveType;

fn bool_to_str(val: bool) []const u8 {
    if (val) {
        return "true";
    } else {
        return "false";
    }
}

pub const MoveTag = enum(u3) {
    castle,
    double_push,
    promote,
    en_passant,
    capture,
    quiet,
};

pub const MoveType = union(MoveTag) {
    castle: CastleSwaps,
    double_push: void,
    en_passant: void,
    promote: PieceType,
    capture: PieceType,
    quiet: PieceType,
};

pub const Move = struct {
    from: u64,
    to: u64,
    move_type: MoveType,
};

const WHITE_QUEENSIDE = CastleSwaps{
    .king = 0x1400000000000000,
    .rook = 0x900000000000000,
};

const WHITE_KINGSIDE = CastleSwaps{
    .king = 0x5000000000000000,
    .rook = 0xa000000000000000,
};

const BLACK_KINGSIDE = CastleSwaps{
    .king = 0x50,
    .rook = 0xa0,
};

const BLACK_QUEENSIDE = CastleSwaps{
    .king = 0x14,
    .rook = 0x9,
};

pub const CastleDirection = enum(u1) {
    kingside,
    queenside,
};

const CastleSwaps = struct {
    king: Bitboard,
    rook: Bitboard,
};

// Squares on a chess board
pub const Square = enum(u6) {
    // zig fmt: off
    A8, B8, C8, D8, E8, F8, G8, H8,
    A7, B7, C7, D7, E7, F7, G7, H7,
    A6, B6, C6, D6, E6, F6, G6, H6,
    A5, B5, C5, D5, E5, F5, G5, H5,
    A4, B4, C4, D4, E4, F4, G4, H4,
    A3, B3, C3, D3, E3, F3, G3, H3,
    A2, B2, C2, D2, E2, F2, G2, H2,
    A1, B1, C1, D1, E1, F1, G1, H1,
    // zig fmt: on

    pub inline fn from_str(str: []const u8) Square {
        return @intToEnum(Square, ('8' - str[1]) * 8 + (str[0] - 'a'));
    }

    pub inline fn as_board(self: *const Square) u64 {
        return @as(u64, 1) << @enumToInt(self.*);
    }

    pub inline fn to_str(self: *const Square) [:0]const u8 {
        return SQUARE_NAME[@enumToInt(self.*)];
    }

    pub inline fn file(self: *const Square) u3 {
        return @intCast(u3, @enumToInt(self.*) & 0b111);
    }

    pub inline fn rank(self: *const Square) u3 {
        return @intCast(u3, @enumToInt(self.*) >> 3);
    }

    pub inline fn down_one(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) + 8);
    }

    pub inline fn up_one(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) - 8);
    }

    pub inline fn down_two(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) + 16);
    }

    pub inline fn up_two(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) - 16);
    }

    pub inline fn down_left(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) + 7);
    }

    pub inline fn down_right(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) + 9);
    }
};

const SQUARE_NAME = [64][:0]const u8{
    "a8", "b8", "c8", "d8", "e8", "f8", "g8", "h8",
    "a7", "b7", "c7", "d7", "e7", "f7", "g7", "h7",
    "a6", "b6", "c6", "d6", "e6", "f6", "g6", "h6",
    "a5", "b5", "c5", "d5", "e5", "f5", "g5", "h5",
    "a4", "b4", "c4", "d4", "e4", "f4", "g4", "h4",
    "a3", "b3", "c3", "d3", "e3", "f3", "g3", "h3",
    "a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2",
    "a1", "b1", "c1", "d1", "e1", "f1", "g1", "h1",
};

pub const PieceType = enum(u3) {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,
};

pub const BoardRights = struct {
    active_color: Color,
    ep_square: ?Square,
    white_kingside: bool,
    white_queenside: bool,
    black_kingside: bool,
    black_queenside: bool,

    const Self = @This();

    pub fn new(color: Color, ep_square: ?Square, wk: bool, wq: bool, bk: bool, bq: bool) Self {
        return Self{
            .active_color = color,
            .ep_square = ep_square,
            .white_kingside = wk,
            .white_queenside = wq,
            .black_kingside = bk,
            .black_queenside = bq,
        };
    }

    pub fn initial() Self {
        return Self.new(Color.white, null, true, true, true, true);
    }

    pub fn kingside(self: *const Self, comptime color: Color) bool {
        switch (color) {
            Color.white => return self.white_kingside,
            Color.black => return self.black_kingside,
        }
    }

    pub fn queenside(self: *const Self, comptime color: Color) bool {
        switch (color) {
            Color.white => return self.white_queenside,
            Color.black => return self.black_queenside,
        }
    }

    pub fn print(self: *const Self, writer: anytype) !void {
        _ = try std.fmt.format(writer, "Active Color: {s}\n", .{@tagName(self.active_color)});
        _ = try writer.write("+--------+----------+-----------+\n");
        _ = try writer.write("| Castle | Kingside | Queenside |\n");
        _ = try writer.write("+--------+----------+-----------+\n");
        _ = try std.fmt.format(writer, "| White  |{s:^10}|{s:^11}|\n", .{
            bool_to_str(self.white_kingside),
            bool_to_str(self.white_queenside),
        });
        _ = try writer.write("+--------+----------+-----------+\n");
        _ = try std.fmt.format(writer, "| Black  |{s:^10}|{s:^11}|\n", .{
            bool_to_str(self.black_kingside),
            bool_to_str(self.black_queenside),
        });
        _ = try writer.write("+--------+----------+-----------+\n");

        if (self.ep_square) |square| {
            _ = try std.fmt.format(writer, "En passant Square: {s}\n", .{SQUARE_NAME[@enumToInt(square)]});
        } else {
            _ = try writer.write("No en passant possible\n");
        }
    }
};

pub const Color = enum(u1) {
    white,
    black,

    const Self = @This();

    pub inline fn other(self: *const Self) Self {
        return @intToEnum(Self, 1 - @enumToInt(self.*));
    }
};

/// Errors that can occur while parsing a FEN string
const FenParseError = error{
    MissingField,
    InvalidPosition,
    InvalidActiveSide,
    InvalidCastlingRights,
    InvalidEnPassant,
    InvalidHalfMoveCounter,
    InvalidFullMoveCounter,
};

pub const Position = struct {
    white_pawns: Bitboard,
    white_knights: Bitboard,
    white_bishops: Bitboard,
    white_rooks: Bitboard,
    white_queens: Bitboard,
    white_king: Bitboard,
    black_pawns: Bitboard,
    black_knights: Bitboard,
    black_bishops: Bitboard,
    black_rooks: Bitboard,
    black_queens: Bitboard,
    black_king: Bitboard,
    black: Bitboard,
    white: Bitboard,
    occupied: Bitboard,

    const Self = @This();

    fn new(white_pawns: Bitboard, white_knights: Bitboard, white_bishops: Bitboard, white_rooks: Bitboard, white_queens: Bitboard, white_king: Bitboard, black_pawns: Bitboard, black_knights: Bitboard, black_bishops: Bitboard, black_rooks: Bitboard, black_queens: Bitboard, black_king: Bitboard) Self {
        const white = white_pawns | white_knights | white_bishops | white_rooks | white_queens | white_king;
        const black = black_pawns | black_knights | black_bishops | black_rooks | black_queens | black_king;
        return Self{
            .white_pawns = white_pawns,
            .white_knights = white_knights,
            .white_bishops = white_bishops,
            .white_rooks = white_rooks,
            .white_queens = white_queens,
            .white_king = white_king,
            .black_pawns = black_pawns,
            .black_knights = black_knights,
            .black_bishops = black_bishops,
            .black_rooks = black_rooks,
            .black_queens = black_queens,
            .black_king = black_king,
            .white = white,
            .black = black,
            .occupied = white | black,
        };
    }

    pub fn pawns(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_pawns,
            Color.black => return self.black_pawns,
        }
    }

    pub fn knights(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_knights,
            Color.black => return self.black_knights,
        }
    }

    pub fn bishops(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_bishops,
            Color.black => return self.black_bishops,
        }
    }

    pub fn rooks(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_rooks,
            Color.black => return self.black_rooks,
        }
    }

    pub fn queens(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_queens,
            Color.black => return self.black_queens,
        }
    }

    pub fn king(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_king,
            Color.black => return self.black_king,
        }
    }

    pub fn occupied_by(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white,
            Color.black => return self.black,
        }
    }

    /// Create a new board with the starting position
    pub fn starting_position() Self {
        return Self.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR") catch unreachable;
    }

    /// Parse the position from a FEN string
    pub fn from_fen(fen_position: []const u8) FenParseError!Self {
        var pieces = [1]Bitboard{0} ** 12;

        var ranks = std.mem.split(u8, fen_position, "/");
        var rank: u6 = 0;
        while (ranks.next()) |entry| {
            var file: u6 = 0;
            for (entry) |c| {
                const square = @intToEnum(Square, rank * 8 + file);
                const piece_index: u4 = switch (c) {
                    'P' => 0,
                    'N' => 1,
                    'B' => 2,
                    'R' => 3,
                    'Q' => 4,
                    'K' => 5,
                    'p' => 6,
                    'n' => 7,
                    'b' => 8,
                    'r' => 9,
                    'q' => 10,
                    'k' => 11,
                    '1'...'8' => {
                        file += @intCast(u4, c - '0');
                        continue;
                    },
                    else => {
                        return FenParseError.InvalidPosition;
                    },
                };
                pieces[piece_index] ^= square.as_board();
                file += 1;
            }
            if (file != 8) return FenParseError.InvalidPosition;
            rank += 1;
        }
        if (rank != 8) return FenParseError.InvalidPosition;

        return Self.new(pieces[0], pieces[1], pieces[2], pieces[3], pieces[4], pieces[5], pieces[6], pieces[7], pieces[8], pieces[9], pieces[10], pieces[11]);
    }

    /// Print the formatted position to the terminal.
    /// This assumes that the position is valid, i.e no two pieces occupy the same position
    pub fn print(self: *const Self) !void {
        const stdout = std.io.getStdOut().writer();
        var i: u6 = 0;
        while (i < 8) : (i += 1) {
            std.debug.print("{d}  ", .{8 - i});
            var j: u6 = 0;
            while (j < 8) : (j += 1) {
                const mask = @intToEnum(Square, i * 8 + j).as_board();

                if (self.white_pawns & mask != 0) {
                    _ = try stdout.write("P");
                } else if (self.white_knights & mask != 0) {
                    _ = try stdout.write("N");
                } else if (self.white_bishops & mask != 0) {
                    _ = try stdout.write("B");
                } else if (self.white_rooks & mask != 0) {
                    _ = try stdout.write("R");
                } else if (self.white_queens & mask != 0) {
                    _ = try stdout.write("Q");
                } else if (self.white_king & mask != 0) {
                    _ = try stdout.write("K");
                } else if (self.black_pawns & mask != 0) {
                    _ = try stdout.write("p");
                } else if (self.black_knights & mask != 0) {
                    _ = try stdout.write("n");
                } else if (self.black_bishops & mask != 0) {
                    _ = try stdout.write("b");
                } else if (self.black_rooks & mask != 0) {
                    _ = try stdout.write("r");
                } else if (self.black_queens & mask != 0) {
                    _ = try stdout.write("q");
                } else if (self.black_king & mask != 0) {
                    _ = try stdout.write("k");
                } else {
                    _ = try stdout.write(".");
                }
                _ = try stdout.write(" ");
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n   a b c d e f g h\n", .{});
    }

    pub fn make_move(self: *const Self, comptime color: Color, move: Move) Position {
        const wp = self.white_pawns;
        const wn = self.white_knights;
        const wb = self.white_bishops;
        const wr = self.white_rooks;
        const wq = self.white_queens;
        const wk = self.white_king;
        const bp = self.black_pawns;
        const bn = self.black_knights;
        const bb = self.black_bishops;
        const br = self.black_rooks;
        const bq = self.black_queens;
        const bk = self.black_king;

        const from = move.from;
        const to = move.to;
        switch (color) {
            Color.white => {
                switch (move.move_type) {
                    MoveTag.castle => |swaps| {
                        return Self.new(wp, wn, wb, wr ^ swaps.rook, wq, wk ^ swaps.king, bp, bn, bb, br, bq, bk);
                    },
                    MoveTag.double_push => {
                        return Self.new(wp ^ (from | to), wn, wb, wr, wq, wk, bp, bn, bb, br, bq, bk);
                    },
                    MoveTag.promote => |promote_to| {
                        const r = ~from;
                        switch (promote_to) {
                            // zig fmt: off
                            PieceType.queen  => return Self.new(wp ^ from, wn, wb, wr, wq ^ to, wk, bp, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.rook   => return Self.new(wp ^ from, wn, wb, wr ^ to, wq, wk, bp, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.bishop => return Self.new(wp ^ from, wn, wb ^ to, wr, wq, wk, bp, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.knight => return Self.new(wp ^ from, wn ^ to, wb, wr, wq, wk, bp, bn & r, bb & r, br & r, bq & r, bk),
                            else => unreachable,
                            // zig fmt: on
                        }
                    },
                    MoveTag.en_passant => unreachable,
                    MoveTag.capture => |piece_type| {
                        const r = ~from;
                        std.debug.assert(move.to & self.white == 0);
                        std.debug.assert(to & bk == 0);
                        const m = (from | to);
                        switch (piece_type) {
                            // zig fmt: off
                            PieceType.pawn   => return Self.new(wp ^ m, wn, wb, wr, wq, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.knight => return Self.new(wp, wn ^ m, wb, wr, wq, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.bishop => return Self.new(wp, wn, wb ^ m, wr, wq, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.rook   => return Self.new(wp, wn, wb, wr ^ m, wq, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.queen  => return Self.new(wp, wn, wb, wr, wq ^ m, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.king   => return Self.new(wp, wn, wb, wr, wq, wk ^ m, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            // zig fmt: on
                        }
                    },
                    MoveTag.quiet => |piece_type| {
                        const m = (from | to);
                        switch (piece_type) {
                            // zig fmt: off
                            PieceType.pawn   => return Self.new(wp ^ m, wn, wb, wr, wq, wk, bp, bn, bb, br, bq, bk),
                            PieceType.knight => return Self.new(wp, wn ^ m, wb, wr, wq, wk, bp, bn, bb, br, bq, bk),
                            PieceType.bishop => return Self.new(wp, wn, wb ^ m, wr, wq, wk, bp, bn, bb, br, bq, bk),
                            PieceType.rook   => return Self.new(wp, wn, wb, wr ^ m, wq, wk, bp, bn, bb, br, bq, bk),
                            PieceType.queen  => return Self.new(wp, wn, wb, wr, wq ^ m, wk, bp, bn, bb, br, bq, bk),
                            PieceType.king   => return Self.new(wp, wn, wb, wr, wq, wk ^ m, bp, bn, bb, br, bq, bk),
                            // zig fmt: on
                        }
                    },
                }
            },
            Color.black => {
                switch (move.move_type) {
                    MoveTag.castle => |swaps| {
                        return Self(wp, wn, wb, wr, wq, wk, bp, bn, bb, br ^ swaps.rook, bq, bk ^ swaps.king);
                    },
                    MoveTag.double_push => {
                        return Self(wp, wn, wb, wr, wq, wk, bp ^ (from | to), bn, bb, br, bq, bk);
                    },
                    MoveTag.promote => |promote_to| {
                        const r = ~from;
                        switch (promote_to) {
                            // zig fmt: off
                            PieceType.queen  => return Self(wp, wn & r, wb & r, wr & r, wq & r, wk, bp ^ from, bn, bb, br, bq ^ to, bk),
                            PieceType.rook   => return Self(wp, wn & r, wb & r, wr & r, wq & r, wk, bp ^ from, bn, bb, br ^ to, bq, bk),
                            PieceType.bishop => return Self(wp, wn & r, wb & r, wr & r, wq & r, wk, bp ^ from, bn, bb ^ to, br, bq, bk),
                            PieceType.knight => return Self(wp, wn & r, wb & r, wr & r, wq & r, wk, bp ^ from, bn ^ to, bb, br, bq, bk),
                            else => unreachable,
                            // zig fmt: on
                        }
                    },
                    MoveTag.en_passant => unreachable,
                    MoveTag.capture => |piece_type| {
                        const r = ~from;
                        std.debug.assert(move.to & self.black == 0);
                        std.debug.assert(to & bk == 0);
                        const m = (from | to);
                        std.debug.assert(m & wk == 0);
                        switch (piece_type) {
                            // zig fmt: off
                            PieceType.pawn   => return Self.new(wp & r, wn & r, wb, wr & r, wq & r, wk, bp ^ m, bn, bb, br, bq, bk),
                            PieceType.knight => return Self.new(wp & r, wn & r, wb, wr & r, wq & r, wk, bp, bn ^ m, bb, br, bq, bk),
                            PieceType.bishop => return Self.new(wp & r, wn & r, wb, wr & r, wq & r, wk, bp, bn, bb ^ m, br, bq, bk),
                            PieceType.rook   => return Self.new(wp & r, wn & r, wb, wr & r, wq & r, wk, bp, bn, bb, br ^ m, bq, bk),
                            PieceType.queen  => return Self.new(wp & r, wn & r, wb, wr & r, wq & r, wk, bp, bn, bb, br, bq ^ m, bk),
                            PieceType.king   => return Self.new(wp & r, wn & r, wb, wr & r, wq & r, wk, bp, bn, bb, br, bq, bk ^ m),
                            // zig fmt: on
                        }
                    },
                    MoveTag.quiet => |piece_type| {
                        const m = (from | to);
                        switch (piece_type) {
                            // zig fmt: off
                            PieceType.pawn   => return Self.new(wp, wn, wb, wr, wq, wk, bp ^ m, bn, bb, br, bq, bk),
                            PieceType.knight => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn ^ m, bb, br, bq, bk),
                            PieceType.bishop => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb ^ m, br, bq, bk),
                            PieceType.rook   => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb, br ^ m, bq, bk),
                            PieceType.queen  => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb, br, bq ^ m, bk),
                            PieceType.king   => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb, br, bq, bk ^ m),
                            // zig fmt: on
                        }
                    },
                }
            },
        }
    }

    // /// Return a bitboard marking all the squares attacked(or guarded) by a piece of a certain color
    // /// Note that the king is effectively considered to be nonexistent, as he cannot move
    // /// to squares that are x-rayed by an opponent slider piece.
    // /// So result is "a bitboard marking all positions that the opponent king cannot move to".
    // pub fn king_unsafe_squares(self: *const Board, comptime us: Color) u64 {
    //     var attacked: Bitboard = 0;
    //     const them = us.other();
    //     const ALL_WITHOUT_KING = self.get_occupancies(Color.both) ^ self.get_bitboard(PieceType.king.color(us));

    //     // pawns
    //     const opponent_pawns = self.get_bitboard(PieceType.pawn.color(them));
    //     attacked |= bitboard.pawn_attacks(us, opponent_pawns);

    //     // knights
    //     var knights = self.get_bitboard(PieceType.knight.color(them));
    //     while (knights != 0) : (bitops.pop_ls1b(&knights)) {
    //         const square = bitboard.get_lsb_square(knights);
    //         attacked |= bitboard.knight_attacks(square.as_board());
    //     }

    //     // bishops
    //     var diag_sliders = self.get_bitboard(PieceType.bishop.color(them)) | self.get_bitboard(PieceType.queen.color(them));
    //     while (diag_sliders != 0) : (bitops.pop_ls1b(&diag_sliders)) {
    //         const square = bitboard.get_lsb_square(diag_sliders);
    //         attacked |= bitboard.bishop_attacks(square, ALL_WITHOUT_KING);
    //     }

    //     // rooks
    //     var straight_sliders = self.get_bitboard(PieceType.rook.color(them)) | self.get_bitboard(PieceType.queen.color(them));
    //     while (straight_sliders != 0) : (bitops.pop_ls1b(&straight_sliders)) {
    //         const square = bitboard.get_lsb_square(straight_sliders);
    //         attacked |= bitboard.rook_attacks(square, ALL_WITHOUT_KING);
    //     }

    //     // king(s)
    //     var kings = self.get_bitboard(PieceType.king.color(them));
    //     while (kings != 0) : (bitops.pop_ls1b(&kings)) {
    //         attacked |= bitboard.king_attacks(kings);
    //     }
    //     return attacked;
    // }
};
