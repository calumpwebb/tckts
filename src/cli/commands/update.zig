const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");
const arg_parser = cli.arg_parser;

// --- constants ---

pub const meta = arg_parser.CommandMeta{
    .name = "update",
    .usage = "update <ID> [options]",
    .short = "Update a ticket's title, description, or status.",
    .options = &.{
        .{ .name = "--title", .short = "-t", .description = "Set new title", .takes_value = true },
        .{ .name = "--description", .short = "-d", .description = "Set new description", .takes_value = true },
        .{ .name = "--status", .short = "-s", .description = "Set status (pending, in_progress, blocked, done)", .takes_value = true },
    },
    .examples = &.{
        "tckts update TODO-1 --status done",
        "tckts update TODO-1 --title \"New title\"",
        "tckts update TODO-1 -s in_progress -t \"Updated\"",
    },
};

// --- types ---

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var parser = arg_parser.ArgParser(@TypeOf(args.*)).init(allocator, args, meta);
    defer parser.deinit();

    if (parser.parseOrExit() == .exit) return;

    // Get ticket ID (first positional)
    const id_str = parser.positional(0) orelse {
        cli.eprint("Error: Missing ticket ID.\n", .{});
        cli.eprint("Usage: tckts {s}\n", .{meta.usage});
        return error.MissingArgument;
    };

    var ticket_id = tckts.TicketId.parse(allocator, id_str) catch {
        cli.eprint("Error: Invalid ticket ID '{s}'.\n", .{id_str});
        return error.InvalidArgument;
    };
    defer ticket_id.deinit(allocator);

    // Parse options
    const new_title = parser.option("title");
    const new_description = parser.option("description");
    const status_str = parser.option("status");

    // At least one option required
    if (new_title == null and new_description == null and status_str == null) {
        cli.eprint("Error: At least one of --title, --description, or --status required.\n", .{});
        return error.MissingArgument;
    }

    // Parse status if provided
    var new_status: ?tckts.Status = null;
    if (status_str) |s| {
        new_status = std.meta.stringToEnum(tckts.Status, s) orelse {
            cli.eprint("Error: Invalid status '{s}'. Valid: pending, in_progress, blocked, done.\n", .{s});
            return error.InvalidArgument;
        };
    }

    // Load project
    var project = try cli.loadProjectOrError(allocator, ticket_id.prefix);
    defer project.deinit();

    // Check dependencies if marking done
    if (new_status) |status| {
        if (status == .done) {
            const blocking = project.canComplete(ticket_id.number) catch |err| {
                if (err == error.TicketNotFound) {
                    cli.eprint("Error: Ticket '{s}-{d}' not found.\n", .{ ticket_id.prefix, ticket_id.number });
                    return error.TicketNotFound;
                }
                return err;
            };
            defer allocator.free(blocking);

            if (blocking.len > 0) {
                cli.eprint("Error: Cannot mark {s}-{d} as done - blocked by:\n", .{ ticket_id.prefix, ticket_id.number });
                for (blocking) |dep| {
                    cli.eprint("  - {s}-{d}\n", .{ dep.prefix, dep.number });
                }
                return error.DependencyNotComplete;
            }
        }
    }

    // Perform update
    try project.updateTicket(ticket_id.number, .{
        .title = new_title,
        .description = new_description,
        .status = new_status,
    });

    try tckts.saveProject(allocator, &project);

    // Print confirmation
    if (new_status) |status| {
        const status_name = @tagName(status);
        cli.print("Updated {s}-{d} status to {s}\n", .{ ticket_id.prefix, ticket_id.number, status_name });
    } else {
        cli.print("Updated {s}-{d}\n", .{ ticket_id.prefix, ticket_id.number });
    }
}
