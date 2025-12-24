const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");
const arg_parser = cli.arg_parser;

// --- constants ---

pub const meta = arg_parser.CommandMeta{
    .name = "init",
    .usage = "init <PREFIX>",
    .short = "Initialize a new project with the given prefix.",
    .options = &.{},
    .examples = &.{
        "tckts init BACKEND",
        "tckts init API",
    },
};

// --- types ---

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var parser = arg_parser.ArgParser(@TypeOf(args.*)).init(allocator, args, meta);
    defer parser.deinit();

    if (parser.parseOrExit() == .exit) return;

    // Get prefix (first positional)
    const prefix = parser.positional(0) orelse {
        cli.eprint("Error: Missing project prefix.\n", .{});
        cli.eprint("Usage: tckts {s}\n", .{meta.usage});
        return error.MissingArgument;
    };

    // Validate prefix - alphanumeric and underscore only
    for (prefix) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') {
            cli.eprint("Error: Prefix must be alphanumeric (A-Z, 0-9, _).\n", .{});
            return error.InvalidArgument;
        }
    }

    const upper_prefix = try cli.toUpperPrefix(allocator, prefix);
    defer allocator.free(upper_prefix);

    tckts.initProject(allocator, upper_prefix) catch |err| {
        if (err == error.ProjectAlreadyExists) {
            cli.eprint("Error: Project '{s}' already exists.\n", .{upper_prefix});
            return err;
        }
        return err;
    };

    cli.print("Initialized project '{s}' in .tckts/{s}.tckts\n", .{ upper_prefix, upper_prefix });
}
