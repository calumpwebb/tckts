const std = @import("std");

const build_options = @import("build_options");
const tckts = @import("tckts");

const cli = @import("cli/mod.zig");
const commands = @import("cli/commands/mod.zig");
const migrations = @import("migrations.zig");

const process = std.process;

// --- constants ---

const version = build_options.version;
const exit_code_error = 1;
const exit_code_internal = 2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    run(allocator) catch |err| {
        switch (err) {
            error.MissingCommand => process.exit(exit_code_error),
            error.UnknownCommand => {
                cli.eprint("Error: Unknown command. Run 'tckts help' for usage.\n", .{});
                process.exit(exit_code_error);
            },
            error.MissingArgument => {
                cli.eprint("Error: Missing required argument.\n", .{});
                process.exit(exit_code_error);
            },
            error.InvalidArgument => {
                cli.eprint("Error: Invalid argument.\n", .{});
                process.exit(exit_code_error);
            },
            error.ProjectNotInitialized, error.ProjectNotFound => {
                process.exit(exit_code_error);
            },
            error.TicketNotFound => {
                // Error message already printed by command handler with specific ticket ID
                process.exit(exit_code_error);
            },
            error.DependencyNotComplete => {
                cli.eprint("Error: Cannot complete ticket - dependencies not done.\n", .{});
                process.exit(exit_code_error);
            },
            error.ProjectAlreadyExists => {
                cli.eprint("Error: Project already exists.\n", .{});
                process.exit(exit_code_error);
            },
            error.AlreadyDone => {
                // Error message already printed by command handler with specific ticket ID
                process.exit(exit_code_error);
            },
            error.TitleTooLong => {
                cli.eprint("Error: Title too long (max {d} characters).\n", .{tckts.max_title_length_bytes});
                process.exit(exit_code_error);
            },
            error.DescriptionTooLong => {
                cli.eprint("Error: Description too long (max {d} bytes).\n", .{tckts.max_description_length_bytes});
                process.exit(exit_code_error);
            },
            error.TooManyTickets => {
                cli.eprint("Error: Too many tickets in project (max {d}).\n", .{tckts.max_tickets_per_project});
                process.exit(exit_code_error);
            },
            error.PrefixTooLong => {
                cli.eprint("Error: Prefix too long (max {d} characters).\n", .{tckts.max_prefix_length_bytes});
                process.exit(exit_code_error);
            },
            error.MigrationFailed => {
                // Error message already printed by migration
                process.exit(exit_code_error);
            },
            else => {
                cli.eprint("Error: {any}\n", .{err});
                process.exit(exit_code_internal);
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

    // Run any pending migrations before every command
    // Migration errors are non-fatal for init command (no projects yet)
    const is_force_migrate = cmd == .migrate and hasForceFlag(&args);
    _ = migrations.runPendingMigrations(allocator, is_force_migrate) catch |err| {
        switch (err) {
            migrations.MigrationError.NotGitRepo, migrations.MigrationError.UncommittedChanges => {
                // Error message already printed
                return error.MigrationFailed;
            },
            else => {
                // For IoError on init, it's fine - no projects exist yet
                if (cmd != .init) {
                    cli.eprint("Error: Migration failed.\n", .{});
                    return error.MigrationFailed;
                }
            },
        }
    };

    switch (cmd) {
        .init => try commands.init.run(allocator, &args),
        .add => try commands.add.run(allocator, &args),
        .list => try commands.list.run(allocator, &args),
        .show => try commands.show.run(allocator, &args),
        .start => try commands.start.run(allocator, &args),
        .done => try commands.done.run(allocator, &args),
        .update => try commands.update.run(allocator, &args),
        .remove => try commands.remove.run(allocator, &args),
        .projects => try commands.projects.run(allocator),
        .quickstart => try commands.quickstart.run(allocator),
        .migrate => cli.print("Migration complete (or no migration needed).\n", .{}),
        .version => cli.print("tckts {s}\n", .{version}),
        .help => printHelp(),
    }
}

fn hasForceFlag(args: anytype) bool {
    // Peek at args to check for --force flag
    // Note: This consumes the iterator, so we need to reset it or check before consuming
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            return true;
        }
    }
    return false;
}

