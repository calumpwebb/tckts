---
name: releasing
description: Use when creating releases - analyzes commits, bumps version, builds all targets, creates GitHub release
---

# Releasing

## When This Applies

- User runs `/release`
- User says "create a release", "cut a release", "ship it"
- User wants to publish a new version

## Pre-Flight Checks

Before starting, verify ALL of these:

```bash
# 1. Check current branch
git branch --show-current  # Should be main (warn if not)

# 2. Check for clean working tree
git status  # Must be clean - stop if dirty

# 3. Check gh CLI is authenticated
gh auth status  # Must be logged in

# 4. Get last tag
git describe --tags --abbrev=0 2>/dev/null || echo "first release"
```

### README Review

Read `README.md` and verify it reflects the current state of the project:
- Features listed match what's actually implemented
- Installation instructions are correct
- Usage examples work with current CLI
- No stale/outdated information

→ **AskUserQuestion**: "README.md looks [up to date / needs updates]. Proceed with release?"
  - If needs updates: list specific issues found
  - Options: Proceed / Update README first

**Stop conditions:**
- Dirty working tree → hard stop, ask to commit/stash first
- gh not authenticated → hard stop, show `gh auth login`
- Not on main → warn but allow override via AskUserQuestion
- README needs updates → warn and allow override, or stop to update first

## Workflow

### Step 1: Analyze Commits

```bash
# Get commits since last tag (or all if no tags)
git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline
```

Parse conventional commit prefixes to determine bump type:
- `BREAKING CHANGE` or `!:` in message → **major**
- `feat:` → **minor**
- `fix:`, `chore:`, `docs:`, `refactor:`, `test:` → **patch**

Take the highest level found. Calculate new version from current.

→ **AskUserQuestion**: "Based on commits, this looks like a [minor] bump: 1.1.0 → 1.2.0. Proceed?"
  - Options: Confirm / Major instead / Minor instead / Patch instead

### Step 2: Generate Release Notes

Read all commits since last tag. Write 3-5 user-facing bullet points that summarize what changed. Be specific and honest - no "various improvements" or "bug fixes".

→ **AskUserQuestion**: "Release notes look good?" (show the notes)
  - Options: Confirm / Let me edit

### Step 3: Bump Version

Update version in TWO places:

**build.zig.zon** - find and update the `.version` field:
```zig
.version = "X.Y.Z",
```

**src/main.zig** - find and update the version constant:
```zig
const version = "X.Y.Z";
```

Commit the change:
```bash
git add build.zig.zon src/main.zig
git commit -m "chore: bump version to X.Y.Z"
```

### Step 4: Build All Targets

Build all 5 platform binaries:

```bash
# Clean previous builds
rm -f tckts-*

# Linux
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux
mv zig-out/bin/tckts tckts-linux-x86_64

zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux
mv zig-out/bin/tckts tckts-linux-aarch64

# macOS
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-macos
mv zig-out/bin/tckts tckts-macos-x86_64

zig build -Doptimize=ReleaseFast -Dtarget=aarch64-macos
mv zig-out/bin/tckts tckts-macos-aarch64

# Windows
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows
mv zig-out/bin/tckts.exe tckts-windows-x86_64.exe
```

**If any build fails, stop immediately.** Show the error, do not proceed.

### Step 5: Create Release

→ **AskUserQuestion**: "Ready to tag vX.Y.Z, push, and create GitHub release?"
  - Options: Confirm / Abort

```bash
# Create and push tag
git tag vX.Y.Z
git push origin main --tags

# Create GitHub release with binaries
gh release create vX.Y.Z tckts-* \
  --title "vX.Y.Z" \
  --notes "$(cat <<'EOF'
[Release notes here]
EOF
)"
```

### Step 6: Cleanup

```bash
# Remove local binary files
rm -f tckts-*
```

Report success with link to the release.

## Error Recovery

| Failure Point | State | Recovery |
|---------------|-------|----------|
| Build fails | No commits pushed | Fix issue, re-run `/release` |
| Push fails | Version committed locally | Fix network, `git push origin main --tags` |
| gh release fails | Tag pushed | `gh release create vX.Y.Z tckts-* --title "vX.Y.Z" --notes "..."` |

## File Locations

| What | Where |
|------|-------|
| Version (zon) | `build.zig.zon` → `.version = "X.Y.Z"` |
| Version (zig) | `src/main.zig` → `const version = "X.Y.Z"` |
| Install script | `install.sh` (no version, always fetches latest) |

## Binary Naming Convention

| Platform | Binary Name |
|----------|-------------|
| Linux x86_64 | `tckts-linux-x86_64` |
| Linux ARM64 | `tckts-linux-aarch64` |
| macOS Intel | `tckts-macos-x86_64` |
| macOS Apple Silicon | `tckts-macos-aarch64` |
| Windows | `tckts-windows-x86_64.exe` |
