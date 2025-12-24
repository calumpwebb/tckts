const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    const project_list = try tckts.listProjects(allocator);
    defer {
        for (project_list) |p| allocator.free(p);
        allocator.free(project_list);
    }

    if (project_list.len == 0) {
        cli.print("No projects initialized.\n", .{});
        cli.print("Run 'tckts init <PREFIX>' to create one.\n", .{});
        return;
    }

    cli.print("\nProjects:\n", .{});
    for (project_list) |prefix| {
        var project = tckts.loadProject(allocator, prefix) catch continue;
        defer project.deinit();

        var pending: usize = 0;
        var done_count: usize = 0;
        for (project.tickets.items) |ticket| {
            if (ticket.status == .done) {
                done_count += 1;
            } else {
                pending += 1;
            }
        }

        cli.print("  {s}: {d} pending, {d} done\n", .{ prefix, pending, done_count });
    }
    cli.print("\n", .{});
}
