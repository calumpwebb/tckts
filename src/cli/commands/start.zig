const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var ticket_id = try cli.parseTicketIdArg(allocator, args, "start");
    defer ticket_id.deinit(allocator);

    var project = try cli.loadProjectOrError(allocator, ticket_id.prefix);
    defer project.deinit();

    project.markInProgress(ticket_id.number) catch |err| {
        if (err == error.TicketNotFound) {
            cli.eprint("Error: Ticket '{s}-{d}' not found.\n", .{ ticket_id.prefix, ticket_id.number });
            return error.TicketNotFound;
        }
        if (err == error.AlreadyDone) {
            cli.eprint("Error: Ticket '{s}-{d}' is already done.\n", .{ ticket_id.prefix, ticket_id.number });
            return error.AlreadyDone;
        }
        return err;
    };

    try tckts.saveProject(allocator, &project);

    cli.print("Started {s}-{d}\n", .{ ticket_id.prefix, ticket_id.number });
}
