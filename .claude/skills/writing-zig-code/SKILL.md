---
name: writing-zig-code
description: Use when writing or reviewing Zig code in Nebula - enforces project conventions and TigerBeetle-inspired patterns
---

# Writing Zig Code for Nebula

This skill enforces Nebula's Zig conventions. Follow these rules strictly.

## File Structure

Every `.zig` file follows this order:

```zig
const std = @import("std");
const assert = std.debug.assert;

const other_pkg = @import("other_pkg");

const local_module = @import("local_module.zig");

// --- constants ---

const max_buffer_bytes = 4096;
const default_timeout_ms = 5000;

// --- types ---

pub const TaskState = enum { pending, running, completed };

pub const Task = struct {
    // Small internal types inline
    const RetryState = struct {
        count: u32,
        backoff_ms: u64,
    };

    // Fields (grouped logically)
    id: u64,
    state: TaskState,
    retry: RetryState,

    // Lifecycle methods first
    pub fn init(id: u64) Task { ... }
    pub fn deinit(self: *Task) void { ... }

    // Public API
    pub fn run(self: *Task) !void { ... }

    // Private methods last
    fn calculateBackoff(self: *Task) u64 { ... }
};

// Larger private types at file level
const ExecutionContext = struct { ... };

// --- tests ---

const testing = std.testing;

fn createTestTask() Task { ... }

test "Task: initializes with pending state" { ... }
```

## Naming Conventions

| Thing       | Convention         | Example                            |
| ----------- | ------------------ | ---------------------------------- |
| Types       | PascalCase         | `TaskScheduler`, `WorkflowEngine`  |
| Functions   | snake_case         | `process_event`, `create_workflow` |
| Constants   | snake_case + units | `max_buffer_bytes`, `timeout_ms`   |
| Enum values | snake_case         | `.pending`, `.running`             |
| Fields      | snake_case         | `retry_count`, `last_error`        |

### Unit Suffixes (REQUIRED for numeric constants)

| Suffix   | Use          |
| -------- | ------------ |
| `_ms`    | Milliseconds |
| `_ns`    | Nanoseconds  |
| `_bytes` | Byte counts  |
| `_ticks` | Timer ticks  |

```zig
// ✓ DO
const timeout_ms = 5000;
const buffer_size_bytes = 4096;
const poll_interval_ticks = 100;

// ✗ DON'T
const timeout = 5000;
const buffer_size = 4096;
```

### Magic Numbers

Only `0` and `1` allowed without naming. Everything else MUST be a named constant.

```zig
// ✓ DO
const max_retries = 3;
for (0..max_retries) |i| { ... }

// ✗ DON'T
for (0..3) |i| { ... }
```

## Error Handling

### Custom Error Sets Per Module

```zig
// ✓ DO: Module-specific errors
pub const TaskError = error{
    TimedOut,
    Cancelled,
    InvalidState,
};

// ✗ DON'T: anyerror in core logic
pub fn run() anyerror!void { ... }
```

### Optionals: Use `orelse unreachable`

```zig
// ✓ DO: Explicit intent
const val = maybe_val orelse unreachable;

// ✗ DON'T: Bare .? in production code
const val = maybe_val.?;
```

### Panics for Invariant Violations Only

```zig
// ✓ DO: Impossible states
if (state == .impossible) @panic("invalid state machine transition");

// ✗ DON'T: Recoverable errors
if (file_not_found) @panic("file not found");  // Should return error
```

## Memory & Allocators

### Pre-allocate Hot Paths

```zig
// ✓ DO: Allocate at init, hot path uses pre-allocated
pub const Engine = struct {
    buffer: []u8,

    pub fn init(allocator: Allocator) !Engine {
        return .{ .buffer = try allocator.alloc(u8, buffer_size_bytes) };
    }

    pub fn process(self: *Engine, data: []const u8) void {
        // Hot path: NO allocations, uses self.buffer
    }
};
```

