---
name: releasing-tckts
description: Use when creating releases - analyzes commits, determines version, writes release notes, then runs release script
---

# Releasing

## When This Applies

- User runs `/release`
- User says "create a release", "cut a release", "ship it"
- User wants to publish a new version

## Overview

The release process has two parts:
1. **AI does content work** - analyze commits, determine version, write release notes
2. **Script does execution** - all checks, builds, tagging, and publishing

The script (`scripts/release-tckts.sh`) cannot be rationalized with - it either passes or fails.

## Workflow

### Step 1: Pre-flight Check (Quick)

Before any analysis, verify basics:

```bash
git status              # Must be clean
git branch --show-current  # Should be main
gh auth status          # Must be authenticated
tckts list --status in-progress  # Must be empty
```

**CRITICAL: No in-progress tickets allowed.**

If `tckts list --status in-progress` shows ANY tickets, **STOP immediately**. Do not proceed with the release.

Tell the user:
> "Cannot release with in-progress tickets. Please resolve these first:
> [list the tickets]
>
> Options:
> - `tckts done <ID>` - if work is complete
> - `tckts update <ID> --status pending` - if work is paused
> - `tckts update <ID> --status blocked` - if work is blocked"

Only proceed once all in-progress tickets are resolved.

If any other check fails, stop and tell user how to fix.

### Step 2: Analyze Commits

Get commits since last tag:

```bash
git describe --tags --abbrev=0 2>/dev/null  # Current version
git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline
```

Parse conventional commit prefixes to determine bump type:

| Prefix | Bump Type |
|--------|-----------|
| `BREAKING CHANGE` or `!:` | **major** |
| `feat:` | **minor** |
| `fix:`, `chore:`, `docs:`, `refactor:`, `test:` | **patch** |

Take the highest level found. Calculate new version.

> **AskUserQuestion**: "Based on commits, this looks like a [patch/minor/major] bump: X.Y.Z → A.B.C. Correct?"
> - Options: Confirm / Major instead / Minor instead / Patch instead

### Step 3: Review README

Read `README.md` and verify it reflects current state:

- Features match what's implemented
- Installation instructions are correct
- Usage examples work
- No stale information

> **AskUserQuestion**: "README looks [up to date / needs updates]. Proceed?"
> - If needs updates: list specific issues
> - Options: Proceed / Update README first

### Step 4: Generate Release Notes

Read all commits since last tag. Write 3-5 user-facing bullet points:

- Be specific and honest
- No "various improvements" or "bug fixes"
- Focus on what users care about

> **AskUserQuestion**: "Release notes look good?"
> - Show the notes
> - Options: Confirm / Let me edit

### Step 5: Final Confirmation

> **AskUserQuestion**: "Ready to release vX.Y.Z?"
> - Show: version, release notes summary
> - Options: Release / Abort

### Step 6: Run Release Script

**This is the only execution step.** Run:

```bash
./scripts/release-tckts.sh "X.Y.Z" "release notes here"
```

The script handles ALL of:
- Version validation (new > current, correct format)
- Clean working tree check
- Branch check (must be main)
- GitHub CLI auth check
- Tag availability check
- Running tests (unit + e2e)
- Version bump in build.zig.zon
- Building all 4 platform binaries
- Creating and pushing tag
- Creating GitHub release with binaries
- Cleanup

**If the script fails at any point, it stops and reports the error.**

### Step 7: Report Success

Show the release URL and confirm completion.

## Error Recovery

| Failure Point | Recovery |
|---------------|----------|
| Script fails early | Fix issue, re-run `/release` |
| Script fails after version bump | Check git log, may need manual recovery |
| Script fails after tag push | Run `gh release create` manually |

## The Iron Rule

> **Do NOT manually execute release steps.** All execution goes through the script.
>
> You analyze and write content. The script executes.
>
> If you find yourself typing `zig build` or `git tag` directly, STOP. Use the script.

## File Locations

| What | Where |
|------|-------|
| Release script | `scripts/release-tckts.sh` |
| Version | `build.zig.zon` → `.version = "X.Y.Z"` |
| Install script | `install.sh` (no version, fetches latest) |
