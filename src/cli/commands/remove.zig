const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");
const arg_parser = cli.arg_parser;

// --- constants ---

pub const meta = arg_parser.CommandMeta{
    .name = "remove",
    .usage = "remove <ID>",
    .short = "Remove a ticket permanently.",
    .options = &.{},
    .examples = &.{
        "tckts remove BACKEND-1",
        "tckts rm BACKEND-1",
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

    project.removeTicket(ticket_id.number) catch |err| {
        if (err == error.TicketNotFound) {
            cli.eprint("Error: Ticket '{s}-{d}' not found.\n", .{ ticket_id.prefix, ticket_id.number });
            return error.TicketNotFound;
        }
        return err;
    };

    try tckts.saveProject(allocator, &project);

    cli.print("Removed {s}-{d}\n", .{ ticket_id.prefix, ticket_id.number });
}
