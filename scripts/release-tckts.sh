#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }

# --- Argument parsing ---

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <version> <release-notes>"
    echo "Example: $0 1.4.0 '- Added feature X'"
    exit 1
fi

NEW_VERSION=$1
RELEASE_NOTES=$2

# --- Version validation ---

# Check version format (semver: X.Y.Z)
if ! [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Version must be in semver format (X.Y.Z), got: $NEW_VERSION"
fi

# Get current version from build.zig.zon
CURRENT_VERSION=$(grep '\.version = ' build.zig.zon | sed 's/.*"\([0-9.]*\)".*/\1/')
if [[ -z $CURRENT_VERSION ]]; then
    error "Could not parse current version from build.zig.zon"
fi

info "Current version: $CURRENT_VERSION"
info "New version: $NEW_VERSION"

# Compare versions (returns 0 if $1 > $2)
version_gt() {
    local IFS=.
    local i
    local v1=($1)
    local v2=($2)

    for ((i=0; i<3; i++)); do
        if ((v1[i] > v2[i])); then
            return 0
        elif ((v1[i] < v2[i])); then
            return 1
        fi
    done
    return 1  # Equal means not greater
}

if ! version_gt "$NEW_VERSION" "$CURRENT_VERSION"; then
    error "New version ($NEW_VERSION) must be greater than current version ($CURRENT_VERSION)"
fi

info "Version check passed: $NEW_VERSION > $CURRENT_VERSION"

# --- Pre-flight checks ---

info "Running pre-flight checks..."

# Check for clean working tree
if ! git diff --quiet || ! git diff --cached --quiet; then
    error "Working tree must be clean. Commit or stash changes first."
fi
info "  Working tree is clean"

# Check we're on main
CURRENT_BRANCH=$(git branch --show-current)
if [[ $CURRENT_BRANCH != "main" ]]; then
    error "Must be on 'main' branch, currently on '$CURRENT_BRANCH'"
fi
info "  On main branch"

# Check gh CLI is authenticated
if ! gh auth status &>/dev/null; then
    error "GitHub CLI not authenticated. Run 'gh auth login' first."
fi
info "  GitHub CLI authenticated"

# Check tag doesn't already exist
if git rev-parse "v$NEW_VERSION" &>/dev/null; then
    error "Tag v$NEW_VERSION already exists"
fi
info "  Tag v$NEW_VERSION is available"

# --- Run tests ---

info "Running tests..."
zig build test
info "  Unit tests passed"

zig build e2e
info "  E2E tests passed"

# --- Bump version ---

info "Bumping version to $NEW_VERSION..."
sed -i '' "s/\.version = \".*\"/\.version = \"$NEW_VERSION\"/" build.zig.zon

# Verify the change
NEW_CHECK=$(grep '\.version = ' build.zig.zon | sed 's/.*"\([0-9.]*\)".*/\1/')
if [[ $NEW_CHECK != $NEW_VERSION ]]; then
    error "Version bump failed. Expected $NEW_VERSION, got $NEW_CHECK"
fi

git add build.zig.zon
git commit -m "chore: bump version to $NEW_VERSION"
info "  Version bumped and committed"

# --- Build all targets ---

info "Building release binaries..."

# Clean previous builds
rm -f tckts-*

TARGETS=(
    "x86_64-linux:tckts-linux-x86_64"
    "aarch64-linux:tckts-linux-aarch64"
    "x86_64-macos:tckts-macos-x86_64"
    "aarch64-macos:tckts-macos-aarch64"
)

for target_pair in "${TARGETS[@]}"; do
    target="${target_pair%%:*}"
    output="${target_pair##*:}"

    info "  Building $output..."
    zig build -Doptimize=ReleaseFast -Dtarget="$target"
    mv zig-out/bin/tckts "$output"
done

info "  All binaries built"

# Verify all binaries exist
for target_pair in "${TARGETS[@]}"; do
    output="${target_pair##*:}"
    if [[ ! -f $output ]]; then
        error "Binary $output not found after build"
    fi
done

# --- Create release ---

info "Creating GitHub release..."

git tag "v$NEW_VERSION"
git push origin main --tags
info "  Tag pushed"

gh release create "v$NEW_VERSION" tckts-* \
    --title "v$NEW_VERSION" \
    --notes "$RELEASE_NOTES"
info "  GitHub release created"

# --- Cleanup ---

info "Cleaning up..."
rm -f tckts-*
info "  Local binaries removed"

# --- Done ---

echo ""
info "Successfully released v$NEW_VERSION!"
echo ""
echo "Release URL: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/v$NEW_VERSION"
