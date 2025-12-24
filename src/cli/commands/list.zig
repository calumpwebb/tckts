const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");
const arg_parser = cli.arg_parser;

const mem = std.mem;

// --- constants ---

pub const meta = arg_parser.CommandMeta{
    .name = "list",
    .usage = "list [PREFIX] [options]",
    .short = "List tickets for a project.",
    .options = &.{
        .{ .short = "-a", .long = "--all", .desc = "Show all tickets (including completed)" },
        .{ .short = "-s", .long = "--status", .arg = "<STATUS>", .desc = "Filter by status: pending, in-progress, blocked, done" },
        .{ .long = "--blocked", .desc = "Show only blocked tickets" },
    },
    .examples = &.{
        "tckts list",
        "tckts list BACKEND",
        "tckts list --status in-progress",
        "tckts list -a",
    },
};

// --- types ---

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var parser = arg_parser.ArgParser(@TypeOf(args.*)).init(allocator, args, meta);
    defer parser.deinit();

    if (parser.parseOrExit() == .exit) return;

    // Get flags
    const show_all_flag = parser.flag("all");
    const show_blocked = parser.flag("blocked");
    var show_all = show_all_flag;

    // Parse status filter
    var status_filter: ?tckts.Status = null;
    if (parser.get("status")) |status_str| {
        if (mem.eql(u8, status_str, "pending")) {
            status_filter = .pending;
        } else if (mem.eql(u8, status_str, "in-progress") or mem.eql(u8, status_str, "in_progress")) {
            status_filter = .in_progress;
        } else if (mem.eql(u8, status_str, "blocked")) {
            status_filter = .blocked;
        } else if (mem.eql(u8, status_str, "done")) {
            status_filter = .done;
            show_all = true;
        } else {
            cli.eprint("Error: Invalid status '{s}'. Use: pending, in-progress, blocked, done\n", .{status_str});
            return error.InvalidArgument;
        }
    }

    // Get project prefix (from positional or default)
    var default_project: ?[]u8 = null;
    defer if (default_project) |dp| allocator.free(dp);

    const prefix = parser.positional(0) orelse blk: {
        default_project = cli.getDefaultProject(allocator);
        if (default_project) |dp| {
            break :blk @as([]const u8, dp);
        } else {
            cli.eprint("Error: Missing required project prefix.\n", .{});
            cli.printAvailableProjects(allocator);
            cli.eprint("Usage: tckts {s}\n", .{meta.usage});
            cli.eprint("Tip: Set a default project in .tckts/config.json\n", .{});
            return error.MissingArgument;
        }
    };

    const upper_prefix = try cli.toUpperPrefix(allocator, prefix);
    defer allocator.free(upper_prefix);

    var project = try cli.loadProjectOrError(allocator, upper_prefix);
    defer project.deinit();

    if (project.tickets.items.len == 0) {
        cli.print("No tickets in project '{s}'.\n", .{upper_prefix});
        return;
    }

    cli.print("\n{s} Tickets:\n", .{upper_prefix});
    cli.print("---------------------------------------------\n", .{});

    var displayed: usize = 0;
    for (project.tickets.items) |ticket| {
        if (!show_all and ticket.status == .done) continue;

        // Filter by status if specified
        if (status_filter) |sf| {
            if (ticket.status != sf) continue;
        }

        const blocking = try project.canComplete(ticket.id.number);
        defer allocator.free(blocking);
        const is_blocked = blocking.len > 0;

        // For --blocked flag, show both explicit blocked status and dependency-blocked
        if (show_blocked and ticket.status != .blocked and !is_blocked) continue;

        const status_char: u8 = switch (ticket.status) {
            .done => 'x',
            .blocked => 'B',
            else => ' ',
        };

        cli.print("[{c}] {s}-{d} | {s} | {s}", .{
            status_char,
            ticket.id.prefix,
            ticket.id.number,
            ticket.ticket_type.toString(),
            ticket.title,
        });

        // Show [BLOCKED] for explicit blocked status or dependency-blocked
        if (ticket.status == .blocked or is_blocked) cli.print(" [BLOCKED]", .{});

        if (ticket.priority) |p| {
            const prio: []const u8 = switch (p) {
                .high => " !!!",
                .medium => " !!",
                .low => " !",
            };
            cli.print("{s}", .{prio});
        }

        cli.print("\n", .{});
        displayed += 1;
    }

    if (displayed == 0) {
        if (show_blocked) {
            cli.print("No blocked tickets.\n", .{});
        } else {
            cli.print("No pending tickets.\n", .{});
        }
    }

    cli.print("\n", .{});
}