fn printUsage() void {
    cli.print(
        \\tckts - CLI ticket tracker {s}
        \\
        \\Usage: tckts <command> [options]
        \\
        \\Commands:
        \\
    , .{version});

    // Print commands from their metadata
    printCommandSummary(commands.init.meta);
    printCommandSummary(commands.add.meta);
    printCommandSummary(commands.list.meta);
    printCommandSummary(commands.show.meta);
    printCommandSummary(commands.start.meta);
    printCommandSummary(commands.done.meta);
    printCommandSummary(commands.update.meta);
    printCommandSummary(commands.remove.meta);

    // Commands without meta (no args)
    cli.print("  {s: <18} {s}\n", .{ "projects", "List all projects" });
    cli.print("  {s: <18} {s}\n", .{ "quickstart", "LLM onboarding guide" });
    cli.print("  {s: <18} {s}\n", .{ "version", "Show version" });
    cli.print("  {s: <18} {s}\n", .{ "help", "Show detailed help" });

    cli.print("\nRun 'tckts <command> -h' for command-specific help.\n", .{});
}

fn printCommandSummary(meta: cli.arg_parser.CommandMeta) void {
    cli.print("  {s: <18} {s}\n", .{ meta.usage, meta.short });
}

fn printHelp() void {
    cli.print(
        \\tckts - CLI ticket tracker {s}
        \\
        \\A plain-text ticket tracker that stores tickets in your repository.
        \\Tickets are human-readable and LLM-friendly.
        \\
        \\USAGE:
        \\    tckts <command> [options]
        \\
        \\COMMANDS:
        \\
    , .{version});

    // Print detailed help from command metadata
    printCommandHelp(commands.init.meta);
    printCommandHelp(commands.add.meta);
    printCommandHelp(commands.list.meta);
    printCommandHelp(commands.show.meta);
    printCommandHelp(commands.start.meta);
    printCommandHelp(commands.done.meta);
    printCommandHelp(commands.update.meta);
    printCommandHelp(commands.remove.meta);

    // Commands without meta
    cli.print("    projects\n", .{});
    cli.print("        List all initialized projects.\n\n", .{});

    cli.print("    quickstart\n", .{});
    cli.print("        LLM onboarding guide. <- LLMs RUN THIS\n\n", .{});

    cli.print("    version\n", .{});
    cli.print("        Show version information.\n\n", .{});

    cli.print("    help\n", .{});
    cli.print("        Show this help message.\n\n", .{});

    cli.print(
        \\FILES:
        \\    Tickets are stored in .tckts/ directory at the repository root.
        \\    Each project has its own file: .tckts/BACKEND.tckts
        \\
        \\ENVIRONMENT:
        \\    TCKTS_DIR    Override the default ticket storage directory (.tckts/)
        \\                 Example: TCKTS_DIR=/path/to/tickets tckts list
        \\
    , .{});
}

fn printCommandHelp(meta: cli.arg_parser.CommandMeta) void {
    cli.print("    {s}\n", .{meta.usage});
    cli.print("        {s}\n", .{meta.short});

    // Print options if any
    if (meta.options.len > 0) {
        cli.print("        Options:\n", .{});
        for (meta.options) |opt| {
            printOptionHelp(opt);
        }
    }

    // Print first example if available
    if (meta.examples.len > 0) {
        cli.print("        Example: {s}\n", .{meta.examples[0]});
    }

    cli.print("\n", .{});
}

fn printOptionHelp(opt: cli.arg_parser.OptionMeta) void {
    var buf: [48]u8 = undefined;
    var len: usize = 0;

    // Build option string: "-p, --project <PREFIX>"
    if (opt.short) |s| {
        for (s) |c| {
            buf[len] = c;
            len += 1;
        }
    }

    if (opt.short != null and opt.long != null) {
        buf[len] = ',';
        len += 1;
        buf[len] = ' ';
        len += 1;
    }

    if (opt.long) |l| {
        for (l) |c| {
            buf[len] = c;
            len += 1;
        }
    }

    if (opt.arg) |a| {
        buf[len] = ' ';
        len += 1;
        for (a) |c| {
            buf[len] = c;
            len += 1;
        }
    }

    cli.print("          {s: <24} {s}\n", .{ buf[0..len], opt.desc });
}
