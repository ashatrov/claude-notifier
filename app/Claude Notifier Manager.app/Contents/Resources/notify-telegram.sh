#!/bin/zsh
# claude-notifier: telegram

ENABLED="$(defaults read com.ashatrov.claude-notifier enabled 2>/dev/null || echo 0)"

[[ "$ENABLED" == "1" ]] || exit 0

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

# Read Telegram credentials from macOS Keychain.
ACCOUNT="$(id -un)"

BOT_TOKEN="$(
    security find-generic-password \
        -a "$ACCOUNT" \
        -s "claude-telegram-bot-token" \
        -w 2>/dev/null
)" || exit 0

CHAT_ID="$(
    security find-generic-password \
        -a "$ACCOUNT" \
        -s "claude-telegram-chat-id" \
        -w 2>/dev/null
)" || exit 0

case "$EVENT" in
    question)
        EMOJI="❓"
        TITLE="Claude needs input"
        MESSAGE="Claude has a question."
        PRIORITY=1
        ;;

    permission)
        TOOL="$(jq -r '.tool_name // empty' <<< "$INPUT")"

        EMOJI="🔐"
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

        EMOJI="🧩"
        TITLE="Claude needs input"

        if [[ -n "$SERVER" ]]; then
            MESSAGE="MCP server '$SERVER' is waiting for your input."
        else
            MESSAGE="An MCP server is waiting for your input."
        fi

        PRIORITY=1
        ;;

    background_input)
        EMOJI="⏸️"
        TITLE="Claude needs input"
        MESSAGE="A background Claude session is waiting for your input."
        PRIORITY=1
        ;;

    failure)
        ERROR="$(jq -r '.error // "unknown"' <<< "$INPUT")"

        EMOJI="⚠️"
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

        EMOJI="✅"
        TITLE="Claude finished"
        MESSAGE="Claude has finished and is waiting for you."
        PRIORITY=0
        ;;

    *)
        exit 0
        ;;
esac

# The headline is sent as HTML so it renders bold, which means every
# interpolated value has to be escaped first.
html_escape() {
    local s=$1
    s=${s//'&'/'&amp;'}
    s=${s//'<'/'&lt;'}
    s=${s//'>'/'&gt;'}
    print -r -- "$s"
}

curl \
    --silent \
    --show-error \
    --fail \
    --connect-timeout 3 \
    --max-time 8 \
    --request POST \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=<b>$EMOJI $(html_escape "$PROJECT"): $(html_escape "$TITLE")</b>
$(html_escape "$MESSAGE")" \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    >/dev/null 2>&1

exit 0
