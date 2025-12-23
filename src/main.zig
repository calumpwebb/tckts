const std = @import("std");
const tckts = @import("tckts");

const mem = std.mem;
const process = std.process;

// --- constants ---

const version = "0.1.0";
const default_prefix = "MAIN";

// --- types ---

const Command = enum {
    init,
    add,
    list,
    show,
    done,
    rm,
    projects,
    help,

    fn fromString(s: []const u8) ?Command {
        const commands = .{
            .{ "init", Command.init },
            .{ "add", Command.add },
            .{ "list", Command.list },
            .{ "ls", Command.list },
            .{ "show", Command.show },
            .{ "done", Command.done },
            .{ "complete", Command.done },
            .{ "rm", Command.rm },
            .{ "delete", Command.rm },
            .{ "remove", Command.rm },
            .{ "projects", Command.projects },
            .{ "help", Command.help },
            .{ "--help", Command.help },
            .{ "-h", Command.help },
        };

        inline for (commands) |cmd| {
            if (mem.eql(u8, s, cmd[0])) return cmd[1];
        }
        return null;
    }
};

// --- I/O helpers ---

fn print(comptime format: []const u8, args: anytype) void {
    const stdout = std.fs.File.stdout();
    var buf: [8192]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, format, args) catch return;
    _ = stdout.write(msg) catch {};
}

fn eprint(comptime format: []const u8, args: anytype) void {
    const stderr = std.fs.File.stderr();
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, format, args) catch return;
    _ = stderr.write(msg) catch {};
}

// --- main ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    run(allocator) catch |err| {
        switch (err) {
            error.MissingCommand => {
                printUsage();
                process.exit(1);
            },
            error.UnknownCommand => {
                eprint("Error: Unknown command. Run 'tckts help' for usage.\n", .{});
                process.exit(1);
            },
            error.MissingArgument => {
                eprint("Error: Missing required argument.\n", .{});
                process.exit(1);
            },
            error.InvalidArgument => {
                eprint("Error: Invalid argument.\n", .{});
                process.exit(1);
            },
            error.ProjectNotInitialized, error.ProjectNotFound => {
                eprint("Error: Project not initialized. Run 'tckts init <PREFIX>' first.\n", .{});
                process.exit(1);
            },
            error.TicketNotFound => {
                eprint("Error: Ticket not found.\n", .{});
                process.exit(1);
            },
            error.DependencyNotComplete => {
                eprint("Error: Cannot complete ticket - dependencies not done.\n", .{});
                process.exit(1);
            },
            error.ProjectAlreadyExists => {
                eprint("Error: Project already exists.\n", .{});
                process.exit(1);
            },
            else => {
                eprint("Error: {any}\n", .{err});
                process.exit(2);
            },
        }
    };
}

fn run(allocator: std.mem.Allocator) !void {
    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    const cmd_str = args.next() orelse {
        printUsage();
        return error.MissingCommand;
    };

    const cmd = Command.fromString(cmd_str) orelse {
        eprint("Unknown command: {s}\n", .{cmd_str});
        return error.UnknownCommand;
    };

    switch (cmd) {
        .init => try cmdInit(allocator, &args),
        .add => try cmdAdd(allocator, &args),
        .list => try cmdList(allocator, &args),
        .show => try cmdShow(allocator, &args),
        .done => try cmdDone(allocator, &args),
        .rm => try cmdRm(allocator, &args),
        .projects => try cmdProjects(allocator),
        .help => printHelp(),
    }
}

fn printUsage() void {
    print(
        \\tckts - CLI ticket tracker v{s}
        \\
        \\Usage: tckts <command> [options]
        \\
        \\Commands:
        \\  init <PREFIX>     Initialize a new project
        \\  add <title>       Add a new ticket
        \\  list [PREFIX]     List tickets
        \\  show <ID>         Show ticket details
        \\  done <ID>         Mark ticket as complete
        \\  rm <ID>           Remove a ticket
        \\  projects          List all projects
        \\  help              Show this help
        \\
        \\Run 'tckts help' for detailed usage.
        \\
    , .{version});
}

