const std = @import("std");
const zap = @import("zap");

var paras: [2]f32 = .{ 0, 0 };
var rohan: [2]f32 = .{ 0, 0 };

fn on_request(r: zap.Request) void {
    if (r.path) |the_path| {
        std.debug.print("{s}", .{the_path});
        if (std.mem.eql(u8, the_path, "/get/rohan/")) {
            var buf: [500]u8 = undefined;
            const resultant = std.fmt.bufPrintZ(&buf, "{d}:{d}", .{ rohan[0], rohan[1] }) catch return;
            std.debug.print("{d}", .{resultant});
            r.sendBody(resultant) catch return;
        } else if (std.mem.eql(u8, the_path, "/set/rohan/")) {
            if (r.query) |the_query| {
                var iter = std.mem.splitScalar(u8, the_query, ':');
                rohan[0] = std.fmt.parseFloat(f32, iter.next().?) catch return;
                rohan[1] = std.fmt.parseFloat(f32, iter.next().?) catch return;
            }
        } else if (std.mem.eql(u8, the_path, "/set/paras/")) {
            if (r.query) |the_query| {
                var iter = std.mem.splitScalar(u8, the_query, ':');
                paras[0] = std.fmt.parseFloat(f32, iter.next().?) catch return;
                paras[1] = std.fmt.parseFloat(f32, iter.next().?) catch return;
            }
        } else if (std.mem.eql(u8, the_path, "/get/paras/")) {
            var buf: [500]u8 = undefined;
            const resultant = std.fmt.bufPrintZ(&buf, "{d}:{d}", .{ paras[0], paras[1] }) catch return;
            r.sendBody(resultant) catch return;
        }
    }
}

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 8080,
        .on_request = on_request,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:8080\n", .{});

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
