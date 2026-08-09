#!/bin/zsh
# claude-notifier: telegram

# The Test button in Claude Notifier Manager sets CLAUDE_NOTIFIER_TEST instead
# of raising `enabled`: that flag belongs to the running session, and borrowing
# it would race with a session starting or stopping mid-test and could leave
# notifications switched on for good. A test also has to send while muted.
if [[ "${CLAUDE_NOTIFIER_TEST:-}" != "1" ]]; then
    ENABLED="$(defaults read com.ashatrov.claude-notifier enabled 2>/dev/null || echo 0)"

    [[ "$ENABLED" == "1" ]] || exit 0
fi

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

        # A roster of every live session, so the notification answers "am I
        # free now?" rather than only "this one session stopped". An empty
        # ROSTER — no `claude` on the hook's PATH — sends the plain message.
        #
        # A table because running text, <pre> included, wraps once a row is
        # wider than the screen; a table scrolls sideways instead.
        SESSION_ID="$(jq -r '.session_id // empty' <<< "$INPUT")"

        ROSTER="$(
            claude agents --json 2>/dev/null \
            | jq -r --arg sid "$SESSION_ID" --arg home "$HOME" '
                def pad2: tostring | if length < 2 then "0" + . else . end;

                [
                    .[] |
                    ((now - (.startedAt / 1000)) / 60 | floor) as $m |
                    {
                        # This session is busy running the hook, so its own row
                        # would otherwise contradict the headline.
                        status: (if .sessionId == $sid then "✅"
                                 elif .status == "idle" then "💤"
                                 elif .status == "busy" then "🧠"
                                 elif .status == "waiting" then "⏳"
                                 else .status end),

                        age: "\(($m / 60 | floor) | pad2)h\(($m % 60) | pad2)m",
                        waiting: (.waitingFor // ""),
                        session: .name,

                        # The widest column, so it is worth the abbreviation.
                        # The $home == "" guard stops an unset $HOME from
                        # matching every absolute path.
                        directory: (.cwd |
                            if $home == "" then .
                            elif . == $home then "~"
                            elif startswith($home + "/") then "~" + ltrimstr($home)
                            else . end),
                    }
                ] as $rows |

                # A column of empty cells would still claim width.
                ($rows | any(.waiting != "")) as $blocked |

                if ($rows | length) == 0 then
                    ""
                else
                    "<table>"
                    # The blank heading is deliberate: a word over the emoji
                    # widens the narrowest column and pushes the rest off-screen.
                    + "<tr><th></th>"
                    + "<th>Age</th>"
                    + (if $blocked then "<th>Waiting for</th>" else "" end)
                    + "<th>Session</th>"
                    + "<th>Directory</th>"
                    + "</tr>"
                    + ($rows | map(
                        "<tr>"
                        + "<td>\(.status)</td>"
                        + "<td>\(.age)</td>"
                        + (if $blocked then "<td>\(.waiting | @html)</td>" else "" end)
                        + "<td>\(.session | @html)</td>"
                        + "<td>\(.directory | @html)</td>"
                        + "</tr>"
                      ) | join(""))
                    + "</table>"
                end
            ' 2>/dev/null
        )"
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

HEADLINE="<b>$EMOJI $(html_escape "$PROJECT"): $(html_escape "$TITLE")</b>"

if [[ -n "${ROSTER:-}" ]]; then
    # The roster replaces MESSAGE rather than following it — it already says
    # everything that line would have. sendRichMessage takes a document rather
    # than form fields, hence the JSON body. ROSTER is markup, escaped by the
    # jq that built it.
    jq \
        --null-input \
        --arg chat_id "$CHAT_ID" \
        --arg html "$HEADLINE
$ROSTER" \
        '{
            chat_id: $chat_id,
            rich_message: { html: $html, skip_entity_detection: true }
        }' \
    | curl \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 3 \
        --max-time 8 \
        --request POST \
        --header "Content-Type: application/json" \
        --data-binary @- \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendRichMessage" \
        >/dev/null 2>&1
else
    curl \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 3 \
        --max-time 8 \
        --request POST \
        --data-urlencode "chat_id=$CHAT_ID" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "text=$HEADLINE
$(html_escape "$MESSAGE")" \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        >/dev/null 2>&1
fi

exit 0
