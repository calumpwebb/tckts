const std = @import("std");
const tckts = @import("tckts");
const cli = @import("../mod.zig");

const mem = std.mem;

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    const id_str = args.next() orelse {
        cli.eprint("Error: Missing ticket ID.\n", .{});
        cli.eprint("Usage: tckts show <ID>\n", .{});
        return error.MissingArgument;
    };

    var ticket_id = tckts.TicketId.parse(allocator, id_str) catch {
        cli.eprint("Error: Invalid ticket ID '{s}'.\n", .{id_str});
        return error.InvalidArgument;
    };
    defer ticket_id.deinit(allocator);

    var project = tckts.loadProject(allocator, ticket_id.prefix) catch |err| {
        if (err == error.ProjectNotFound) {
            cli.eprint("Error: Project '{s}' not found.\n", .{ticket_id.prefix});
            cli.printAvailableProjects(allocator);
            return error.ProjectNotInitialized;
        }
        return err;
    };
    defer project.deinit();

    const ticket = project.findTicket(ticket_id.number) orelse {
        cli.eprint("Error: Ticket '{s}' not found.\n", .{id_str});
        return error.TicketNotFound;
    };

    cli.print("\n", .{});
    cli.print("--- {s}-{d} ---\n", .{ ticket.id.prefix, ticket.id.number });
    cli.print("Title:    {s}\n", .{ticket.title});
    cli.print("Type:     {s}\n", .{ticket.ticket_type.toString()});
    cli.print("Status:   {s}\n", .{ticket.status.toString()});
    cli.print("Created:  {s}\n", .{ticket.created});

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

    if (ticket.description.len > 0) {
        cli.print("\nDescription:\n", .{});
        var lines = mem.splitSequence(u8, ticket.description, "\n");
        while (lines.next()) |line| {
            cli.print("  {s}\n", .{line});
        }
    }

    cli.print("\n", .{});
}
