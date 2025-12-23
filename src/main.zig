const std = @import("std");
const tckts = @import("tckts");
const cli = @import("cli/mod.zig");
const commands = @import("cli/commands/mod.zig");

const process = std.process;

// --- constants ---

const version = "0.1.0";

// --- main ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    run(allocator) catch |err| {
        switch (err) {
            error.MissingCommand => process.exit(1),
            error.UnknownCommand => {
                cli.eprint("Error: Unknown command. Run 'tckts help' for usage.\n", .{});
                process.exit(1);
            },
            error.MissingArgument => {
                cli.eprint("Error: Missing required argument.\n", .{});
                process.exit(1);
            },
            error.InvalidArgument => {
                cli.eprint("Error: Invalid argument.\n", .{});
                process.exit(1);
            },
            error.ProjectNotInitialized, error.ProjectNotFound => {
                process.exit(1);
            },
            error.TicketNotFound => {
                cli.eprint("Error: Ticket not found.\n", .{});
                process.exit(1);
            },
            error.DependencyNotComplete => {
                cli.eprint("Error: Cannot complete ticket - dependencies not done.\n", .{});
                process.exit(1);
            },
            error.ProjectAlreadyExists => {
                cli.eprint("Error: Project already exists.\n", .{});
                process.exit(1);
            },
            error.AlreadyDone => {
                cli.eprint("Error: Ticket is already done.\n", .{});
                process.exit(1);
            },
            error.TitleTooLong => {
                cli.eprint("Error: Title too long (max {d} characters).\n", .{tckts.max_title_length_bytes});
                process.exit(1);
            },
            error.DescriptionTooLong => {
                cli.eprint("Error: Description too long (max {d} bytes).\n", .{tckts.max_description_length_bytes});
                process.exit(1);
            },
            error.TooManyTickets => {
                cli.eprint("Error: Too many tickets in project (max {d}).\n", .{tckts.max_tickets_per_project});
                process.exit(1);
            },
            error.PrefixTooLong => {
                cli.eprint("Error: Prefix too long (max {d} characters).\n", .{tckts.max_prefix_length_bytes});
                process.exit(1);
            },
            else => {
                cli.eprint("Error: {any}\n", .{err});
                process.exit(2);
            },
        }
    };
}

fn run(allocator: std.mem.Allocator) !void {
    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip program name

    const cmd_str = args.next() orelse {
        printUsage();
        return error.MissingCommand;
    };

    const cmd = cli.Command.fromString(cmd_str) orelse {
        cli.eprint("Unknown command: {s}\n", .{cmd_str});
        return error.UnknownCommand;
    };

    switch (cmd) {
        .init => try commands.init.run(allocator, &args),
        .add => try commands.add.run(allocator, &args),
        .list => try commands.list.run(allocator, &args),
        .show => try commands.show.run(allocator, &args),
        .start => try commands.start.run(allocator, &args),
        .done => try commands.done.run(allocator, &args),
        .rm => try commands.rm.run(allocator, &args),
        .projects => try commands.projects.run(allocator),
        .help => printHelp(),
    }
}

fn printUsage() void {
    cli.print(
        \\tckts - CLI ticket tracker v{s}
        \\
        \\Usage: tckts <command> [options]
        \\
        \\Commands:
        \\  init <PREFIX>     Initialize a new project
        \\  add <title>       Add a new ticket
        \\  list [PREFIX]     List tickets
        \\  show <ID>         Show ticket details
        \\  start <ID>        Mark ticket as in-progress
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
    cli.print(
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
        \\          -t, --type <TYPE>        Ticket type: bug, feature, task, chore, epic
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
        \\    start <ID>
        \\        Mark a ticket as in-progress.
        \\        Records the started_at timestamp.
        \\        Example: tckts start BACKEND-1
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
        \\    tckts start BACKEND-1
        \\    tckts done BACKEND-1
        \\
    , .{version});
}
