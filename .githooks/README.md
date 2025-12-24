# Git Hooks

This directory contains git hooks for the tckts project.

## Setup

Install the project's git hooks:

```bash
git config core.hooksPath .githooks
```

## Troubleshooting

If hooks aren't running, ensure they are executable:

```bash
chmod +x .githooks/*
```
