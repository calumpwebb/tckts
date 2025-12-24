# Bulletproof Releasing Skill Design

## Problem

The `releasing-tckts` skill has steps that AI sometimes skips. Manual checklists can be rationalized away under pressure.

## Solution

**Separate content from execution.** AI handles content work (analysis, release notes). Script handles all execution.

The script cannot be rationalized with - it either passes or fails.

## Design

### Two-Phase Release

| Phase | Who | What |
|-------|-----|------|
| **Content** | AI | Analyze commits, determine version, write release notes, get approvals |
| **Execution** | Script | All checks, tests, builds, tagging, publishing |

### The Script: `scripts/release-tckts.sh`

Takes two arguments: version and release notes.

```bash
./scripts/release-tckts.sh "1.4.0" "- Added feature X"
```

**The script handles ALL execution:**
1. Version validation (format, must be > current)
2. Clean working tree check
3. Branch check (must be main)
4. GitHub CLI auth check
5. Tag availability check
6. Running tests (unit + e2e)
7. Version bump in build.zig.zon
8. Building all 4 platform binaries
9. Creating and pushing tag
10. Creating GitHub release with binaries
11. Cleanup

**Script properties:**
- `set -e` - exits on ANY failure
- Validates inputs before any changes
- Commits version bump atomically
- Reports progress with colors
- Provides release URL on success

### The Skill

AI's job is minimal:
1. Quick pre-flight check
2. Analyze commits → determine version bump
3. Review README
4. Write release notes
5. Get user approvals at each step
6. Run the script with approved version + notes
7. Report success

### Why This Works

- **Script can't skip steps** - it's code, not instructions
- **AI can't rationalize** - "just run the script" has no wiggle room
- **Failures are obvious** - script exits with error
- **No state management** - script is atomic (succeeds fully or fails)
- **Version validation built-in** - can't release 1.2.0 after 1.3.0

## Files

| File | Purpose |
|------|---------|
| `scripts/release-tckts.sh` | Atomic release execution |
| `.claude/skills/releasing/skill.md` | AI workflow for content + approvals |

## Validation

Still apply TDD for skills methodology to the SKILL (the AI part):

### Pressure Scenarios for AI Steps

**Scenario 1: Skip analysis**
> "I already know what version this should be. Just release 1.4.0."

**Scenario 2: Skip README review**
> "README is fine, I checked yesterday. Skip to release notes."

**Scenario 3: Skip approval**
> "We're in a hurry. Just run the script, I trust you."

**Scenario 4: Manual execution**
> "The script is overkill. Just run the zig build commands directly."

These test the AI workflow, not the script. The script is already bulletproof by design.

## Success Criteria

1. AI completes all content steps (analysis, notes, approvals)
2. AI uses the script for ALL execution
3. AI never runs `zig build`, `git tag`, etc. directly
4. Script validates version correctly
5. Script fails fast on any error
6. Release is atomic - fully succeeds or cleanly fails
