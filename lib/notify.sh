# Notification helpers shared by the CLI notifier shim.

agentbar_notify_linux() {
    title=$1
    body=$2
    notify-send "$title" "$body"
}

agentbar_notify_darwin_terminal_notifier() {
    title=$1
    body=$2
    terminal-notifier -title "$title" -message "$body"
}

agentbar_notify_darwin_osascript() {
    title=$1
    body=$2
    osascript - "$title" "$body" <<'EOF'
on run argv
    set theTitle to item 1 of argv
    set theBody to item 2 of argv
    display notification theBody with title theTitle
end run
EOF
}

agentbar_notify_wsl() {
    title=$1
    body=$2
    wsl-notify-send.exe "$title" "$body"
}

agentbar_notify_powershell() {
    title=$1
    body=$2
    # shellcheck disable=SC2016
    AGENTBAR_NOTIFY_TITLE=$title AGENTBAR_NOTIFY_BODY=$body \
        powershell.exe -NoProfile -Command \
        '[string]$title=$env:AGENTBAR_NOTIFY_TITLE; [string]$body=$env:AGENTBAR_NOTIFY_BODY; if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) { New-BurntToastNotification -Text $title, $body | Out-Null }'
}

agentbar_notify_fallback() {
    title=$1
    body=$2
    message=$title
    [ -n "$body" ] && message="$title: $body"
    tmux display-message "$message" >/dev/null 2>&1 || true
    printf '\a' >/dev/tty 2>/dev/null || true
}

agentbar_notify_dispatch() {
    title=$1
    body=$2
    subtitle=$3
    platform=$(uname -s 2>/dev/null || printf '')
    release=$(uname -r 2>/dev/null || printf '')

    if [ -n "${AGENTBAR_NOTIFIER:-}" ]; then
        "$AGENTBAR_NOTIFIER" "$title" "$body" "$subtitle" >/dev/null 2>&1 || true
        return 0
    fi

    if [ "$platform" = 'Linux' ] && command -v notify-send >/dev/null 2>&1; then
        agentbar_notify_linux "$title" "$body" >/dev/null 2>&1 || true
        return 0
    fi

    if [ "$platform" = 'Darwin' ] && command -v terminal-notifier >/dev/null 2>&1; then
        agentbar_notify_darwin_terminal_notifier "$title" "$body" >/dev/null 2>&1 || true
        return 0
    fi

    if [ "$platform" = 'Darwin' ] && command -v osascript >/dev/null 2>&1; then
        agentbar_notify_darwin_osascript "$title" "$body" >/dev/null 2>&1 || true
        return 0
    fi

    case "$release" in
        *[Mm]icrosoft*)
            if command -v wsl-notify-send.exe >/dev/null 2>&1; then
                agentbar_notify_wsl "$title" "$body" >/dev/null 2>&1 || true
                return 0
            fi
            ;;
    esac

    if command -v powershell.exe >/dev/null 2>&1; then
        agentbar_notify_powershell "$title" "$body" >/dev/null 2>&1 || true
        return 0
    fi

    agentbar_notify_fallback "$title" "$body"
}