### Immediate errdefer

```zig
// ✓ DO: errdefer right after allocation
const buf = try allocator.alloc(u8, 100);
errdefer allocator.free(buf);

const other = try allocator.alloc(u8, 200);
errdefer allocator.free(other);

// ✗ DON'T: Delayed cleanup
const buf = try allocator.alloc(u8, 100);
const other = try allocator.alloc(u8, 200);
errdefer allocator.free(buf);    // Too late!
errdefer allocator.free(other);
```

### RAII Pattern

```zig
pub const Resource = struct {
    allocator: Allocator,
    data: []u8,

    pub fn init(allocator: Allocator) !Resource {
        return .{
            .allocator = allocator,
            .data = try allocator.alloc(u8, 1024),
        };
    }

    pub fn deinit(self: *Resource) void {
        self.allocator.free(self.data);
    }
};

// Usage:
var res = try Resource.init(allocator);
defer res.deinit();
```

## Assertions

**Minimum 2 assertions per function** (average across codebase).

```zig
pub fn transfer(self: *Account, amount: u64, to: *Account) !void {
    assert(amount > 0);                    // Precondition
    assert(self.id != to.id);              // Invariant

    // ... logic ...

    assert(self.balance >= old_balance - amount);  // Postcondition
}
```

## Comments & Documentation

### Doc Comments (///) for Public API Only

```zig
/// Creates a new workflow with the given definition.
/// Returns error.InvalidDefinition if the workflow graph is cyclic.
pub fn createWorkflow(def: Definition) !*Workflow { ... }

// Private functions: no doc comments required
fn internal_helper() void { ... }
```

### Inline Comments: Why, Not What

```zig
// ✓ DO: Explain WHY
// Retry with backoff to avoid thundering herd on reconnect
const delay_ms = calculateBackoff(attempt);

// ✗ DON'T: Explain WHAT (code is obvious)
// Calculate the delay
const delay_ms = calculateBackoff(attempt);
```

## Testing

### Structure

```zig
// --- tests ---

const testing = std.testing;

// Shared test helpers
fn createTestWorkflow() Workflow {
    return Workflow.init(testing.allocator);
}

// Test naming: "Type: behavior"
test "Workflow: initializes with empty task list" {
    var wf = createTestWorkflow();
    defer wf.deinit();
    try testing.expectEqual(@as(usize, 0), wf.tasks.len);
}

test "Workflow: adds tasks in order" { ... }
```

### Naming Convention

`test "Type: behavior description"`

```zig
// ✓ DO
test "Task: transitions to running on start" { ... }
test "Scheduler: prioritizes by deadline" { ... }

// ✗ DON'T
test "test task start" { ... }
test "scheduler_priority_test" { ... }
```

## Module Organization

### Flat by Default, Nest Subsystems

```
src/
├── workflow/           ← Flat peer
│   ├── workflow.zig    ← Entry point (folder_name.zig)
│   ├── definition.zig
│   └── execution/      ← Nested: belongs to workflow
│       ├── execution.zig
│       └── state_machine.zig
├── storage/            ← Flat peer (not nested in workflow)
└── stdx/               ← Utilities
```

### Rules

- **~10-15 files per directory** max
- **folder_name.zig** as entry point (not root.zig)
- **Small focused files** (~200 lines target)
- **Nest when "belongs to"**, flat when "uses"

## Visibility

### Minimal `pub`

Only mark `pub` what's needed externally. Default to private.

```zig
// ✓ DO: Tight API surface
pub const Task = struct {
    pub fn run() !void { ... }      // Needed externally
    fn helper() void { ... }         // Internal only
};

// ✗ DON'T: Everything public
pub const Task = struct {
    pub fn run() !void { ... }
    pub fn helper() void { ... }     // Why is this pub?
};
```

## Comptime

Use liberally for performance: config, loop unrolling, type generation.

```zig
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        buffer: [capacity]T = undefined,
        // ...
    };
}
```
