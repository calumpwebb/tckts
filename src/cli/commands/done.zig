const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var ticket_id = try cli.parseTicketIdArg(allocator, args, "done");
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

    try project.markDone(ticket_id.number);
    try tckts.saveProject(allocator, &project);

    cli.print("Completed {s}-{d}\n", .{ ticket_id.prefix, ticket_id.number });
}
