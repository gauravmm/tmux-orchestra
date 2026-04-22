# Shared helpers for tmux-orchestra. This file is sourced by executables, so it
# intentionally avoids `set -e` and only exposes reusable functions.

AB_EXIT_USAGE=1
AB_EXIT_NOTMUX=2
AB_EXIT_TMUX=3

ab_err() {
    printf '%s\n' "$*" >&2
}

ab_usage() {
    ab_err "$*"
    exit "$AB_EXIT_USAGE"
}

ab_notmux() {
    ab_err "$*"
    exit "$AB_EXIT_NOTMUX"
}

ab_tmux_fail() {
    ab_err "$*"
    exit "$AB_EXIT_TMUX"
}

ab_plugin_dir() {
    CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd
}

ab_option_max() {
    case "$1" in
        @ab_current_action) printf '%s' 120 ;;
        @ab_progress_label) printf '%s' 60 ;;
        @ab_last_notification) printf '%s' 120 ;;
        @ab_last_cmd) printf '%s' 80 ;;
        @ab_last_exit) printf '%s' 32 ;;
        @ab_status_*__icon) printf '%s' 1 ;;
        @ab_status_*__color) printf '%s' 32 ;;
        @ab_status_*) printf '%s' 40 ;;
        @ab_width) printf '%s' 8 ;;
        *) printf '%s' 0 ;;
    esac
}

ab_normalize_value() {
    printf '%s' "$1" | tr '\n' ' '
}

ab_truncate_value() {
    max=$1
    value=$2

    if [ "$max" -le 0 ]; then
        printf '%s' "$value"
        return 0
    fi

    printf '%s' "$value" | awk -v max="$max" '
        BEGIN { ORS = "" }
        {
            text = $0
            if (length(text) <= max) {
                print text
            } else if (max <= 1) {
                print substr(text, 1, max)
            } else {
                print substr(text, 1, max - 1) "…"
            }
        }
    '
}

set_opt() {
    target=$1
    option=$2
    value=$(ab_normalize_value "$3")
    max=$(ab_option_max "$option")
    value=$(ab_truncate_value "$max" "$value")
    tmux set-option -wq -t "$target" "$option" "$value" >/dev/null 2>&1
}

clear_opt() {
    target=$1
    option=$2
    tmux set-option -wqu -t "$target" "$option" >/dev/null 2>&1
}

get_opt() {
    target=$1
    option=$2
    tmux show-options -v -w -t "$target" "$option" 2>/dev/null || printf ''
}

set_session_opt() {
    target=$1
    option=$2
    value=$(ab_normalize_value "$3")
    max=$(ab_option_max "$option")
    value=$(ab_truncate_value "$max" "$value")
    tmux set-option -q -t "$target" "$option" "$value" >/dev/null 2>&1
}

clear_session_opt() {
    target=$1
    option=$2
    tmux set-option -qu -t "$target" "$option" >/dev/null 2>&1
}

get_session_opt() {
    target=$1
    option=$2
    tmux show-options -v -t "$target" "$option" 2>/dev/null || printf ''
}

resolve_window() {
    explicit_window=${1-}

    if [ -n "$explicit_window" ]; then
        printf '%s\n' "$explicit_window"
        return 0
    fi

    if [ -n "${TMUX_PANE:-}" ]; then
        tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null && return 0
    fi

    if [ -n "${ORCHESTRA_WINDOW_ID:-}" ]; then
        printf '%s\n' "$ORCHESTRA_WINDOW_ID"
        return 0
    fi

    tmux display-message -p '#{window_id}' 2>/dev/null && return 0
    ab_notmux 'not in tmux and no --window given.'
}

resolve_session() {
    window_id=$1
    tmux display-message -p -t "$window_id" '#{session_name}' 2>/dev/null || return 1
}

window_exists() {
    tmux display-message -p -t "$1" '#{window_id}' >/dev/null 2>&1
}

pane_exists() {
    tmux display-message -p -t "$1" '#{pane_id}' >/dev/null 2>&1
}

sanitize_status_key() {
    case "$1" in
        ''|*[!A-Za-z0-9_]*)
            ab_usage 'status key must contain only letters, numbers, and underscores'
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}
