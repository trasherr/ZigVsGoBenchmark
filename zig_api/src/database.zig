const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Database = struct {
    db: ?*c.sqlite3,

    pub fn init(db_path: []const u8) !Database {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(db_path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            std.debug.print("Can't open database: {s}\n", .{c.sqlite3_errmsg(db)});
            return error.SQLiteError;
        }

        // Create users table
        const create_table_sql =
            \\CREATE TABLE IF NOT EXISTS users (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  name TEXT NOT NULL,
            \\  email TEXT NOT NULL UNIQUE,
            \\  age INTEGER NOT NULL,
            \\  password TEXT NOT NULL
            \\);
        ;
        var err_msg: [*c]u8 = null;
        const result = c.sqlite3_exec(db, create_table_sql, null, null, &err_msg);
        if (result != c.SQLITE_OK) {
            std.debug.print("SQL error: {s}\n", .{err_msg});
            c.sqlite3_free(err_msg);
            return error.SQLiteError;
        }
        std.debug.print("Table ready\n\n", .{});

        return Database{ .db = db };
    }

    pub fn deinit(self: *Database) void {
        _ = c.sqlite3_close(self.db);
    }
};

pub fn init(db_path: []const u8) !Database {
    return Database.init(db_path);
}
