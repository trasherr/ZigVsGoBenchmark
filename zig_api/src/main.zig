const std = @import("std");
const zap = @import("zap");
const UserHandler = @import("handler.zig").UserHandler;
const db = @import("database.zig");

fn not_found(req: zap.Request) void {
    std.debug.print("not found handler", .{});
    req.sendBody("Not found") catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator();

    // Initialize database
    var database = try db.init("benchmark.db");
    defer database.deinit();

    var userHandler = UserHandler.init(allocator, database.db);
    var simpleRouter = zap.Router.init(allocator, .{
        .not_found = not_found,
    });
    defer simpleRouter.deinit();

    // Register routes
    try simpleRouter.handle_func("/", &userHandler, &UserHandler.getAllUser);
    try simpleRouter.handle_func("/user", &userHandler, &UserHandler.handleUser);

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = simpleRouter.on_request_handler(),
        .log = true,
    });

    try listener.listen();
    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
