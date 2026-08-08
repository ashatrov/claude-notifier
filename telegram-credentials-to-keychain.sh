#!/bin/zsh

ACCOUNT="$(id -un)"

read -r "BOT_TOKEN?Telegram bot token: "

security add-generic-password \
    -U \
    -a "$ACCOUNT" \
    -s "claude-telegram-bot-token" \
    -w "$BOT_TOKEN"

echo "Send /start to your Telegram bot, then press Enter."
read

CHAT_ID="$(
    curl -fsS "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" \
        | jq -r '.result[-1].message.chat.id // empty'
)"

if [[ -z "$CHAT_ID" ]]; then
    echo "Could not get chat ID."
    exit 1
fi

security add-generic-password \
    -U \
    -a "$ACCOUNT" \
    -s "claude-telegram-chat-id" \
    -w "$CHAT_ID"

echo "Telegram credentials saved in keychain in 'laude-telegram-bot-token' and 'claude-telegram-chat-id' keys."
echo "Chat ID: $CHAT_ID"
