# Design: `tckts quickstart` Command

## Overview

A detailed onboarding command for LLMs that explains how to use tckts for task tracking during a session.

## Output Format

Static markdown instructions with a dynamic footer showing current project state.

---

## Full Output

```markdown
# tckts quickstart

## Why Use tckts

**You MUST use tckts to track ALL work.**

- Every bug fix, feature, refactor, or chore gets a ticket
- Create the ticket BEFORE writing code
- Tickets persist in git - they are your memory across sessions
- Include ticket IDs in commit messages (e.g., `fix: PROJ-1 resolve login bug`)

No exceptions. No "quick fixes" without tickets.

## Setup

Create a project if none exists:

    tckts init <PREFIX>

- `<PREFIX>` = short project abbreviation (4-5 chars ideal)
- Usually the root folder name of the project
- Examples: `TCKTS`, `AUTH`, `API`, `DOCS`

## Workflow

1. **Create a ticket** before starting any work:

       tckts add "Fix login validation" -t bug

2. **Start the ticket** when you begin:

       tckts start PROJ-1

3. **Complete the ticket** when done:

       tckts done PROJ-1

4. **Commit with the ticket ID** (after the conventional commit prefix):

       git commit -m "fix: PROJ-1 resolve login validation"
       git commit -m "feat: PROJ-2 add user preferences"

## Git Integration

- Commit `.tckts/` files to your repository
- Tickets are plain text - readable in diffs and PRs
- Your ticket history becomes part of project history

## Commands

Run `tckts help` for full command reference.

---

## Current State

TCKTS: 2 pending, 0 in-progress, 0 completed
```

If no projects exist, the footer shows:

```markdown
## Current State

No projects found. Run: tckts init <PREFIX>
```

---

## Implementation

1. Create `src/cli/commands/quickstart.zig`
2. Add `quickstart` to command enum in `src/cli/mod.zig`
3. Wire up dispatch in `src/cli/commands/mod.zig`
4. Static content as a multiline string literal
5. Dynamic footer: iterate projects, count tickets by status
