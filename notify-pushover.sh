#!/bin/zsh

INPUT="$(cat)"
EVENT="${1:-}"

# Ignore malformed/empty hook input.
if ! jq -e . >/dev/null 2>&1 <<< "$INPUT"; then
    exit 0
fi

# Never notify about hooks firing inside subagents.
# Claude Code adds agent_id only when the hook is executing
# in a subagent context.
if jq -e '.agent_id? != null' >/dev/null 2>&1 <<< "$INPUT"; then
    exit 0
fi

# Determine project name from the hook's actual working directory.
CWD="$(jq -r '.cwd // empty' <<< "$INPUT")"

if [[ -n "$CWD" ]]; then
    PROJECT="${CWD:t}"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    PROJECT="${CLAUDE_PROJECT_DIR:t}"
else
    PROJECT="Claude Code"
fi

# Read Pushover credentials from macOS Keychain.
ACCOUNT="$(id -un)"

USER_KEY="$(
    security find-generic-password \
        -a "$ACCOUNT" \
        -s "claude-pushover-user" \
        -w 2>/dev/null
)" || exit 0

APP_TOKEN="$(
    security find-generic-password \
        -a "$ACCOUNT" \
        -s "claude-pushover-token" \
        -w 2>/dev/null
)" || exit 0

case "$EVENT" in
    question)
        TITLE="Claude needs input"
        MESSAGE="Claude has a question."
        PRIORITY=1
        ;;

    permission)
        TOOL="$(jq -r '.tool_name // empty' <<< "$INPUT")"

        TITLE="Claude needs permission"

        if [[ -n "$TOOL" ]]; then
            MESSAGE="Permission required for: $TOOL"
        else
            MESSAGE="Claude is waiting for permission."
        fi

        PRIORITY=1
        ;;

    elicitation)
        SERVER="$(jq -r '.mcp_server_name // empty' <<< "$INPUT")"

        TITLE="Claude needs input"

        if [[ -n "$SERVER" ]]; then
            MESSAGE="MCP server '$SERVER' is waiting for your input."
        else
            MESSAGE="An MCP server is waiting for your input."
        fi

        PRIORITY=1
        ;;

    background_input)
        TITLE="Claude needs input"
        MESSAGE="A background Claude session is waiting for your input."
        PRIORITY=1
        ;;

    failure)
        ERROR="$(jq -r '.error // "unknown"' <<< "$INPUT")"

        TITLE="Claude stopped"
        MESSAGE="Claude stopped because of an API error: $ERROR"
        PRIORITY=1
        ;;

    done)
        # Stop can fire while background work or scheduled wakeups
        # are still active. In that case Claude may continue without us,
        # so don't notify.
        if jq -e '
            (((.background_tasks // []) | length) > 0)
            or
            (((.session_crons // []) | length) > 0)
        ' >/dev/null 2>&1 <<< "$INPUT"; then
            exit 0
        fi

        TITLE="Claude finished"
        MESSAGE="Claude has finished and is waiting for you."
        PRIORITY=0
        ;;

    *)
        exit 0
        ;;
esac

curl \
    --silent \
    --show-error \
    --fail \
    --connect-timeout 3 \
    --max-time 8 \
    -F "token=$APP_TOKEN" \
    -F "user=$USER_KEY" \
    -F "title=$TITLE · $PROJECT" \
    -F "message=$MESSAGE" \
    -F "priority=$PRIORITY" \
    "https://api.pushover.net/1/messages.json" \
    >/dev/null 2>&1

exit 0
