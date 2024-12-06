pub const User = struct {
    id: ?i64 = null,
    name: []const u8,
    email: []const u8,
    age: i32,
    password: []const u8,
};

pub const UserLoginRequest = struct {
    email: []const u8,
    password: []const u8,
};
