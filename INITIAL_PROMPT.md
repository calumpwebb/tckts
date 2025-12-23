# Mission: Build a CLI Todo Tracker in Zig

## Autonomy Level: FULL
Do not ask for my help. Make all decisions yourself. If something is ambiguous,
make the best choice and document why. I will not be available to answer questions.

## What You're Building
A CLI todo/task tracker inspired by "beads" (a tool that stores todos in the repo
for LLM consumption). This is NOT a clone - take creative liberty on naming, UX,
and implementation details.

The core idea: plain-text task storage that lives in the repo, designed to be
both human-readable AND easily parsed by LLMs working on the codebase.

## Hard Requirements (Non-Negotiable)
1. **Language**: Zig 0.15 (latest stable)
2. **Zero external dependencies** - stdlib only
3. **Plain text storage** - NO JSON, NO YAML, NO TOML. Design your own simple
   human-readable format that's still parseable
4. **Multi-project support** - one repo can have multiple independent task lists
   (user configures a prefix/namespace when setting up)
5. **Task dependencies** - tasks can depend on other tasks (blocked until deps done)
6. **No split-brain** - single source of truth, no sync conflicts possible
7. **Comprehensive test suite** - unit tests, integration tests for CLI
8. **Documentation** - README with usage examples, `--help` that actually helps
9. **Simple CLI UX** - intuitive commands, good error messages

## Decisions For You To Make
- Project name and branding
- File format design (how to structure the plain text)
- CLI command structure and subcommands
- How to handle the multi-project namespacing
- Where files are stored (`.tasks/`? root? configurable?)
- What metadata to track (created date? priority? tags?)
- How to display tasks (formatting, colors, etc.)

## Process Expectations
1. Plan your approach first (write it down somewhere I can see)
2. Design the file format before coding
3. Write tests alongside implementation
4. Verify everything works before claiming done
5. Commit with meaningful messages

## Definition of Done
- [ ] `zig build` succeeds with no warnings
- [ ] `zig build test` passes all tests
- [ ] CLI has working: init, add, list, complete, delete commands (minimum)
- [ ] Dependency tracking works (can't complete task if deps incomplete)
- [ ] Multiple projects in same repo works
- [ ] README documents all commands with examples
- [ ] `--help` works on all commands
- [ ] At least one realistic usage scenario tested end-to-end

## Style
- Idiomatic Zig
- Clear variable/function names
- Comments only where logic isn't obvious
- Handle errors properly, don't panic on user mistakes

---

## How This Works

Read this prompt, ask any clarifying questions you need, and plan your approach.

**Control Commands:**
- `[START]` - Activates autonomous mode. From this point, you cannot stop to ask questions.
- `[PAUSE]` - Temporarily suspends autonomous mode. You can ask questions again.
- `[CONTINUE]` - Resumes autonomous mode after a pause.
- `[STOP]` - Fully terminates autonomous mode.

Once in autonomous mode, you must make all decisions yourself and keep working
until the Definition of Done is complete.

Good luck. Show me what you build.
