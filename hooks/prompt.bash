# Safe-to-source bash prompt publisher for tmux-orchestra.

if [ -z "${_ORCHESTRA_PROMPT_BASH_LOADED:-}" ]; then
    _ORCHESTRA_PROMPT_BASH_LOADED=1

    _orchestra_publish() {
        local exit_code=$?
        [ -n "${TMUX:-}" ] || return "$exit_code"
        [ -n "${TMUX_PANE:-}" ] || return "$exit_code"

        local win branch
        win=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null) || return "$exit_code"
        branch=$(git -C "$PWD" symbolic-ref --short HEAD 2>/dev/null || printf '')

        tmux set-option -wq -t "$win" @ab_cwd "$PWD" \;\
            set-option -wq -t "$win" @ab_last_exit "$exit_code" \;\
            set-option -wq -t "$win" @ab_branch "$branch" \;\
            set-option -wq -t "$win" @ab_last_cmd "${_orchestra_last_cmd:-}" >/dev/null 2>&1 || true

        return "$exit_code"
    }

    _orchestra_capture_last_cmd() {
        _orchestra_last_cmd=$BASH_COMMAND
    }

    trap '_orchestra_capture_last_cmd' DEBUG

    case ";${PROMPT_COMMAND:-};" in
        *";_orchestra_publish;"*) ;;
        '')
            PROMPT_COMMAND=_orchestra_publish
            ;;
        *)
            PROMPT_COMMAND="_orchestra_publish;$PROMPT_COMMAND"
            ;;
    esac
fi