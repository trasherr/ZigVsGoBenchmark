const std = @import("std");
const zap = @import("zap");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const User = @import("user.zig").User;
const UserLoginRequest = @import("user.zig").UserLoginRequest;
const Allocator = std.mem.Allocator;
const HttpParamStrKVList = @import("zap").Request.HttpParamStrKVList;

pub const UserHandler = struct {
    const Self = @This();
    allocator: Allocator,
    db: ?*c.sqlite3,

    pub fn init(allocator: Allocator, db: ?*c.sqlite3) Self {
        return .{
            .allocator = allocator,
            .db = db,
        };
    }

    fn sendJsonResponse(req: zap.Request, data: anytype, alloc: Allocator) !void {
        const response = try std.json.stringifyAlloc(alloc, data, .{});
        defer alloc.free(response);
        try req.setContentType(.JSON);
        try req.sendBody(response);
    }

    // Main handler for /user endpoint
    pub fn handleUser(self: *Self, req: zap.Request) void {
        if (req.method != null) {
            if (std.mem.eql(u8, req.method.?, "GET")) {
                self.login(req) catch return;
            } else if (std.mem.eql(u8, req.method.?, "POST")) {
                self.register(req) catch return;
            } else if (std.mem.eql(u8, req.method.?, "PUT")) {
                const auth = Self.checkBearerToken(req) catch return;
                if (!auth) {
                    return;
                }
                self.updateUser(req) catch return;
            } else if (std.mem.eql(u8, req.method.?, "DELETE")) {
                const auth = Self.checkBearerToken(req) catch return;
                if (!auth) {
                    return;
                }
                self.deleteUser(req) catch return;
            } else {
                req.setStatus(.method_not_allowed);
                req.sendBody("Method not allowed") catch return;
            }
        }
    }
    pub fn getAllUser(self: *Self, req: zap.Request) void {
        if (req.method != null) {
            self.allUser(req) catch return;
        }
    }

    fn checkBearerToken(req: zap.Request) !bool {
        const auth_header = req.getHeader("authorization") orelse {
            req.setStatus(.unauthorized);
            try req.sendBody("Missing Authorization header");
            return false;
        };
        // Basic check for bearer token format (starts with "Bearer ")
        if (!std.mem.startsWith(u8, auth_header, "Bearer test@gmail.com")) {
            req.setStatus(.unauthorized);
            try req.sendBody("Invalid Authorization header format");
            return false;
        }

        // Note: Token authentication is not implemented here
        // You would typically validate the token against a database or auth service
        return true;
    }

    fn getValueByKey(list: HttpParamStrKVList, key: []const u8) []const u8 {
        for (list.items) |param| {
            if (std.mem.eql(u8, param.key.str, key)) {
                return param.value.str;
            }
        }
        return ""; // Return null if the key is not found
    }
    pub fn login(self: *Self, req: zap.Request) !void {
        req.parseBody() catch |err| {
            std.log.err("Parse Body error: {any}. Expected if body is empty", .{err});
        };
        var strparams = req.parametersToOwnedStrList(self.allocator, false) catch unreachable;
        defer strparams.deinit();
        const email: []const u8 = Self.getValueByKey(strparams, "email");
        const password: []const u8 = Self.getValueByKey(strparams, "password");

        var stmt: ?*c.sqlite3_stmt = null;
        const query = "SELECT id, name, email, age FROM users WHERE email = ? AND password = ?";

        const prepare_result = c.sqlite3_prepare_v2(
            self.db,
            query,
            @intCast(query.len),
            &stmt,
            null,
        );

        if (prepare_result != c.SQLITE_OK) {
            // req.setStatus(.internal_server_error) catch return;
            req.sendBody("Database error") catch return;
            return;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, @ptrCast(email), @intCast(email.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, @ptrCast(password), @intCast(password.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const user = User{
                .id = c.sqlite3_column_int64(stmt, 0),
                .name = std.mem.sliceTo(c.sqlite3_column_text(stmt, 1), 0),
                .email = std.mem.sliceTo(c.sqlite3_column_text(stmt, 2), 0),
                .age = c.sqlite3_column_int(stmt, 3),
                .password = "",
            };
            Self.sendJsonResponse(req, user, self.allocator) catch return;
        } else {
            req.setStatus(.internal_server_error);
            try req.sendBody("Invalid email or password");
        }
    }

    pub fn register(self: *Self, req: zap.Request) !void {
        req.parseBody() catch |err| {
            std.log.err("Parse Body error: {any}. Expected if body is empty", .{err});
        };

        var strparams = req.parametersToOwnedStrList(self.allocator, false) catch unreachable;
        defer strparams.deinit();

        const name: []const u8 = Self.getValueByKey(strparams, "name");
        const email: []const u8 = Self.getValueByKey(strparams, "email");
        const password: []const u8 = Self.getValueByKey(strparams, "password");
        const age_str: []const u8 = Self.getValueByKey(strparams, "age");
        const age = std.fmt.parseInt(i32, age_str, 10) catch 0;

        var stmt: ?*c.sqlite3_stmt = null;
        const query = "INSERT INTO users (name, email, age, password) VALUES (?, ?, ?, ?)";

        const prepare_result = c.sqlite3_prepare_v2(
            self.db,
            query,
            @intCast(query.len),
            &stmt,
            null,
        );

        if (prepare_result != c.SQLITE_OK) {
            req.sendBody("Database error") catch return;
            return;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, @ptrCast(name), @intCast(name.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, @ptrCast(email), @intCast(email.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int(stmt, 3, age);
        _ = c.sqlite3_bind_text(stmt, 4, @ptrCast(password), @intCast(password.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_DONE) {
            const user = User{
                .id = c.sqlite3_last_insert_rowid(self.db),
                .name = name,
                .email = email,
                .age = age,
                .password = "", // Don't return the password
            };
            Self.sendJsonResponse(req, user, self.allocator) catch return;
        } else {
            req.setStatus(.internal_server_error);
            try req.sendBody("Failed to create user");
        }
    }

    pub fn updateUser(self: *Self, req: zap.Request) !void {
        req.parseBody() catch |err| {
            std.log.err("Parse Body error: {any}. Expected if body is empty", .{err});
        };

        var strparams = req.parametersToOwnedStrList(self.allocator, false) catch unreachable;
        defer strparams.deinit();

        const name: []const u8 = Self.getValueByKey(strparams, "name");
        const email: []const u8 = Self.getValueByKey(strparams, "email");
        const password: []const u8 = Self.getValueByKey(strparams, "password");
        const age_str: []const u8 = Self.getValueByKey(strparams, "age");
        const age = std.fmt.parseInt(i32, age_str, 10) catch 0;

        var stmt: ?*c.sqlite3_stmt = null;
        const query = "UPDATE users SET name = ?, age = ?, password = ? WHERE email = ?";

        const prepare_result = c.sqlite3_prepare_v2(
            self.db,
            query,
            @intCast(query.len),
            &stmt,
            null,
        );

        if (prepare_result != c.SQLITE_OK) {
            req.sendBody("Database error") catch return;
            return;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, @ptrCast(name), @intCast(name.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int(stmt, 2, age);
        _ = c.sqlite3_bind_text(stmt, 3, @ptrCast(password), @intCast(password.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 4, @ptrCast(email), @intCast(email.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_DONE) {
            const user = User{
                .id = 0, // ID won't be updated
                .name = name,
                .email = email,
                .age = age,
                .password = password,
            };
            Self.sendJsonResponse(req, user, self.allocator) catch return;
        } else {
            req.setStatus(.internal_server_error);
            try req.sendBody("Failed to update user");
        }
    }

    pub fn deleteUser(self: *Self, req: zap.Request) !void {
        req.parseBody() catch |err| {
            std.log.err("Parse Body error: {any}. Expected if body is empty", .{err});
        };
        var strparams = req.parametersToOwnedStrList(self.allocator, false) catch unreachable;
        defer strparams.deinit();

        const email: []const u8 = Self.getValueByKey(strparams, "email");
        const password: []const u8 = Self.getValueByKey(strparams, "password");

        var stmt1: ?*c.sqlite3_stmt = null;
        const query1 = "SELECT id, name, email, age, password FROM users WHERE email = ? AND password = ?";

        const prepare_result1 = c.sqlite3_prepare_v2(
            self.db,
            query1,
            @intCast(query1.len),
            &stmt1,
            null,
        );

        if (prepare_result1 != c.SQLITE_OK) {
            // req.setStatus(.internal_server_error) catch return;
            req.sendBody("Database error") catch return;
            return;
        }
        defer _ = c.sqlite3_finalize(stmt1);

        _ = c.sqlite3_bind_text(stmt1, 1, @ptrCast(email), @intCast(email.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt1, 2, @ptrCast(password), @intCast(password.len), c.SQLITE_STATIC);
        var user: ?User = null;
        if (c.sqlite3_step(stmt1) == c.SQLITE_ROW) {
            user = User{
                .id = c.sqlite3_column_int64(stmt1, 0),
                .name = std.mem.sliceTo(c.sqlite3_column_text(stmt1, 1), 0),
                .email = std.mem.sliceTo(c.sqlite3_column_text(stmt1, 2), 0),
                .age = c.sqlite3_column_int(stmt1, 3),
                .password = std.mem.sliceTo(c.sqlite3_column_text(stmt1, 4), 0),
            };
        } else {
            req.setStatus(.not_found);
            try req.sendBody("User not found");
            return;
        }

        var stmt: ?*c.sqlite3_stmt = null;
        const query = "DELETE FROM users WHERE email = ? AND password = ?";

        const prepare_result = c.sqlite3_prepare_v2(
            self.db,
            query,
            @intCast(query.len),
            &stmt,
            null,
        );

        if (prepare_result != c.SQLITE_OK) {
            req.sendBody("Database error") catch return;
            return;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, @ptrCast(email), @intCast(email.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, @ptrCast(password), @intCast(password.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_DONE) {
            if (c.sqlite3_changes(self.db) > 0) {
                Self.sendJsonResponse(req, user, self.allocator) catch return;
            } else {
                req.setStatus(.not_found);
                try req.sendBody("User not found");
            }
        } else {
            req.setStatus(.internal_server_error);
            try req.sendBody("Failed to delete user");
        }
    }

    fn allUser(self: *Self, req: zap.Request) !void {
        if (self.db == null) {
            try req.sendBody("Database connection not initialized");
            return;
        }

        var stmt: ?*c.sqlite3_stmt = null;
        const query = "SELECT id, name, email, age FROM users";

        // Prepare statement with explicit error handling
        const prepare_result = c.sqlite3_prepare_v2(
            self.db,
            query,
            @intCast(query.len),
            &stmt,
            null,
        );

        // Immediately check prepare result
        if (prepare_result != c.SQLITE_OK) {
            try req.sendBody("Failed to prepare SQL statement");
            return;
        }

        defer _ = c.sqlite3_finalize(stmt);

        var users = std.ArrayList(User).init(self.allocator);
        defer users.deinit();

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const id: i64 = c.sqlite3_column_int64(stmt, 0);
            const user = User{
                .id = id,
                .name = "test123",
                .email = "test123@gmail.com",
                .age = c.sqlite3_column_int(stmt, 3),
                .password = "password123",
            };
            try users.append(user);
        }
        Self.sendJsonResponse(req, users.items, self.allocator) catch return;
    }
};
