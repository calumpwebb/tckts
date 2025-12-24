# Setting up hooks in Claude Code

Use the following configuration options to set up Claude Code to use the hooks defined here. Please remember to keep this up to date when editing, adding or removing hooks.

```
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/keep-going.sh"
          }
        ]
      }
    ]
  }
}
```
