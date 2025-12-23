const std = @import("std");
const tckts = @import("tckts");
const cli = @import("../mod.zig");

const mem = std.mem;

const default_prefix = "MAIN";

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var prefix: []const u8 = default_prefix;
    var show_all = false;
    var show_blocked = false;

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-a") or mem.eql(u8, arg, "--all")) {
            show_all = true;
        } else if (mem.eql(u8, arg, "--pending")) {
            show_all = false;
        } else if (mem.eql(u8, arg, "--blocked")) {
            show_blocked = true;
        } else if (!mem.startsWith(u8, arg, "-")) {
            prefix = arg;
        }
    }

    const upper_prefix = try cli.toUpperPrefix(allocator, prefix);
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