fn printHelp() void {
    print(
        \\tckts - CLI ticket tracker v{s}
        \\
        \\A plain-text ticket tracker that stores tickets in your repository.
        \\Tickets are human-readable and LLM-friendly.
        \\
        \\USAGE:
        \\    tckts <command> [options]
        \\
        \\COMMANDS:
        \\    init <PREFIX>
        \\        Initialize a new project with the given prefix.
        \\        The prefix becomes part of ticket IDs (e.g., BACKEND-1).
        \\        Example: tckts init BACKEND
        \\
        \\    add <title> [options]
        \\        Add a new ticket to a project.
        \\        Options:
        \\          -p, --project <PREFIX>   Project prefix (default: MAIN)
        \\          -t, --type <TYPE>        Ticket type: bug, feature, task, chore
        \\          -d, --depends <IDs>      Comma-separated dependency IDs
        \\          -m, --message <DESC>     Ticket description
        \\          --priority <LEVEL>       Priority: low, medium, high
        \\        Example: tckts add "Fix login bug" -t bug -p BACKEND
        \\
        \\    list [PREFIX] [options]
        \\        List tickets for a project.
        \\        Options:
        \\          -a, --all       Show all tickets (including completed)
        \\          --pending       Show only pending tickets (default)
        \\          --blocked       Show only blocked tickets
        \\        Example: tckts list BACKEND --all
        \\
        \\    show <ID>
        \\        Show detailed information about a ticket.
        \\        Example: tckts show BACKEND-1
        \\
        \\    done <ID>
        \\        Mark a ticket as complete.
        \\        Fails if the ticket has incomplete dependencies.
        \\        Example: tckts done BACKEND-1
        \\
        \\    rm <ID>
        \\        Remove a ticket. Also removes it from dependency lists.
        \\        Example: tckts rm BACKEND-1
        \\
        \\    projects
        \\        List all initialized projects.
        \\
        \\    help
        \\        Show this help message.
        \\
        \\FILES:
        \\    Tickets are stored in .tckts/ directory at the repository root.
        \\    Each project has its own file: .tckts/BACKEND.tckts
        \\
        \\EXAMPLES:
        \\    tckts init BACKEND
        \\    tckts add "Set up database" -p BACKEND -t task
        \\    tckts add "Implement auth" -p BACKEND -t feature -d BACKEND-1
        \\    tckts list BACKEND
        \\    tckts done BACKEND-1
        \\
    , .{version});
}

// --- commands ---

fn cmdInit(allocator: std.mem.Allocator, args: anytype) !void {
    const prefix = args.next() orelse {
        eprint("Error: Missing project prefix.\n", .{});
        eprint("Usage: tckts init <PREFIX>\n", .{});
        return error.MissingArgument;
    };

    // Validate prefix
    for (prefix) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') {
            eprint("Error: Prefix must be alphanumeric (A-Z, 0-9, _).\n", .{});
            return error.InvalidArgument;
        }
    }

    // Convert to uppercase
    var upper_prefix = try allocator.alloc(u8, prefix.len);
    defer allocator.free(upper_prefix);
    for (prefix, 0..) |c, i| {
        upper_prefix[i] = std.ascii.toUpper(c);
    }

    tckts.initProject(allocator, upper_prefix) catch |err| {
        if (err == error.ProjectAlreadyExists) {
            eprint("Error: Project '{s}' already exists.\n", .{upper_prefix});
            return err;
        }
        return err;
    };

    print("Initialized project '{s}' in .tckts/{s}.tckts\n", .{ upper_prefix, upper_prefix });
}

fn cmdAdd(allocator: std.mem.Allocator, args: anytype) !void {
    var title: ?[]const u8 = null;
    var prefix: []const u8 = default_prefix;
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
                eprint("Error: Invalid type '{s}'. Use: bug, feature, task, chore\n", .{type_str});
                return error.InvalidArgument;
            };
        } else if (mem.eql(u8, arg, "-m") or mem.eql(u8, arg, "--message")) {
            description = args.next() orelse return error.MissingArgument;
        } else if (mem.eql(u8, arg, "-d") or mem.eql(u8, arg, "--depends")) {
            depends_str = args.next() orelse return error.MissingArgument;
        } else if (mem.eql(u8, arg, "--priority")) {
            const prio_str = args.next() orelse return error.MissingArgument;
            priority = tckts.Priority.fromString(prio_str) orelse {
                eprint("Error: Invalid priority '{s}'. Use: low, medium, high\n", .{prio_str});
                return error.InvalidArgument;
            };
        } else if (!mem.startsWith(u8, arg, "-")) {
            title = arg;
        }
    }

    if (title == null) {
        eprint("Error: Missing ticket title.\n", .{});
        eprint("Usage: tckts add <title> [options]\n", .{});
        return error.MissingArgument;
    }

    // Convert prefix to uppercase
    var upper_prefix = try allocator.alloc(u8, prefix.len);
    defer allocator.free(upper_prefix);
    for (prefix, 0..) |c, i| {
        upper_prefix[i] = std.ascii.toUpper(c);
    }

    // Load project
    var project = tckts.loadProject(allocator, upper_prefix) catch |err| {
        if (err == error.ProjectNotFound) {
            eprint("Error: Project '{s}' not found. Run 'tckts init {s}' first.\n", .{ upper_prefix, upper_prefix });
            return error.ProjectNotInitialized;
        }
        return err;
    };
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
                eprint("Error: Invalid dependency ID '{s}'.\n", .{trimmed});
                return error.InvalidArgument;
            };
            try depends.append(allocator, dep_id);
        }
    }

    const ticket = try project.addTicket(ticket_type, title.?, description, depends.items, priority);
    try tckts.saveProject(allocator, &project);

    print("Created {s}-{d}: {s}\n", .{ upper_prefix, ticket.id.number, ticket.title });
}

