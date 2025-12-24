const std = @import("std");

const tckts = @import("tckts");

const mem = std.mem;

// --- constants ---

const stdout_buffer_size_bytes = 8192;
const stderr_buffer_size_bytes = 4096;

// --- types ---

pub fn print(comptime format: []const u8, args: anytype) void {
    const stdout = std.fs.File.stdout();
    var buf: [stdout_buffer_size_bytes]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, format, args) catch return;
    _ = stdout.write(msg) catch {};
}

pub fn eprint(comptime format: []const u8, args: anytype) void {
    const stderr = std.fs.File.stderr();
    var buf: [stderr_buffer_size_bytes]u8 = undefined;
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

/// Get default project from config, returns null if not configured
pub fn getDefaultProject(allocator: std.mem.Allocator) ?[]u8 {
    var config = tckts.loadConfig(allocator) catch return null;
    defer config.deinit(allocator);

    if (config.default_project) |p| {
        return allocator.dupe(u8, p) catch return null;
    }
    return null;
}

/// Convert a prefix string to uppercase, allocating a new buffer
pub fn toUpperPrefix(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    var upper = try allocator.alloc(u8, prefix.len);
    for (prefix, 0..) |c, i| {
        upper[i] = std.ascii.toUpper(c);
    }
    return upper;
}

/// Load a project by prefix, handling ProjectNotFound with user-friendly error
pub fn loadProjectOrError(allocator: std.mem.Allocator, prefix: []const u8) !tckts.Project {
    return tckts.loadProject(allocator, prefix) catch |err| {
        if (err == error.ProjectNotFound) {
            eprint("Error: Project '{s}' not found.\n", .{prefix});
            printAvailableProjects(allocator);
            return error.ProjectNotInitialized;
        }
        return err;
    };
}

/// Parse a ticket ID from command args with user-friendly errors
pub fn parseTicketIdArg(allocator: std.mem.Allocator, args: anytype, cmd_name: []const u8) !tckts.TicketId {
    const id_str = args.next() orelse {
        eprint("Error: Missing ticket ID.\n", .{});
        eprint("Usage: tckts {s} <ID>\n", .{cmd_name});
        return error.MissingArgument;
    };

    return tckts.TicketId.parse(allocator, id_str) catch {
        eprint("Error: Invalid ticket ID '{s}'.\n", .{id_str});
        return error.InvalidArgument;
    };
}

// --- types ---

pub const Command = enum {
    init,
    add,
    list,
    show,
    start,
    done,
    remove,
    projects,
    quickstart,
    version,
    help,

    pub fn fromString(s: []const u8) ?Command {
        const commands = .{
            .{ "init", Command.init },
            .{ "add", Command.add },
            .{ "list", Command.list },
            .{ "ls", Command.list },
            .{ "show", Command.show },
            .{ "start", Command.start },
            .{ "done", Command.done },
            .{ "complete", Command.done },
            .{ "rm", Command.remove },
            .{ "delete", Command.remove },
            .{ "remove", Command.remove },
            .{ "projects", Command.projects },
            .{ "quickstart", Command.quickstart },
            .{ "version", Command.version },
            .{ "--version", Command.version },
            .{ "-v", Command.version },
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

    // TODO: (calum) anyway to make sure we have all the commands covered?
    try testing.expectEqual(Command.init, Command.fromString("init").?);
    try testing.expectEqual(Command.add, Command.fromString("add").?);
    try testing.expectEqual(Command.list, Command.fromString("list").?);
    try testing.expectEqual(Command.list, Command.fromString("ls").?);
    try testing.expectEqual(Command.show, Command.fromString("show").?);
    try testing.expectEqual(Command.start, Command.fromString("start").?);
    try testing.expectEqual(Command.done, Command.fromString("done").?);
    try testing.expectEqual(Command.done, Command.fromString("complete").?);
    try testing.expectEqual(Command.remove, Command.fromString("rm").?);
    try testing.expectEqual(Command.remove, Command.fromString("delete").?);
    try testing.expectEqual(Command.projects, Command.fromString("projects").?);
    try testing.expectEqual(Command.quickstart, Command.fromString("quickstart").?);
    try testing.expectEqual(Command.version, Command.fromString("version").?);
    try testing.expectEqual(Command.version, Command.fromString("--version").?);
    try testing.expectEqual(Command.version, Command.fromString("-v").?);
    try testing.expectEqual(Command.help, Command.fromString("help").?);
    try testing.expectEqual(Command.help, Command.fromString("--help").?);
    try testing.expectEqual(@as(?Command, null), Command.fromString("unknown"));
}
