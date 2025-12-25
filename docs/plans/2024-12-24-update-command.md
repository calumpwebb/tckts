# Update Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an `update` command that allows editing ticket title, description, and status, replacing the existing `done` and `start` commands as aliases.

**Architecture:** The `update` command takes a ticket ID and optional flags (`--title`, `--description`, `--status`). The `done` and `start` commands become aliases that call update with pre-set status values. Only status changes are recorded in history; title/description changes are not tracked.

**Tech Stack:** Zig, existing ArgParser/CommandMeta infrastructure

---

## Task 1: Add Ticket Update Methods to Core Library

**Files:**
- Modify: `src/root.zig` (add methods to Ticket and Project)

**Step 1: Write the failing test for setTitle**

Add to `src/root.zig` in the test section:

```zig
test "Ticket: setTitle updates title" {
    const allocator = std.testing.allocator;
    var ticket = Ticket{
        .id = TicketId{ .prefix = "TEST", .number = 1 },
        .ticket_type = .task,
        .status = .pending,
        .title = "Original title",
        .created_at = "2024-01-01T00:00:00Z",
        .started_at = null,
        .completed_at = null,
        .depends = &[_]TicketId{},
        .priority = null,
        .description = "",
        .history = &[_]HistoryEntry{},
    };

    try ticket.setTitle(allocator, "New title");
    defer allocator.free(ticket.title);

    try std.testing.expectEqualStrings("New title", ticket.title);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: Compilation error - `setTitle` doesn't exist

**Step 3: Implement setTitle on Ticket**

Add method to `Ticket` struct (after line ~422, after `appendHistory`):

```zig
pub fn setTitle(self: *Ticket, allocator: std.mem.Allocator, new_title: []const u8) !void {
    if (new_title.len > 280) return error.TitleTooLong;
    if (new_title.len == 0) return error.TitleEmpty;
    const duped = try allocator.dupe(u8, new_title);
    self.title = duped;
}
```

**Step 4: Run test to verify it passes**

Run: `zig build test 2>&1 | grep -E "(PASS|FAIL|error)"`
Expected: Test passes

**Step 5: Commit**

```bash
git add src/root.zig
git commit -m "feat: TCKTS-XX add Ticket.setTitle method"
```

---

## Task 2: Add setDescription Method

**Files:**
- Modify: `src/root.zig`

**Step 1: Write the failing test**

```zig
test "Ticket: setDescription updates description" {
    const allocator = std.testing.allocator;
    var ticket = Ticket{
        .id = TicketId{ .prefix = "TEST", .number = 1 },
        .ticket_type = .task,
        .status = .pending,
        .title = "Test",
        .created_at = "2024-01-01T00:00:00Z",
        .started_at = null,
        .completed_at = null,
        .depends = &[_]TicketId{},
        .priority = null,
        .description = "",
        .history = &[_]HistoryEntry{},
    };

    try ticket.setDescription(allocator, "New description text");
    defer allocator.free(ticket.description);

    try std.testing.expectEqualStrings("New description text", ticket.description);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: Compilation error - `setDescription` doesn't exist

**Step 3: Implement setDescription on Ticket**

```zig
pub fn setDescription(self: *Ticket, allocator: std.mem.Allocator, new_description: []const u8) !void {
    const max_description: usize = 64 * 1024; // 64KB
    if (new_description.len > max_description) return error.DescriptionTooLong;
    const duped = try allocator.dupe(u8, new_description);
    self.description = duped;
}
```

**Step 4: Run test to verify it passes**

Run: `zig build test 2>&1 | grep -E "(PASS|FAIL|error)"`
Expected: Test passes

**Step 5: Commit**

```bash
git add src/root.zig
git commit -m "feat: TCKTS-XX add Ticket.setDescription method"
```

---

## Task 3: Add setStatus Method (with History)

**Files:**
- Modify: `src/root.zig`

**Step 1: Write the failing test**

```zig
test "Ticket: setStatus updates status and appends history" {
    const allocator = std.testing.allocator;
    var ticket = Ticket{
        .id = TicketId{ .prefix = "TEST", .number = 1 },
        .ticket_type = .task,
        .status = .pending,
        .title = "Test",
        .created_at = "2024-01-01T00:00:00Z",
        .started_at = null,
        .completed_at = null,
        .depends = &[_]TicketId{},
        .priority = null,
        .description = "",
        .history = &[_]HistoryEntry{},
    };
    defer allocator.free(ticket.history);

    try ticket.setStatus(allocator, .in_progress);

    try std.testing.expectEqual(Status.in_progress, ticket.status);
    try std.testing.expectEqual(@as(usize, 1), ticket.history.len);
    try std.testing.expectEqual(Status.in_progress, ticket.history[0].status);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: Compilation error - `setStatus` doesn't exist

**Step 3: Implement setStatus on Ticket**

```zig
pub fn setStatus(self: *Ticket, allocator: std.mem.Allocator, new_status: Status) !void {
    self.status = new_status;
    try self.appendHistory(allocator, new_status);
}
```

**Step 4: Run test to verify it passes**

Run: `zig build test 2>&1 | grep -E "(PASS|FAIL|error)"`
Expected: Test passes

**Step 5: Commit**

```bash
git add src/root.zig
git commit -m "feat: TCKTS-XX add Ticket.setStatus method with history"
```

---

## Task 4: Add Project.updateTicket Method

**Files:**
- Modify: `src/root.zig`

**Step 1: Write the failing test**

```zig
test "Project: updateTicket modifies existing ticket" {
    const allocator = std.testing.allocator;

    var project = Project.init(allocator, "TEST", 2);
    defer project.deinit();

    _ = try project.addTicket(.{
        .title = "Original",
        .ticket_type = .task,
    });

    try project.updateTicket(1, .{
        .title = "Updated title",
        .status = .in_progress,
    });

    const ticket = project.getTicket(1).?;
    try std.testing.expectEqualStrings("Updated title", ticket.title);
    try std.testing.expectEqual(Status.in_progress, ticket.status);
    try std.testing.expectEqual(@as(usize, 1), ticket.history.len);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: Compilation error

**Step 3: Define UpdateOptions struct and implement updateTicket**

Add struct near other option structs (around line 300):

```zig
pub const UpdateOptions = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    status: ?Status = null,
};
```

Add method to Project (after `markDone`, around line 400):

```zig
pub fn updateTicket(self: *Project, ticket_number: u32, options: UpdateOptions) !void {
    const ticket = self.getTicketMut(ticket_number) orelse return error.TicketNotFound;

    if (options.title) |new_title| {
        try ticket.setTitle(self.allocator, new_title);
    }
    if (options.description) |new_desc| {
        try ticket.setDescription(self.allocator, new_desc);
    }
    if (options.status) |new_status| {
        try ticket.setStatus(self.allocator, new_status);
    }
}
```

**Step 4: Run test to verify it passes**

Run: `zig build test 2>&1 | grep -E "(PASS|FAIL|error)"`
Expected: Test passes

**Step 5: Commit**

```bash
git add src/root.zig
git commit -m "feat: TCKTS-XX add Project.updateTicket method"
```

---

## Task 5: Create the Update Command Handler

**Files:**
- Create: `src/cli/commands/update.zig`

**Step 1: Create the command file with CommandMeta**

```zig
const std = @import("std");
const cli = @import("../mod.zig");
const root = @import("../../root.zig");
const ArgParser = @import("../args.zig").ArgParser;
const CommandMeta = @import("../args.zig").CommandMeta;

pub const meta = CommandMeta{
    .name = "update",
    .usage = "<ticket-id> [options]",
    .short = "Update a ticket's title, description, or status",
    .options = &[_]CommandMeta.Option{
        .{ .name = "--title", .short = "-t", .description = "Set new title", .takes_value = true },
        .{ .name = "--description", .short = "-d", .description = "Set new description", .takes_value = true },
        .{ .name = "--status", .short = "-s", .description = "Set status (pending, in_progress, blocked, done)", .takes_value = true },
    },
    .examples = &[_][]const u8{
        "update TODO-1 --status done",
        "update TODO-1 --title \"New title\"",
        "update TODO-1 -s in_progress -t \"Updated\"",
    },
};

pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var parser = ArgParser(@TypeOf(args.*)).init(args, meta);
    parser.parse() catch |err| {
        try parser.printError(err);
        return;
    };

    if (parser.helpRequested()) {
        try parser.printHelp(false);
        return;
    }

    const ticket_id_str = parser.positional(0) orelse {
        try cli.eprint("Error: missing ticket ID\n");
        try cli.eprint("Usage: tckts update <ticket-id> [options]\n");
        return;
    };

    const ticket_id = root.TicketId.parse(ticket_id_str) catch {
        try cli.eprint("Error: invalid ticket ID format '{s}'\n", .{ticket_id_str});
        return;
    };

    // Parse options
    const new_title = parser.option("title");
    const new_description = parser.option("description");
    const status_str = parser.option("status");

    // At least one option required
    if (new_title == null and new_description == null and status_str == null) {
        try cli.eprint("Error: at least one of --title, --description, or --status required\n");
        return;
    }

    // Parse status if provided
    var new_status: ?root.Status = null;
    if (status_str) |s| {
        new_status = std.meta.stringToEnum(root.Status, s) orelse {
            try cli.eprint("Error: invalid status '{s}'. Valid: pending, in_progress, blocked, done\n", .{s});
            return;
        };
    }

    // Load project
    var project = root.Project.load(allocator, ticket_id.prefix) catch |err| {
        if (err == error.FileNotFound) {
            try cli.eprint("Error: project '{s}' not found\n", .{ticket_id.prefix});
            return;
        }
        return err;
    };
    defer project.deinit();

    // Check ticket exists
    if (project.getTicket(ticket_id.number) == null) {
        try cli.eprint("Error: ticket {s} not found\n", .{ticket_id_str});
        return;
    }

    // Check dependencies if marking done
    if (new_status == .done) {
        if (!project.canComplete(ticket_id.number)) {
            try cli.eprint("Error: cannot mark {s} as done - has incomplete dependencies\n", .{ticket_id_str});
            return;
        }
    }

    // Perform update
    try project.updateTicket(ticket_id.number, .{
        .title = new_title,
        .description = new_description,
        .status = new_status,
    });

    try project.save();

    // Print confirmation
    if (new_status) |status| {
        const status_name = @tagName(status);
        try cli.print("{s} status changed to {s}\n", .{ ticket_id_str, status_name });
    } else if (new_title != null or new_description != null) {
        try cli.print("{s} updated\n", .{ticket_id_str});
    }
}
```

**Step 2: Run build to check for compilation errors**

Run: `zig build 2>&1 | head -20`
Expected: May fail because update.zig not registered yet

**Step 3: Commit**

```bash
git add src/cli/commands/update.zig
git commit -m "feat: TCKTS-XX add update command handler"
```

---

## Task 6: Register Update Command in Module

**Files:**
- Modify: `src/cli/commands/mod.zig`

**Step 1: Add the import**

Find the imports section and add:

```zig
pub const update = @import("update.zig");
```

**Step 2: Run build to verify**

Run: `zig build 2>&1`
Expected: Should compile (command not yet wired to dispatch)

**Step 3: Commit**

```bash
git add src/cli/commands/mod.zig
git commit -m "feat: TCKTS-XX register update command module"
```

---

## Task 7: Add Update to Command Enum and Aliases

**Files:**
- Modify: `src/cli/mod.zig`

**Step 1: Add `update` to Command enum**

Find the `Command` enum and add `update`:

```zig
pub const Command = enum {
    init,
    add,
    list,
    show,
    start,
    done,
    update,  // Add this
    remove,
    projects,
    quickstart,
    migrate,
    version,
    help,
};
```

**Step 2: Add aliases in fromString()**

Find the `fromString` function and add to the mapping tuple:

```zig
.{ "update", Command.update },
.{ "set", Command.update },      // alias
.{ "edit", Command.update },     // alias
```

**Step 3: Run build to verify**

Run: `zig build 2>&1`
Expected: Should compile

**Step 4: Commit**

```bash
git add src/cli/mod.zig
git commit -m "feat: TCKTS-XX add update command to enum with aliases"
```

---

## Task 8: Wire Up Command Dispatch in main.zig

**Files:**
- Modify: `src/main.zig`

**Step 1: Add dispatch case**

Find the switch statement in `run()` and add:

```zig
.update => try commands.update.run(allocator, &args),
```

**Step 2: Add to help output**

Find `printAllHelp` and add:

```zig
printCommandSummary(commands.update.meta);
```

Find `printAllCommandsHelp` and add:

```zig
printCommandHelp(commands.update.meta);
```

**Step 3: Run and test manually**

Run: `zig build run -- update --help`
Expected: Shows update command help

Run: `zig build run -- help`
Expected: Shows update in command list

**Step 4: Commit**

```bash
git add src/main.zig
git commit -m "feat: TCKTS-XX wire update command dispatch and help"
```

---

## Task 9: Add E2E Tests for Update Command

**Files:**
- Create: `e2e/update_test.zig` (or add to existing e2e test file)

**Step 1: Check existing E2E test structure**

Run: `ls e2e/`
Look at how other commands are tested

**Step 2: Add update tests following existing pattern**

Tests should cover:
- Update title only
- Update description only
- Update status only
- Update multiple fields
- Error: missing ticket ID
- Error: ticket not found
- Error: invalid status
- Error: no options provided

**Step 3: Run E2E tests**

Run: `zig build && zig build e2e`
Expected: All tests pass

**Step 4: Commit**

```bash
git add e2e/
git commit -m "test: TCKTS-XX add e2e tests for update command"
```

---

## Task 10: Make `done` and `start` Aliases for Update

**Files:**
- Modify: `src/cli/commands/done.zig`
- Modify: `src/cli/commands/start.zig`

**Step 1: Simplify done.zig to delegate to update**

Replace the run function body to call update with `--status done`:

```zig
pub fn run(allocator: std.mem.Allocator, args: anytype) !void {
    var parser = ArgParser(@TypeOf(args.*)).init(args, meta);
    parser.parse() catch |err| {
        try parser.printError(err);
        return;
    };

    if (parser.helpRequested()) {
        try parser.printHelp(false);
        return;
    }

    const ticket_id_str = parser.positional(0) orelse {
        try cli.eprint("Error: missing ticket ID\n");
        try cli.eprint("Usage: tckts done <ticket-id>\n");
        return;
    };

    // Delegate to update command logic
    const ticket_id = root.TicketId.parse(ticket_id_str) catch {
        try cli.eprint("Error: invalid ticket ID format '{s}'\n", .{ticket_id_str});
        return;
    };

    var project = root.Project.load(allocator, ticket_id.prefix) catch |err| {
        if (err == error.FileNotFound) {
            try cli.eprint("Error: project '{s}' not found\n", .{ticket_id.prefix});
            return;
        }
        return err;
    };
    defer project.deinit();

    if (project.getTicket(ticket_id.number) == null) {
        try cli.eprint("Error: ticket {s} not found\n", .{ticket_id_str});
        return;
    }

    if (!project.canComplete(ticket_id.number)) {
        try cli.eprint("Error: cannot mark {s} as done - has incomplete dependencies\n", .{ticket_id_str});
        return;
    }

    try project.updateTicket(ticket_id.number, .{ .status = .done });
    try project.save();
    try cli.print("{s} marked as done\n", .{ticket_id_str});
}
```

**Step 2: Similarly update start.zig**

Replace to use `project.updateTicket` with `.status = .in_progress`.

**Step 3: Run all tests**

Run: `zig build test && zig build && zig build e2e`
Expected: All tests pass

**Step 4: Commit**

```bash
git add src/cli/commands/done.zig src/cli/commands/start.zig
git commit -m "refactor: TCKTS-XX done/start commands use updateTicket internally"
```

---

## Task 11: Update Unit Tests for Command Enum

**Files:**
- Modify: `src/cli/mod.zig`

**Step 1: Add test for update command parsing**

Find the command tests and add:

```zig
test "Command.fromString: update and aliases" {
    try std.testing.expectEqual(Command.update, Command.fromString("update"));
    try std.testing.expectEqual(Command.update, Command.fromString("set"));
    try std.testing.expectEqual(Command.update, Command.fromString("edit"));
}
```

**Step 2: Run tests**

Run: `zig build test`
Expected: All tests pass

**Step 3: Commit**

```bash
git add src/cli/mod.zig
git commit -m "test: TCKTS-XX add unit tests for update command aliases"
```

---

## Task 12: Final Verification

**Step 1: Run full test suite**

```bash
zig build test && zig build && zig build e2e
```

**Step 2: Manual smoke test**

```bash
# Create test project
zig build run -- init TEST

# Add a ticket
zig build run -- add "Test ticket" -p TEST

# Test update variations
zig build run -- update TEST-1 --title "New title"
zig build run -- update TEST-1 --status in_progress
zig build run -- update TEST-1 -s done

# Verify with show
zig build run -- show TEST-1

# Test aliases
zig build run -- set TEST-1 --title "Alias test"
zig build run -- edit TEST-1 -d "Description via alias"
```

**Step 3: Clean up test data**

```bash
rm -rf .tckts/TEST.tckts
```

**Step 4: Final commit if any remaining changes**

```bash
git status
# If clean, done!
```

---

## Summary

| Task | Description |
|------|-------------|
| 1 | Add `Ticket.setTitle()` method |
| 2 | Add `Ticket.setDescription()` method |
| 3 | Add `Ticket.setStatus()` method with history |
| 4 | Add `Project.updateTicket()` method |
| 5 | Create `update.zig` command handler |
| 6 | Register in `commands/mod.zig` |
| 7 | Add to Command enum with aliases |
| 8 | Wire dispatch in `main.zig` |
| 9 | Add E2E tests |
| 10 | Refactor `done`/`start` to use updateTicket |
| 11 | Add unit tests for aliases |
| 12 | Final verification |

**Key decisions:**
- `done` and `start` remain as separate commands (backwards compatible) but internally use `updateTicket`
- Aliases: `set`, `edit` → `update`
- Only status changes recorded in history (title/description are not)
- Validation: title max 280 chars, description max 64KB
