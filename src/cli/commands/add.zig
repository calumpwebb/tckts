const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");
const arg_parser = cli.arg_parser;

const mem = std.mem;

// --- constants ---

pub const meta = arg_parser.CommandMeta{
    .name = "add",
    .usage = "add <title> [options]",
    .short = "Add a new ticket to a project.",
    .options = &.{
        .{ .short = "-p", .long = "--project", .arg = "<PREFIX>", .desc = "Project prefix (uses default if set)" },
        .{ .short = "-t", .long = "--type", .arg = "<TYPE>", .desc = "bug, feature, task, chore, epic (default: task)" },
        .{ .short = "-m", .long = "--message", .arg = "<DESC>", .desc = "Ticket description" },
        .{ .short = "-d", .long = "--depends", .arg = "<IDs>", .desc = "Comma-separated dependency IDs" },
        .{ .long = "--priority", .arg = "<LEVEL>", .desc = "low, medium, high" },
    },
    .examples = &.{
        "tckts add \"Fix login bug\" -t bug",
        "tckts add \"Auth feature\" -t feature -d PROJ-1",
    },
};

// --- types ---

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var parser = arg_parser.ArgParser(@TypeOf(args.*)).init(allocator, args, meta);
    defer parser.deinit();

    if (parser.parseOrExit() == .exit) return;

    // Get title (first positional)
    const title = parser.positional(0) orelse {
        cli.eprint("Error: Missing ticket title.\n", .{});
        cli.eprint("Usage: tckts {s}\n", .{meta.usage});
        return error.MissingArgument;
    };

    // Get project prefix (from flag or default)
    var default_project: ?[]u8 = null;
    defer if (default_project) |dp| allocator.free(dp);

    const prefix = parser.get("project") orelse blk: {
        default_project = cli.getDefaultProject(allocator);
        if (default_project) |dp| {
            break :blk @as([]const u8, dp);
        } else {
            cli.eprint("Error: Missing required -p/--project flag.\n", .{});
            cli.printAvailableProjects(allocator);
            cli.eprint("Usage: tckts {s}\n", .{meta.usage});
            cli.eprint("Tip: Set a default project in .tckts/config.json\n", .{});
            return error.MissingArgument;
        }
    };

    // Parse ticket type
    const ticket_type: tckts.TicketType = if (parser.get("type")) |type_str|
        tckts.TicketType.fromString(type_str) orelse {
            cli.eprint("Error: Invalid type '{s}'. Use: bug, feature, task, chore, epic\n", .{type_str});
            return error.InvalidArgument;
        }
    else
        .task;

    // Parse priority
    const priority: ?tckts.Priority = if (parser.get("priority")) |prio_str|
        tckts.Priority.fromString(prio_str) orelse {
            cli.eprint("Error: Invalid priority '{s}'. Use: low, medium, high\n", .{prio_str});
            return error.InvalidArgument;
        }
    else
        null;

    const description = parser.get("message") orelse "";
    const depends_str = parser.get("depends");

    const upper_prefix = try cli.toUpperPrefix(allocator, prefix);
    defer allocator.free(upper_prefix);

    var project = try cli.loadProjectOrError(allocator, upper_prefix);
    defer project.deinit();

    // Parse dependencies
    var depends: std.ArrayList(tckts.TicketId) = .empty;
    defer {
        for (depends.items) |*d| d.deinit(allocator);
        depends.deinit(allocator);
    }

    if (depends_str) |ds| {
        var parts = mem.splitSequence(u8, ds, ",");
        while (parts.next()) |part| {
            const trimmed = mem.trim(u8, part, " \t");
            if (trimmed.len == 0) continue;
            const dep_id = tckts.TicketId.parse(allocator, trimmed) catch {
                cli.eprint("Error: Invalid dependency ID '{s}'.\n", .{trimmed});
                return error.InvalidArgument;
            };
            try depends.append(allocator, dep_id);
        }
    }

    // Validate limits with friendly messages showing actual vs max
    if (title.len > tckts.max_title_length_bytes) {
        cli.eprint("Error: Title is {d} characters (max {d}).\n", .{ title.len, tckts.max_title_length_bytes });
        return error.TitleTooLong;
    }
    if (description.len > tckts.max_description_length_bytes) {
        cli.eprint("Error: Description is {d} bytes (max {d}).\n", .{ description.len, tckts.max_description_length_bytes });
        return error.DescriptionTooLong;
    }
    if (depends.items.len > tckts.max_dependencies_per_ticket) {
        cli.eprint("Error: Too many dependencies: {d} (max {d}).\n", .{ depends.items.len, tckts.max_dependencies_per_ticket });
        return error.TooManyDependencies;
    }

    const ticket = try project.addTicket(ticket_type, title, description, depends.items, priority);
    try tckts.saveProject(allocator, &project);

    cli.print("Created {s}-{d}: {s}\n", .{ upper_prefix, ticket.id.number, ticket.title });
}
