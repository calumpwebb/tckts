const std = @import("std");
const tckts = @import("tckts");

const mem = std.mem;

// --- I/O helpers ---

pub fn print(comptime format: []const u8, args: anytype) void {
    const stdout = std.fs.File.stdout();
    var buf: [8192]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, format, args) catch return;
    _ = stdout.write(msg) catch {};
}

pub fn eprint(comptime format: []const u8, args: anytype) void {
    const stderr = std.fs.File.stderr();
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, format, args) catch return;
    _ = stderr.write(msg) catch {};
}

pub fn printAvailableProjects(allocator: std.mem.Allocator) void {
    const projects = tckts.listProjects(allocator) catch return;
    defer {
        for (projects) |p| allocator.free(p);
        allocator.free(projects);
    }

    if (projects.len == 0) {
        eprint("No projects initialized. Run 'tckts init <PREFIX>' to create one.\n", .{});
    } else {
        eprint("Available projects: ", .{});
        for (projects, 0..) |prefix, i| {
            if (i > 0) eprint(", ", .{});
            eprint("{s}", .{prefix});
        }
        eprint("\n", .{});
    }
}

/// Convert a prefix string to uppercase, allocating a new buffer
pub fn toUpperPrefix(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    var upper = try allocator.alloc(u8, prefix.len);
    for (prefix, 0..) |c, i| {
        upper[i] = std.ascii.toUpper(c);
    }
    return upper;
}

// --- types ---

pub const Command = enum {
    init,
    add,
    list,
    show,
    done,
    rm,
    projects,
    help,

    pub fn fromString(s: []const u8) ?Command {
        const commands = .{
            .{ "init", Command.init },
            .{ "add", Command.add },
            .{ "list", Command.list },
            .{ "ls", Command.list },
            .{ "show", Command.show },
            .{ "done", Command.done },
            .{ "complete", Command.done },
            .{ "rm", Command.rm },
            .{ "delete", Command.rm },
            .{ "remove", Command.rm },
            .{ "projects", Command.projects },
            .{ "help", Command.help },
            .{ "--help", Command.help },
            .{ "-h", Command.help },
        };

        inline for (commands) |cmd| {
            if (mem.eql(u8, s, cmd[0])) return cmd[1];
        }
        return null;
    }
};

// --- tests ---

test "Command: fromString" {
    const testing = std.testing;

    try testing.expectEqual(Command.init, Command.fromString("init").?);
    try testing.expectEqual(Command.add, Command.fromString("add").?);
    try testing.expectEqual(Command.list, Command.fromString("list").?);
    try testing.expectEqual(Command.list, Command.fromString("ls").?);
    try testing.expectEqual(Command.show, Command.fromString("show").?);
    try testing.expectEqual(Command.done, Command.fromString("done").?);
    try testing.expectEqual(Command.done, Command.fromString("complete").?);
    try testing.expectEqual(Command.rm, Command.fromString("rm").?);
    try testing.expectEqual(Command.rm, Command.fromString("delete").?);
    try testing.expectEqual(Command.projects, Command.fromString("projects").?);
    try testing.expectEqual(Command.help, Command.fromString("help").?);
    try testing.expectEqual(Command.help, Command.fromString("--help").?);
    try testing.expectEqual(@as(?Command, null), Command.fromString("unknown"));
}