fn cmdList(allocator: std.mem.Allocator, args: anytype) !void {
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

    var upper_prefix = try allocator.alloc(u8, prefix.len);
    defer allocator.free(upper_prefix);
    for (prefix, 0..) |c, i| {
        upper_prefix[i] = std.ascii.toUpper(c);
    }

    var project = tckts.loadProject(allocator, upper_prefix) catch |err| {
        if (err == error.ProjectNotFound) {
            return error.ProjectNotInitialized;
        }
        return err;
    };
    defer project.deinit();

    if (project.tickets.items.len == 0) {
        print("No tickets in project '{s}'.\n", .{upper_prefix});
        return;
    }

    print("\n{s} Tickets:\n", .{upper_prefix});
    print("---------------------------------------------\n", .{});

    var displayed: usize = 0;
    for (project.tickets.items) |ticket| {
        if (!show_all and ticket.status == .done) continue;

        const blocking = try project.canComplete(ticket.id.number);
        defer allocator.free(blocking);
        const is_blocked = blocking.len > 0;

        if (show_blocked and !is_blocked) continue;

        const status_char: u8 = if (ticket.status == .done) 'x' else ' ';

        print("[{c}] {s}-{d} | {s} | {s}", .{
            status_char,
            ticket.id.prefix,
            ticket.id.number,
            ticket.ticket_type.toString(),
            ticket.title,
        });

        if (is_blocked) print(" [BLOCKED]", .{});

        if (ticket.priority) |p| {
            const prio: []const u8 = switch (p) {
                .high => " !!!",
                .medium => " !!",
                .low => " !",
            };
            print("{s}", .{prio});
        }

        print("\n", .{});
        displayed += 1;
    }

    if (displayed == 0) {
        if (show_blocked) {
            print("No blocked tickets.\n", .{});
        } else {
            print("No pending tickets.\n", .{});
        }
    }

    print("\n", .{});
}

fn cmdShow(allocator: std.mem.Allocator, args: anytype) !void {
    const id_str = args.next() orelse {
        eprint("Error: Missing ticket ID.\n", .{});
        eprint("Usage: tckts show <ID>\n", .{});
        return error.MissingArgument;
    };

    var ticket_id = tckts.TicketId.parse(allocator, id_str) catch {
        eprint("Error: Invalid ticket ID '{s}'.\n", .{id_str});
        return error.InvalidArgument;
    };
    defer ticket_id.deinit(allocator);

    var project = tckts.loadProject(allocator, ticket_id.prefix) catch |err| {
        if (err == error.ProjectNotFound) {
            eprint("Error: Project '{s}' not found.\n", .{ticket_id.prefix});
            return error.ProjectNotInitialized;
        }
        return err;
    };
    defer project.deinit();

    const ticket = project.findTicket(ticket_id.number) orelse {
        eprint("Error: Ticket '{s}' not found.\n", .{id_str});
        return error.TicketNotFound;
    };

    print("\n", .{});
    print("--- {s}-{d} ---\n", .{ ticket.id.prefix, ticket.id.number });
    print("Title:    {s}\n", .{ticket.title});
    print("Type:     {s}\n", .{ticket.ticket_type.toString()});
    print("Status:   {s}\n", .{ticket.status.toString()});
    print("Created:  {s}\n", .{ticket.created});

    if (ticket.priority) |p| {
        print("Priority: {s}\n", .{p.toString()});
    }

    if (ticket.depends.len > 0) {
        print("Depends:  ", .{});
        for (ticket.depends, 0..) |dep, i| {
            if (i > 0) print(", ", .{});
            print("{s}-{d}", .{ dep.prefix, dep.number });
        }
        print("\n", .{});
    }

    if (ticket.description.len > 0) {
        print("\nDescription:\n", .{});
        var lines = mem.splitSequence(u8, ticket.description, "\n");
        while (lines.next()) |line| {
            print("  {s}\n", .{line});
        }
    }

    print("\n", .{});
}

