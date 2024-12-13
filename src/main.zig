const std = @import("std");
const zap = @import("zap");
const eql = std.mem.eql;
const alc = std.heap.c_allocator;
const Player = struct {
    id: u32,
    online: bool = true,
    x: f32 = 0,
    z: f32 = 0,
    in_game: bool = false,
    room_id: ?u32,
    user_name: []const u8,
    password: []const u8,

    const Self = @This();

    pub fn create(id: u32, user_name: []const u8, password: []const u8) Player {
        // Allocate fixed-size array to store the user_name and password slices
        const user_name_dupe = alc.dupe(u8, user_name) catch @panic("RAM full");
        const password_dupe = alc.dupe(u8, password) catch @panic("RAM full");

        std.debug.print("\n{s}\n", .{user_name_dupe});
        std.debug.print("\n{s}\n", .{password_dupe});
        return Player{
            .id = id,
            .room_id = null,
            .user_name = user_name_dupe,
            .password = password_dupe,
        };
    }

    pub fn setRoom(self: *Self, id: u32, password: []const u8, room_id: u32) bool {
        if (!self.in_game and self.id == id and eql(u8, self.password, password)) {
            self.room_id = room_id;
            self.in_game = true;
            return true;
        }
        return false;
    }

    pub fn setCoordinates(self: *Self, id: u32, password: []const u8, x: f32, z: f32) bool {
        if (self.in_game and self.id == id and eql(u8, self.password, password)) {
            self.x = x;
            self.z = z;
            return true;
        }
        return false;
    }

    pub fn getCoordinates(self: *Self) [2]f32 {
        return .{ self.x, self.z };
    }
};

const GameRoom = struct {
    id: u32,
    no_of_players: u8 = 0,
    players: [*]Player = undefined,

    pub fn init(id: u32) GameRoom {
        var players_s: [4]Player = undefined;
        return GameRoom{
            .id = id,
            .no_of_players = 0,
            .players = &players_s,
        };
    }
};

var players: [5000]Player = undefined;
var players_index: u32 = 0;
var games: [5000]GameRoom = undefined;
var games_index: u32 = 0;

fn handleSignup(r: zap.Request) !void {
    if (r.query) |query| {
        var parts = std.mem.splitScalar(u8, query, ':');
        if (parts.next()) |user_name| {
            for (players[0..players_index]) |player| {
                if (eql(u8, player.user_name, user_name)) {
                    try r.sendBody("USER ALREADY EXISTS");
                    return;
                }
            }
            if (parts.next()) |password| {
                const sanitized_user_name = if (user_name.len > 10) user_name[0..10] else user_name;
                const sanitized_password = if (password.len > 10) password[0..10] else password;
                const new_player = Player.create(players_index, sanitized_user_name, sanitized_password);
                players[players_index] = new_player;
                players_index += 1;
                try r.sendBody("CREATED USER");
                return;
            }
        }
    }
    try r.sendBody("INVALID QUERY");
}

fn handleSignin(r: zap.Request) !void {
    if (r.query) |query| {
        var parts = std.mem.splitScalar(u8, query, ':');
        if (parts.next()) |user_name| {
            if (parts.next()) |password| {
                if (user_name.len > 10 or password.len > 10) {
                    try r.sendBody("WRONG CREDENTIALS");
                    return;
                }
                for (players[0..players_index]) |player| {
                    if (eql(u8, player.user_name, user_name) and eql(u8, player.password, password)) {
                        var buf: [50]u8 = undefined;
                        const res = try std.fmt.bufPrintZ(&buf, "{d}", .{player.id});
                        try r.sendBody(res);
                        return;
                    }
                }
            }
        }
    }
}

