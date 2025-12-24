#!/bin/bash
# keep-going.sh - Autonomous mode with [START], [PAUSE], [CONTINUE], [STOP] controls

# Read hook input from stdin
INPUT=$(cat)

# Extract transcript_path from the JSON input
TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)

# Default: not in autonomous mode
AUTONOMOUS="false"

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Find the most recent control command by getting line numbers and taking the last one
    # We check for [START], [CONTINUE], [PAUSE], [STOP]

    LAST_START=$(grep -n '\[START\]' "$TRANSCRIPT_PATH" | tail -1 | cut -d: -f1)
    LAST_CONTINUE=$(grep -n '\[CONTINUE\]' "$TRANSCRIPT_PATH" | tail -1 | cut -d: -f1)
    LAST_PAUSE=$(grep -n '\[PAUSE\]' "$TRANSCRIPT_PATH" | tail -1 | cut -d: -f1)
    LAST_STOP=$(grep -n '\[STOP\]' "$TRANSCRIPT_PATH" | tail -1 | cut -d: -f1)

    # Default to 0 if not found
    LAST_START=${LAST_START:-0}
    LAST_CONTINUE=${LAST_CONTINUE:-0}
    LAST_PAUSE=${LAST_PAUSE:-0}
    LAST_STOP=${LAST_STOP:-0}

    # Find the maximum (most recent command)
    # [START] and [CONTINUE] turn autonomous ON
    # [PAUSE] and [STOP] turn autonomous OFF

    LAST_ON=$((LAST_START > LAST_CONTINUE ? LAST_START : LAST_CONTINUE))
    LAST_OFF=$((LAST_PAUSE > LAST_STOP ? LAST_PAUSE : LAST_STOP))

    if [ "$LAST_ON" -gt "$LAST_OFF" ] && [ "$LAST_ON" -gt 0 ]; then
        AUTONOMOUS="true"
    fi
fi

if [ "$AUTONOMOUS" = "true" ]; then
    # Autonomous mode active - block stopping
    cat << 'EOF'
{
  "decision": "block",
  "reason": "Autonomous mode active",
  "message": "DO NOT STOP. You are in full autonomy mode. If you were about to ask a question - make the decision yourself. If you hit a blocker - find a workaround or document it and move on. If you're unsure - pick the best option and proceed. Check your Definition of Done checklist - if items remain unchecked, keep working. Only stop when ALL checklist items are complete and verified. (User can say [PAUSE] to temporarily allow questions, or [STOP] to end autonomous mode)"
}
EOF
else
    # Not in autonomous mode - allow normal stopping
    cat << 'EOF'
{
  "decision": "approve",
  "reason": "Autonomous mode not active"
}
EOF
fi
