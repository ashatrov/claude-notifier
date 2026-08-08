#!/bin/zsh

ACCOUNT="$(id -un)"

read -r "USER_KEY?Pushover user key: "

security add-generic-password \
    -U \
    -a "$ACCOUNT" \
    -s "claude-pushover-user" \
    -w "$USER_KEY"

read -r "APP_TOKEN?Pushover application API token: "

security add-generic-password \
    -U \
    -a "$ACCOUNT" \
    -s "claude-pushover-token" \
    -w "$APP_TOKEN"

echo "Pushover credentials saved in keychain in 'claude-pushover-user' and 'claude-pushover-token."
