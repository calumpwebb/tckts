const std = @import("std");
const tckts = @import("tckts");
const cli = @import("../mod.zig");

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    const id_str = args.next() orelse {
        cli.eprint("Error: Missing ticket ID.\n", .{});
        cli.eprint("Usage: tckts rm <ID>\n", .{});
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

    project.removeTicket(ticket_id.number) catch |err| {
        if (err == error.TicketNotFound) {
            cli.eprint("Error: Ticket '{s}' not found.\n", .{id_str});
            return error.TicketNotFound;
        }
        return err;
    };

    try tckts.saveProject(allocator, &project);

    cli.print("Removed {s}-{d}\n", .{ ticket_id.prefix, ticket_id.number });
}
