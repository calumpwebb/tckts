const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");

const mem = std.mem;

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var prefix: ?[]const u8 = null;
    var show_all = false;
    var show_blocked = false;
    var status_filter: ?tckts.Status = null;

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-a") or mem.eql(u8, arg, "--all")) {
            show_all = true;
        } else if (mem.eql(u8, arg, "--blocked")) {
            show_blocked = true;
        } else if (mem.eql(u8, arg, "-s") or mem.eql(u8, arg, "--status")) {
            const status_str = args.next() orelse {
                cli.eprint("Error: --status requires a value (pending, in-progress, done)\n", .{});
                return error.MissingArgument;
            };
            if (mem.eql(u8, status_str, "pending")) {
                status_filter = .pending;
            } else if (mem.eql(u8, status_str, "in-progress") or mem.eql(u8, status_str, "in_progress")) {
                status_filter = .in_progress;
            } else if (mem.eql(u8, status_str, "done")) {
                status_filter = .done;
                show_all = true;
            } else {
                cli.eprint("Error: Invalid status '{s}'. Use: pending, in-progress, done\n", .{status_str});
                return error.InvalidArgument;
            }
        } else if (!mem.startsWith(u8, arg, "-")) {
            prefix = arg;
        }
    }

    // Try default project from config if not specified
    var default_project: ?[]u8 = null;
    defer if (default_project) |dp| allocator.free(dp);

    if (prefix == null) {
        default_project = cli.getDefaultProject(allocator);
        if (default_project) |dp| {
            prefix = dp;
        } else {
            cli.eprint("Error: Missing required project prefix.\n", .{});
            const projects = try tckts.listProjects(allocator);
            defer {
                for (projects) |p| allocator.free(p);
                allocator.free(projects);
            }
            if (projects.len > 0) {
                cli.eprint("Available projects: ", .{});
                for (projects, 0..) |p, i| {
                    if (i > 0) cli.eprint(", ", .{});
                    cli.eprint("{s}", .{p});
                }
                cli.eprint("\n", .{});
            } else {
                cli.eprint("No projects exist. Run 'tckts init <PREFIX>' to create one.\n", .{});
            }
            cli.eprint("Usage: tckts list <PREFIX>\n", .{});
            cli.eprint("Tip: Set a default project in .tckts/config.json\n", .{});
            return error.MissingArgument;
        }
    }

    const upper_prefix = try cli.toUpperPrefix(allocator, prefix.?);
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

        if (show_blocked and !is_blocked) continue;

        const status_char: u8 = if (ticket.status == .done) 'x' else ' ';

        cli.print("[{c}] {s}-{d} | {s} | {s}", .{
            status_char,
            ticket.id.prefix,
            ticket.id.number,
            ticket.ticket_type.toString(),
            ticket.title,
        });

        if (is_blocked) cli.print(" [BLOCKED]", .{});

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