fn cmdDone(allocator: std.mem.Allocator, args: anytype) !void {
    const id_str = args.next() orelse {
        eprint("Error: Missing ticket ID.\n", .{});
        eprint("Usage: tckts done <ID>\n", .{});
        return error.MissingArgument;
    };

    var ticket_id = tckts.TicketId.parse(allocator, id_str) catch {
        eprint("Error: Invalid ticket ID '{s}'.\n", .{id_str});
        return error.InvalidArgument;
    };
    defer ticket_id.deinit(allocator);

    var project = tckts.loadProject(allocator, ticket_id.prefix) catch |err| {
        if (err == error.ProjectNotFound) {
            eprint("Error: Project '{s}' not found.\n", .{ticket_id.prefix});
            return error.ProjectNotInitialized;
        }
        return err;
    };
    defer project.deinit();

    const blocking = try project.canComplete(ticket_id.number);
    defer allocator.free(blocking);

    if (blocking.len > 0) {
        eprint("Error: Cannot complete {s}-{d} - blocked by:\n", .{ ticket_id.prefix, ticket_id.number });
        for (blocking) |dep| {
            eprint("  - {s}-{d}\n", .{ dep.prefix, dep.number });
        }
        return error.DependencyNotComplete;
    }

    try project.markDone(ticket_id.number);
    try tckts.saveProject(allocator, &project);

    print("Completed {s}-{d}\n", .{ ticket_id.prefix, ticket_id.number });
}

fn cmdRm(allocator: std.mem.Allocator, args: anytype) !void {
    const id_str = args.next() orelse {
        eprint("Error: Missing ticket ID.\n", .{});
        eprint("Usage: tckts rm <ID>\n", .{});
        return error.MissingArgument;
    };

    var ticket_id = tckts.TicketId.parse(allocator, id_str) catch {
        eprint("Error: Invalid ticket ID '{s}'.\n", .{id_str});
        return error.InvalidArgument;
    };
    defer ticket_id.deinit(allocator);

    var project = tckts.loadProject(allocator, ticket_id.prefix) catch |err| {
        if (err == error.ProjectNotFound) {
            eprint("Error: Project '{s}' not found.\n", .{ticket_id.prefix});
            return error.ProjectNotInitialized;
        }
        return err;
    };
    defer project.deinit();

    project.removeTicket(ticket_id.number) catch |err| {
        if (err == error.TicketNotFound) {
            eprint("Error: Ticket '{s}' not found.\n", .{id_str});
            return error.TicketNotFound;
        }
        return err;
    };

    try tckts.saveProject(allocator, &project);

    print("Removed {s}-{d}\n", .{ ticket_id.prefix, ticket_id.number });
}

fn cmdProjects(allocator: std.mem.Allocator) !void {
    const projects = try tckts.listProjects(allocator);
    defer {
        for (projects) |p| allocator.free(p);
        allocator.free(projects);
    }

    if (projects.len == 0) {
        print("No projects initialized.\n", .{});
        print("Run 'tckts init <PREFIX>' to create one.\n", .{});
        return;
    }

    print("\nProjects:\n", .{});
    for (projects) |prefix| {
        var project = tckts.loadProject(allocator, prefix) catch continue;
        defer project.deinit();

        var pending: usize = 0;
        var done: usize = 0;
        for (project.tickets.items) |ticket| {
            if (ticket.status == .done) {
                done += 1;
            } else {
                pending += 1;
            }
        }

        print("  {s}: {d} pending, {d} done\n", .{ prefix, pending, done });
    }
    print("\n", .{});
}

// --- tests ---

test "Command: fromString" {
    const testing = std.testing;

    try testing.expectEqual(Command.init, Command.fromString("init").?);
    try testing.expectEqual(Command.add, Command.fromString("add").?);
    try testing.expectEqual(Command.list, Command.fromString("list").?);
    try testing.expectEqual(Command.list, Command.fromString("ls").?);
    try testing.expectEqual(Command.show, Command.fromString("show").?);
    try testing.expectEqual(Command.done, Command.fromString("done").?);
    try testing.expectEqual(Command.done, Command.fromString("complete").?);
    try testing.expectEqual(Command.rm, Command.fromString("rm").?);
    try testing.expectEqual(Command.rm, Command.fromString("delete").?);
    try testing.expectEqual(Command.projects, Command.fromString("projects").?);
    try testing.expectEqual(Command.help, Command.fromString("help").?);
    try testing.expectEqual(Command.help, Command.fromString("--help").?);
    try testing.expectEqual(@as(?Command, null), Command.fromString("unknown"));
}
