const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");
const arg_parser = cli.arg_parser;

const mem = std.mem;

// --- constants ---

pub const meta = arg_parser.CommandMeta{
    .name = "show",
    .usage = "show <ID>",
    .short = "Show detailed information about a ticket.",
    .options = &.{},
    .examples = &.{
        "tckts show BACKEND-1",
        "tckts show TCKTS-42",
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

    const ticket = project.findTicket(ticket_id.number) orelse {
        cli.eprint("Error: Ticket '{s}-{d}' not found.\n", .{ ticket_id.prefix, ticket_id.number });
        return error.TicketNotFound;
    };

    cli.print("\n", .{});
    cli.print("--- {s}-{d} ---\n", .{ ticket.id.prefix, ticket.id.number });
    cli.print("Title:    {s}\n", .{ticket.title});
    cli.print("Type:     {s}\n", .{ticket.ticket_type.toString()});
    cli.print("Status:   {s}\n", .{ticket.status.toString()});
    cli.print("Created:  {s}\n", .{ticket.created_at});

    if (ticket.priority) |p| {
        cli.print("Priority: {s}\n", .{p.toString()});
    }

    if (ticket.depends.len > 0) {
        cli.print("Depends:  ", .{});
        for (ticket.depends, 0..) |dep, i| {
            if (i > 0) cli.print(", ", .{});
            cli.print("{s}-{d}", .{ dep.prefix, dep.number });
        }
        cli.print("\n", .{});
    }

    if (ticket.history.len > 0) {
        cli.print("\nHistory:\n", .{});
        for (ticket.history) |entry| {
            cli.print("  {s: <12} {s}\n", .{ entry.status.toString(), entry.at });
        }
    }

    if (ticket.description.len > 0) {
        cli.print("\nDescription:\n", .{});
        var lines = mem.splitSequence(u8, ticket.description, "\n");
        while (lines.next()) |line| {
            cli.print("  {s}\n", .{line});
        }
    }

    cli.print("\n", .{});
}
