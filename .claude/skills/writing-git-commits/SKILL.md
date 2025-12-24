---
name: writing-git-commits
description: Use when creating git commits - enforces Conventional Commits format, atomic commit structure, and clear commit history
---

# Writing Git Commits

## Overview

Every commit tells a story. Follow Conventional Commits for machine-readable, human-understandable commit history.

**Core principle:** Each commit should be atomic — one logical change that could be reverted independently.

## When to Use

```dot
digraph commit_decision {
    "Ready to commit?" [shape=diamond];
    "Multiple logical changes?" [shape=diamond];
    "Split into separate commits" [shape=box];
    "Write commit message" [shape=box];

    "Ready to commit?" -> "Multiple logical changes?" [label="yes"];
    "Multiple logical changes?" -> "Split into separate commits" [label="yes"];
    "Multiple logical changes?" -> "Write commit message" [label="no"];
    "Split into separate commits" -> "Write commit message";
}
```

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type       | When to Use                         | SemVer |
| ---------- | ----------------------------------- | ------ |
| `feat`     | New feature or capability           | MINOR  |
| `fix`      | Bug fix                             | PATCH  |
| `chore`    | Maintenance, setup, config          | -      |
| `docs`     | Documentation only                  | -      |
| `refactor` | Code change without behavior change | -      |
| `test`     | Adding or fixing tests              | -      |
| `perf`     | Performance improvement             | -      |
| `ci`       | CI/CD changes                       | -      |
| `build`    | Build system changes                | -      |
| `style`    | Formatting, whitespace              | -      |

### Scopes

Use parentheses to indicate affected subsystem:

```
feat(toolkit): add new skill
fix(api): handle null response
chore(deps): update dependencies
```

### Breaking Changes

Mark with `!` before colon or `BREAKING CHANGE:` footer:

```
feat!: remove deprecated API

BREAKING CHANGE: The v1 API endpoints have been removed.
```

## Writing Good Descriptions

**DO:**

- Use imperative mood: "add feature" not "added feature"
- Keep under 50 characters
- Focus on WHY, not WHAT (code shows what)
- Be specific: "fix null pointer in auth flow" not "fix bug"

**DON'T:**

- End with period
- Use vague terms: "update", "change", "modify" without context
- Reference issue numbers in subject (use footer)

## Body Guidelines

- Separate from subject with blank line
- Wrap at 72 characters
- Explain motivation and contrast with previous behavior
- Use bullet points for multiple items

```
fix(auth): prevent session fixation on login

Previously, session IDs were preserved across authentication,
allowing potential session fixation attacks.

- Regenerate session ID after successful authentication
- Clear old session data before creating new session
- Add session rotation on privilege escalation
```

## Atomicity Guidelines

```dot
digraph atomicity {
    "What am I committing?" [shape=diamond];
    "Infrastructure/scaffold?" [shape=diamond];
    "New functionality?" [shape=diamond];
    "Use chore" [shape=box];
    "Use feat" [shape=box];
    "Bug fix?" [shape=diamond];
    "Use fix" [shape=box];
    "Separate commits" [shape=box];

    "What am I committing?" -> "Infrastructure/scaffold?" [label="setup"];
    "Infrastructure/scaffold?" -> "Use chore" [label="yes"];
    "What am I committing?" -> "New functionality?" [label="feature"];
    "New functionality?" -> "Use feat" [label="yes"];
    "What am I committing?" -> "Bug fix?" [label="fix"];
    "Bug fix?" -> "Use fix" [label="yes"];
    "What am I committing?" -> "Separate commits" [label="multiple things"];
}
```

**Split commits when:**

- Adding scaffold AND functionality (two commits)
- Fixing multiple independent bugs
- Refactoring AND adding features
- Changes could be reverted independently

**Keep together when:**

- Changes are tightly coupled
- One change doesn't make sense without the other
- It's a single logical unit of work

## Examples

### Initial Project Setup (Multiple Commits)

```
# Commit 1: Foundation
chore: initialize project

Set up the foundation for the application.

# Commit 2: Tooling scaffold
chore(tooling): initialize development environment

Add configuration and tooling infrastructure.

- Build configuration
- Linting setup
- Development scripts

# Commit 3: First feature
feat(tooling): add code generation utilities

Implement utilities for generating boilerplate code.
```

### Feature Addition

```
feat(auth): add password reset flow

Allow users to reset passwords via email link.

- Add reset token generation with 1-hour expiry
- Create reset email template
- Add rate limiting (3 requests per hour)
```

### Bug Fix

```
fix(api): handle race condition in connection pool

Connections were being returned to pool before response
completion, causing intermittent failures under load.

Fixes #234
```

## HEREDOC Format for Multi-line Messages

Always use HEREDOC for commit messages with bodies:

```bash
git commit -m "$(cat <<'EOF'
feat(scope): description here

Body paragraph explaining the change.

- Bullet point one
- Bullet point two
EOF
)"
```

## Common Mistakes

| Mistake                     | Fix                                                      |
| --------------------------- | -------------------------------------------------------- |
| "Fixed stuff"               | Be specific: "fix(auth): prevent null pointer on logout" |
| Mixing concerns             | Split into atomic commits                                |
| Huge commits                | Break down by logical unit                               |
| No body for complex changes | Explain WHY, not just WHAT                               |
| Past tense "Added feature"  | Imperative "Add feature"                                 |

## Red Flags - Reconsider Your Commit

- Commit touches 10+ unrelated files
- Description needs "and" to explain changes
- You're tempted to write "various fixes"
- Changes span multiple subsystems for different reasons
- You can't summarize in under 50 characters

**If any apply:** Split into multiple atomic commits.
