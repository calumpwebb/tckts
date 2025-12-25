const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");
const arg_parser = cli.arg_parser;

// --- constants ---

pub const meta = arg_parser.CommandMeta{
    .name = "done",
    .usage = "done <ID>",
    .short = "Mark a ticket as complete.",
    .options = &.{},
    .examples = &.{
        "tckts done BACKEND-1",
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

    var project = try cli.loadProjectOrError(allocator, ticket_id.prefix);
    defer project.deinit();

    const blocking = project.canComplete(ticket_id.number) catch |err| {
        if (err == error.TicketNotFound) {
            cli.eprint("Error: Ticket '{s}-{d}' not found.\n", .{ ticket_id.prefix, ticket_id.number });
            return error.TicketNotFound;
        }
        return err;
    };
    defer allocator.free(blocking);

    if (blocking.len > 0) {
        cli.eprint("Error: Cannot complete {s}-{d} - blocked by:\n", .{ ticket_id.prefix, ticket_id.number });
        for (blocking) |dep| {
            cli.eprint("  - {s}-{d}\n", .{ dep.prefix, dep.number });
        }
        return error.DependencyNotComplete;
    }

    try project.updateTicket(ticket_id.number, .{ .status = .done });
    try tckts.saveProject(allocator, &project);

    cli.print("Completed {s}-{d}\n", .{ ticket_id.prefix, ticket_id.number });
}