fn handleEnterRoom(r: zap.Request) !void {
    if (r.query) |query| {
        std.debug.print("Query: {s}\n", .{query});
        var parts = std.mem.splitScalar(u8, query, ':');

        if (parts.next()) |id_str| {
            if (parts.next()) |password| {
                const id = std.fmt.parseInt(u32, id_str, 10) catch {
                    try r.sendBody("INVALID ID");
                    return;
                };
                if (id >= players_index or !eql(u8, players[id].password, password)) {
                    std.debug.print("\nGOT:{d}:{s}", .{ id, players[id].password });
                    std.debug.print("\nEXPECTED:{d}:{s}", .{ players[0].id, players[0].password });
                    try r.sendBody("INVALID CREDENTIALS");
                    return;
                }

                // Handle optional room_id
                if (parts.next()) |room_id_str| {
                    const room_id = std.fmt.parseInt(u32, room_id_str, 10) catch {
                        try r.sendBody("INVALID ROOM ID");
                        return;
                    };

                    // Check for existing room
                    for (games[0..games_index]) |*game| {
                        if (game.id == room_id and game.no_of_players < 4) {
                            game.players[game.no_of_players] = players[id];
                            game.no_of_players += 1;
                            players[id].in_game = true;
                            players[id].room_id = room_id;
                            try r.sendBody("ENTERED ROOM");
                            return;
                        }
                    }

                    try r.sendBody("ROOM NOT FOUND OR FULL");
                    return;
                } else {
                    // Create a new room if no room_id is provided
                    var new_room = GameRoom.init(games_index);
                    new_room.players[0] = players[id];
                    new_room.no_of_players = 1;

                    games[games_index] = new_room;
                    players[id].in_game = true;
                    players[id].room_id = games_index;
                    games_index += 1;

                    try r.sendBody("NEW ROOM CREATED");
                    return;
                }
            }
        }
    }
    try r.sendBody("INVALID QUERY FORMAT");
}

fn handleSetCoordinates(r: zap.Request) !void {
    if (r.query) |query| {
        var parts = std.mem.splitScalar(u8, query, ':');
        if (parts.next()) |id_str| {
            const id = std.fmt.parseInt(u32, id_str, 10) catch {
                try r.sendBody("INVALID ID");
                return;
            };
            if (id >= players_index) {
                try r.sendBody("INVALID PLAYER ID");
                return;
            }

            if (parts.next()) |password| {
                if (!eql(u8, players[id].password, password) or !players[id].in_game) {
                    try r.sendBody("INVALID CREDENTIALS");
                    return;
                }

                if (parts.next()) |x_str| {
                    if (parts.next()) |z_str| {
                        const x = std.fmt.parseFloat(f32, x_str) catch {
                            try r.sendBody("INVALID COORDINATE X");
                            return;
                        };
                        const z = std.fmt.parseFloat(f32, z_str) catch {
                            try r.sendBody("INVALID COORDINATE Z");
                            return;
                        };

                        _ = players[id].setCoordinates(id, password, x, z);
                        try r.sendBody("COORDINATES UPDATED");
                        return;
                    }
                }
            }
        }
    }
    try r.sendBody("INVALID QUERY");
}

fn handleGetCoordinates(r: zap.Request) !void {
    if (r.query) |query| {
        const id = std.fmt.parseInt(u32, query, 10) catch {
            try r.sendBody("INVALID PLAYER ID");
            return;
        };
        if (id >= players_index) {
            try r.sendBody("INVALID PLAYER ID");
            return;
        }
        const coords = players[id].getCoordinates();
        var buf: [64]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}:{d}", .{ coords[0], coords[1] }) catch {
            try r.sendBody("ERROR FORMATTING COORDINATES");
            return;
        };
        try r.sendBody(result);
        return;
    }
    try r.sendBody("INVALID QUERY");
}

fn onRequest(r: zap.Request) void {
    std.debug.print("\n{any}\n", .{players[0..2]});
    if (r.path) |path| {
        if (eql(u8, path, "/")) {
            r.sendFile("./a.html") catch return;
        } else if (eql(u8, path, "/signup/")) {
            handleSignup(r) catch return;
        } else if (eql(u8, path, "/signin/")) {
            handleSignin(r) catch return;
        } else if (eql(u8, path, "/enter_room/")) {
            handleEnterRoom(r) catch return;
        } else if (eql(u8, path, "/set/")) {
            handleSetCoordinates(r) catch return;
        } else if (eql(u8, path, "/get/")) {
            handleGetCoordinates(r) catch return;
        } else {
            r.sendBody("INVALID PATH") catch return;
        }
    } else {
        r.sendBody("INVALID REQUEST") catch return;
    }
}

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 8080,
        .on_request = onRequest,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:8080\n", .{});

    // Start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
