const std = @import("std");

const testing = std.testing;
const fs = std.fs;
const mem = std.mem;

// --- constants ---

const tckts_binary = "zig-out/bin/tckts";

// --- types ---

const RunResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
};

fn runTckts(allocator: std.mem.Allocator, tckts_dir: []const u8, args: []const []const u8) !RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, tckts_binary);
    for (args) |arg| {
        try argv.append(allocator, arg);
    }

    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("TCKTS_DIR", tckts_dir);

    var child = std.process.Child.init(argv.items, allocator);
    child.env_map = &env_map;
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

    return RunResult{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = exit_code,
    };
}

fn createTempDir(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.milliTimestamp();
    return std.fmt.allocPrint(allocator, "/tmp/tckts-test-{d}", .{timestamp});
}

fn cleanupTempDir(path: []const u8) void {
    fs.cwd().deleteTree(path) catch {};
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return mem.indexOf(u8, haystack, needle) != null;
}

// --- tests ---

test "e2e: Scenario 1 - new project setup" {
    const allocator = testing.allocator;

    const tckts_dir = try createTempDir(allocator);
    defer allocator.free(tckts_dir);
    defer cleanupTempDir(tckts_dir);

    // 1. Init project
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "init", "MYAPP" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "MYAPP"));
    }

    // 2. Add ticket
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "add", "-p", "MYAPP", "Setup CI pipeline", "-t", "task" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "MYAPP-1"));
    }

    // 3. List shows it
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "list", "MYAPP" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "MYAPP-1"));
        try testing.expect(contains(result.stdout, "Setup CI pipeline"));
    }

    // 4. Create config with default_project
    {
        const config_path = try std.fmt.allocPrint(allocator, "{s}/config.json", .{tckts_dir});
        defer allocator.free(config_path);

        const file = try fs.cwd().createFile(config_path, .{});
        defer file.close();
        try file.writeAll("{\"default_project\":\"MYAPP\"}\n");
    }

    // 5. Add without -p works
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "add", "Add login page" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "MYAPP-2"));
    }
}

test "e2e: Scenario 2 - daily workflow" {
    const allocator = testing.allocator;

    const tckts_dir = try createTempDir(allocator);
    defer allocator.free(tckts_dir);
    defer cleanupTempDir(tckts_dir);

    // Setup
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "init", "WORK" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // 1. Add ticket
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "add", "-p", "WORK", "Fix bug", "-t", "bug" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "WORK-1"));
    }

    // 2. List shows pending
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "list", "WORK" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "WORK-1"));
        try testing.expect(contains(result.stdout, "[ ]")); // pending checkbox
    }

    // 3. Start it
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "start", "WORK-1" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "Started"));
    }

    // 4. Done it
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "done", "WORK-1" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "Completed"));
    }

    // 5. List hides completed by default
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "list", "WORK" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(!contains(result.stdout, "WORK-1"));
    }

    // 6. List --all shows it with [x]
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "list", "WORK", "--all" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "WORK-1"));
        try testing.expect(contains(result.stdout, "[x]")); // done checkbox
    }
}

test "e2e: Scenario 3 - dependencies and blocking" {
    const allocator = testing.allocator;

    const tckts_dir = try createTempDir(allocator);
    defer allocator.free(tckts_dir);
    defer cleanupTempDir(tckts_dir);

    // Setup
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "init", "DEP" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // 1. Add ticket A
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "add", "-p", "DEP", "Design API schema", "-t", "task" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "DEP-1"));
    }

    // 2. Add ticket B depending on A
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "add", "-p", "DEP", "Implement API", "-t", "feature", "-d", "DEP-1" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "DEP-2"));
    }

    // 3. List shows B as blocked
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "list", "DEP" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "[BLOCKED]"));
    }

    // 4. Done B fails (dependency incomplete)
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "done", "DEP-2" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expect(result.exit_code != 0);
    }

    // 5. Done A succeeds
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "done", "DEP-1" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // 6. Done B now succeeds
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "done", "DEP-2" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }
}

test "e2e: Scenario 4 - ticket removal cleans dependencies" {
    const allocator = testing.allocator;

    const tckts_dir = try createTempDir(allocator);
    defer allocator.free(tckts_dir);
    defer cleanupTempDir(tckts_dir);

    // Setup
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "init", "RM" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // 1. Add ticket A
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "add", "-p", "RM", "Feature A", "-t", "feature" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "RM-1"));
    }

    // 2. Add ticket B depending on A
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "add", "-p", "RM", "Subtask", "-t", "task", "-d", "RM-1" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "RM-2"));
    }

    // 3. Verify B is blocked
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "list", "RM" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "[BLOCKED]"));
    }

    // 4. Remove A
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "rm", "RM-1" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "Removed"));
    }

    // 5. B is no longer blocked
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "list", "RM" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(!contains(result.stdout, "[BLOCKED]"));
        try testing.expect(contains(result.stdout, "RM-2"));
    }

    // 6. Show B has no deps listed
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "show", "RM-2" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(!contains(result.stdout, "RM-1"));
    }
}

test "e2e: Scenario 5 - update command" {
    const allocator = testing.allocator;

    const tckts_dir = try createTempDir(allocator);
    defer allocator.free(tckts_dir);
    defer cleanupTempDir(tckts_dir);

    // Setup
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "init", "UPD" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // 1. Add ticket
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "add", "-p", "UPD", "Original title", "-t", "task" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "UPD-1"));
    }

    // 2. Update title
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "update", "UPD-1", "--title", "Updated title" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "Updated UPD-1"));
    }

    // 3. Show verifies title change
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "show", "UPD-1" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "Updated title"));
    }

    // 4. Update status to in_progress
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "update", "UPD-1", "--status", "in_progress" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "Updated UPD-1 status to in_progress"));
    }

    // 5. Update status to done
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "update", "UPD-1", "--status", "done" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "Updated UPD-1 status to done"));
    }

    // 6. Verify done in list --all
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "list", "UPD", "--all" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "[x]")); // done checkbox
    }

    // 7. Test alias 'edit' works
    {
        // Add another ticket
        const add_result = try runTckts(allocator, tckts_dir, &.{ "add", "-p", "UPD", "Second ticket", "-t", "bug" });
        defer allocator.free(add_result.stdout);
        defer allocator.free(add_result.stderr);
        try testing.expectEqual(@as(u8, 0), add_result.exit_code);

        const result = try runTckts(allocator, tckts_dir, &.{ "edit", "UPD-2", "--status", "in_progress" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(contains(result.stdout, "Updated UPD-2 status to in_progress"));
    }

    // 8. Test error: missing ticket ID
    {
        const result = try runTckts(allocator, tckts_dir, &.{"update"});
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expect(result.exit_code != 0);
    }

    // 9. Test error: no options provided
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "update", "UPD-1" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expect(result.exit_code != 0);
        try testing.expect(contains(result.stderr, "At least one"));
    }

    // 10. Test error: invalid status
    {
        const result = try runTckts(allocator, tckts_dir, &.{ "update", "UPD-2", "--status", "invalid" });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        try testing.expect(result.exit_code != 0);
        try testing.expect(contains(result.stderr, "Invalid status"));
    }
}
