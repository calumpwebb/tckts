const std = @import("std");

const tckts = @import("tckts");

const cli = @import("../mod.zig");

const mem = std.mem;

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var title: ?[]const u8 = null;
    var prefix: ?[]const u8 = null;
    var ticket_type: tckts.TicketType = .task;
    var description: []const u8 = "";
    var priority: ?tckts.Priority = null;
    var depends_str: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-p") or mem.eql(u8, arg, "--project")) {
            prefix = args.next() orelse return error.MissingArgument;
        } else if (mem.eql(u8, arg, "-t") or mem.eql(u8, arg, "--type")) {
            const type_str = args.next() orelse return error.MissingArgument;
            ticket_type = tckts.TicketType.fromString(type_str) orelse {
                cli.eprint("Error: Invalid type '{s}'. Use: bug, feature, task, chore, epic\n", .{type_str});
                return error.InvalidArgument;
            };
        } else if (mem.eql(u8, arg, "-m") or mem.eql(u8, arg, "--message")) {
            description = args.next() orelse return error.MissingArgument;
        } else if (mem.eql(u8, arg, "-d") or mem.eql(u8, arg, "--depends")) {
            depends_str = args.next() orelse return error.MissingArgument;
        } else if (mem.eql(u8, arg, "--priority")) {
            const prio_str = args.next() orelse return error.MissingArgument;
            priority = tckts.Priority.fromString(prio_str) orelse {
                cli.eprint("Error: Invalid priority '{s}'. Use: low, medium, high\n", .{prio_str});
                return error.InvalidArgument;
            };
        } else if (!mem.startsWith(u8, arg, "-")) {
            title = arg;
        }
    }

    if (title == null) {
        cli.eprint("Error: Missing ticket title.\n", .{});
        cli.eprint("Usage: tckts add -p <PREFIX> <title>\n", .{});
        return error.MissingArgument;
    }

    // Try default project from config if not specified
    var default_project: ?[]u8 = null;
    defer if (default_project) |dp| allocator.free(dp);

    if (prefix == null) {
        default_project = cli.getDefaultProject(allocator);
        if (default_project) |dp| {
            prefix = dp;
        } else {
            cli.eprint("Error: Missing required -p/--project flag.\n", .{});
            const projects = try tckts.listProjects(allocator);
            defer {
                for (projects) |p| allocator.free(p);
                allocator.free(projects);
            }
            if (projects.len > 0) {
                cli.eprint("Available projects: ", .{});
                for (projects, 0..) |p, i| {
                    if (i > 0) cli.eprint(", ", .{});
                    cli.eprint("{s}", .{p});
                }
                cli.eprint("\n", .{});
            } else {
                cli.eprint("No projects exist. Run 'tckts init <PREFIX>' to create one.\n", .{});
            }
            cli.eprint("Usage: tckts add -p <PREFIX> <title>\n", .{});
            cli.eprint("Tip: Set a default project in .tckts/config.json\n", .{});
            return error.MissingArgument;
        }
    }

    const upper_prefix = try cli.toUpperPrefix(allocator, prefix.?);
    defer allocator.free(upper_prefix);

    var project = try cli.loadProjectOrError(allocator, upper_prefix);
    defer project.deinit();

    // Parse dependencies
    var depends: std.ArrayList(tckts.TicketId) = .empty;
    defer {
        for (depends.items) |*d| d.deinit(allocator);
        depends.deinit(allocator);
    }

    if (depends_str) |ds| {
        var parts = mem.splitSequence(u8, ds, ",");
        while (parts.next()) |part| {
            const trimmed = mem.trim(u8, part, " \t");
            if (trimmed.len == 0) continue;
            const dep_id = tckts.TicketId.parse(allocator, trimmed) catch {
                cli.eprint("Error: Invalid dependency ID '{s}'.\n", .{trimmed});
                return error.InvalidArgument;
            };
            try depends.append(allocator, dep_id);
        }
    }

    // Validate limits with friendly messages showing actual vs max
    if (title.?.len > tckts.max_title_length_bytes) {
        cli.eprint("Error: Title is {d} characters (max {d}).\n", .{ title.?.len, tckts.max_title_length_bytes });
        return error.TitleTooLong;
    }
    if (description.len > tckts.max_description_length_bytes) {
        cli.eprint("Error: Description is {d} bytes (max {d}).\n", .{ description.len, tckts.max_description_length_bytes });
        return error.DescriptionTooLong;
    }
    if (depends.items.len > tckts.max_dependencies_per_ticket) {
        cli.eprint("Error: Too many dependencies: {d} (max {d}).\n", .{ depends.items.len, tckts.max_dependencies_per_ticket });
        return error.TooManyDependencies;
    }

    const ticket = try project.addTicket(ticket_type, title.?, description, depends.items, priority);
    try tckts.saveProject(allocator, &project);

    cli.print("Created {s}-{d}: {s}\n", .{ upper_prefix, ticket.id.number, ticket.title });
}
