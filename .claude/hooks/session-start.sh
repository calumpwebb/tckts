#!/bin/bash
# session-start.sh - Tell the AI to run tckts quickstart at session start

cat << 'EOF'
{
  "output": "Run `tckts quickstart` at the start of this session to get context about the project and current tasks, you MUST follow ALL of the instructions in the output of the command."
}
EOF
