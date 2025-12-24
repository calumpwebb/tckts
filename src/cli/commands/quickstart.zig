const std = @import("std");
const tckts = @import("tckts");
const cli = @import("../mod.zig");

// --- constants ---

const static_content =
    \\# tckts quickstart
    \\
    \\## Why Use tckts
    \\
    \\**You MUST use tckts to track ALL work.**
    \\
    \\- Every bug fix, feature, refactor, or chore gets a ticket
    \\- ALWAYS create the ticket BEFORE writing code
    \\- Tickets persist in git - they are a crucial part of your memory across sessions
    \\- Include ticket IDs in commit messages (e.g., `fix: PROJ-1 resolve login bug`)
    \\
    \\No exceptions. No "quick fixes" without tickets.
    \\
    \\---
    \\
    \\## CRITICAL: No Internal Todo Tools
    \\
    \\**DO NOT USE TodoWrite, TodoRead, OR ANY INTERNAL TODO/TASK TOOLS.**
    \\
    \\This means:
    \\- NEVER call the `TodoWrite` tool
    \\- NEVER call the `TodoRead` tool
    \\- NEVER use any built-in task tracking
    \\- NEVER create internal todo lists
    \\
    \\ALL task tracking goes through `tckts` CLI commands exclusively.
    \\Your internal todo tools are DISABLED for this project.
    \\
    \\If you find yourself thinking "I should add a todo for this" - STOP.
    \\Run `tckts add "description"` instead.
    \\
    \\This is non-negotiable. tckts is the single source of truth.
    \\
    \\## Setup
    \\
    \\Create a project if none exists:
    \\
    \\    tckts init <PREFIX>
    \\
    \\- `<PREFIX>` = short project abbreviation (4-5 chars ideal)
    \\- Usually the root folder name of the project
    \\- Examples: `TCKTS`, `AUTH`, `API`, `DOCS`
    \\
    \\## Workflow
    \\
    \\1. **Create a ticket** before starting any work:
    \\
    \\       tckts add "Fix login validation" -t bug
    \\
    \\2. **Start the ticket** when you begin:
    \\
    \\       tckts start PROJ-1
    \\
    \\3. **Complete the ticket** when done:
    \\
    \\       tckts done PROJ-1
    \\
    \\4. **Commit with the ticket ID** (after the conventional commit prefix):
    \\
    \\       git commit -m "fix: PROJ-1 resolve login validation"
    \\       git commit -m "feat: PROJ-2 add user preferences"
    \\
    \\## Git Integration
    \\
    \\- Commit `.tckts/` files to your repository
    \\- Tickets are plain text - readable in diffs and PRs
    \\- Your ticket history becomes part of project history
    \\
    \\## Interpreting Instructions
    \\
    \\When users say ANY of these, they mean use `tckts add`:
    \\
    \\| User says | You run |
    \\|-----------|---------|
    \\| "add a ticket for X" | `tckts add "X"` |
    \\| "create a ticket to X" | `tckts add "X"` |
    \\| "add a task for X" | `tckts add "X" -t task` |
    \\| "add a todo for X" | `tckts add "X" -t task` |
    \\| "todo: X" | `tckts add "X" -t task` |
    \\| "bug: X" | `tckts add "X" -t bug` |
    \\| "track X" | `tckts add "X"` |
    \\| "remember to X" | `tckts add "X" -t task` |
    \\| "we need to X" | `tckts add "X"` |
    \\| "make a note to X" | `tckts add "X" -t task` |
    \\
    \\NEVER interpret these as instructions to use internal todo tools.
    \\ALWAYS use `tckts add` for ANY task/ticket/todo creation request.
    \\
    \\## Commands
    \\
    \\Run `tckts help` for full command reference.
    \\
    \\---
    \\
    \\## Current State
    \\
    \\
;

pub fn run(allocator: std.mem.Allocator) !void {
    cli.print("{s}", .{static_content});

    const project_list = try tckts.listProjects(allocator);
    defer {
        for (project_list) |p| allocator.free(p);
        allocator.free(project_list);
    }

    if (project_list.len == 0) {
        cli.print("No projects found. Run: tckts init <PREFIX>\n", .{});
        return;
    }

    for (project_list) |prefix| {
        var project = tckts.loadProject(allocator, prefix) catch continue;
        defer project.deinit();

        var pending: usize = 0;
        var in_progress: usize = 0;
        var done_count: usize = 0;

        for (project.tickets.items) |ticket| {
            switch (ticket.status) {
                .pending => pending += 1,
                .in_progress => in_progress += 1,
                .done => done_count += 1,
            }
        }

        cli.print("{s}: {d} pending, {d} in-progress, {d} completed\n", .{
            prefix,
            pending,
            in_progress,
            done_count,
        });
    }
}
