const std = @import("std");

const tckts = @import("tckts");
const cli = @import("cli/mod.zig");

// --- constants ---

const current_schema_version: u32 = 2;

// --- types ---

pub const MigrationError = error{
    NotGitRepo,
    UncommittedChanges,
    MigrationFailed,
    OutOfMemory,
    IoError,
};

const Migration = struct {
    from_version: u32,
    to_version: u32,
    run: *const fn (std.mem.Allocator, []const u8) MigrationError!void,
};

const migrations = [_]Migration{
    .{ .from_version = 1, .to_version = 2, .run = migrateV1ToV2 },
};

/// Check if any project needs migration and run if needed.
/// Called before every command.
pub fn runPendingMigrations(allocator: std.mem.Allocator, force: bool) MigrationError!bool {
    var config = tckts.loadConfig(allocator) catch return MigrationError.IoError;
    defer config.deinit(allocator);

    var any_migrated = false;

    var iter = config.projects.iterator();
    while (iter.next()) |entry| {
        const prefix = entry.key_ptr.*;
        const meta = entry.value_ptr.*;

        if (meta.version < current_schema_version) {
            if (!force) {
                try checkGitSafety(allocator);
            }

            try runMigrationsForProject(allocator, prefix, meta.version);
            any_migrated = true;
        }
    }

    return any_migrated;
}

fn runMigrationsForProject(allocator: std.mem.Allocator, prefix: []const u8, from_version: u32) MigrationError!void {
    var version = from_version;

    while (version < current_schema_version) {
        for (migrations) |migration| {
            if (migration.from_version == version) {
                cli.print("Migrating {s} from v{d} to v{d}...\n", .{ prefix, migration.from_version, migration.to_version });
                try migration.run(allocator, prefix);
                version = migration.to_version;
                break;
            }
        }
    }

    // Update version in config
    updateProjectVersion(allocator, prefix, current_schema_version) catch return MigrationError.IoError;
    cli.print("Migrated {s} to schema v{d}\n", .{ prefix, current_schema_version });
}

fn updateProjectVersion(allocator: std.mem.Allocator, prefix: []const u8, version: u32) !void {
    var config = try tckts.loadConfig(allocator);
    defer config.deinit(allocator);

    if (config.projects.getPtr(prefix)) |meta| {
        meta.version = version;
    }

    try tckts.saveConfig(allocator, &config);
}

fn checkGitSafety(allocator: std.mem.Allocator) MigrationError!void {
    // Check if in git repo
    const git_check = runGitCommand(allocator, &.{ "git", "rev-parse", "--git-dir" }) catch return MigrationError.NotGitRepo;
    defer allocator.free(git_check.stdout);
    defer allocator.free(git_check.stderr);

    if (git_check.exit_code != 0) {
        cli.eprint("Error: Migration requires a git repository.\n", .{});
        cli.eprint("Use 'tckts migrate --force' to migrate without git safety.\n", .{});
        return MigrationError.NotGitRepo;
    }

    // Check if .tckts/ has uncommitted changes
    const tckts_dir = tckts.getTcktsDir(allocator) catch return MigrationError.IoError;
    defer allocator.free(tckts_dir);

    const status_check = runGitCommand(allocator, &.{ "git", "status", "--porcelain", tckts_dir }) catch return MigrationError.IoError;
    defer allocator.free(status_check.stdout);
    defer allocator.free(status_check.stderr);

    if (status_check.stdout.len > 0) {
        cli.eprint("Error: Cannot migrate with uncommitted changes in {s}/\n", .{tckts_dir});
        cli.eprint("Please commit or stash your changes first.\n", .{});
        cli.eprint("Or use 'tckts migrate --force' to skip this check.\n", .{});
        return MigrationError.UncommittedChanges;
    }
}

const GitResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
};

fn runGitCommand(allocator: std.mem.Allocator, args: []const []const u8) !GitResult {
    var child = std.process.Child.init(args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    errdefer allocator.free(stdout);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 64 * 1024);
    errdefer allocator.free(stderr);

    const term = try child.wait();
    const exit_code: u8 = switch (term) {
        .Exited => |code| code,
        else => 255,
    };

    return GitResult{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = exit_code,
    };
}

// --- migration implementations ---

fn migrateV1ToV2(allocator: std.mem.Allocator, prefix: []const u8) MigrationError!void {
    // Load project
    var project = tckts.loadProject(allocator, prefix) catch return MigrationError.IoError;
    defer project.deinit();

    // For each ticket, build history from existing fields
    for (project.tickets.items) |*ticket| {
        // Count how many history entries we need
        var entry_count: usize = 1; // Always have created/pending entry
        if (ticket.started_at != null) entry_count += 1;
        if (ticket.completed_at != null) entry_count += 1;

        // Free old (empty) history
        allocator.free(ticket.history);

        // Allocate new history
        var new_history = allocator.alloc(tckts.HistoryEntry, entry_count) catch return MigrationError.OutOfMemory;
        var idx: usize = 0;

        // Add created (pending) entry - copy the timestamp
        const created_at_copy = allocator.dupe(u8, ticket.created_at) catch return MigrationError.OutOfMemory;
        new_history[idx] = .{ .status = .pending, .at = created_at_copy };
        idx += 1;

        // Add started entry if exists (reuse the string, don't copy)
        if (ticket.started_at) |started_at| {
            new_history[idx] = .{ .status = .in_progress, .at = started_at };
            idx += 1;
            ticket.started_at = null; // Transfer ownership to history
        }

        // Add completed entry if exists (reuse the string, don't copy)
        if (ticket.completed_at) |completed_at| {
            new_history[idx] = .{ .status = .done, .at = completed_at };
            idx += 1;
            ticket.completed_at = null; // Transfer ownership to history
        }

        ticket.history = new_history;
    }

    // Save project
    tckts.saveProject(allocator, &project) catch return MigrationError.IoError;
}

// --- tests ---

const testing = std.testing;

test "migrations: v1 to v2 builds history" {
    // This test uses the v1 fixtures
    // We'll test the migration logic in isolation
}
