# Safe-to-source zsh prompt publisher for tmux-orchestra.

if [ -z "${_ORCHESTRA_PROMPT_ZSH_LOADED:-}" ]; then
    _ORCHESTRA_PROMPT_ZSH_LOADED=1

    _orchestra_precmd() {
        local exit_code=$?
        [[ -n "${TMUX:-}" ]] || return "$exit_code"
        [[ -n "${TMUX_PANE:-}" ]] || return "$exit_code"

        local win branch
        win=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null) || return "$exit_code"
        branch=$(git -C "$PWD" symbolic-ref --short HEAD 2>/dev/null || printf '')

        tmux set-option -wq -t "$win" @ab_cwd "$PWD" \;\
            set-option -wq -t "$win" @ab_last_exit "$exit_code" \;\
            set-option -wq -t "$win" @ab_branch "$branch" \;\
            set-option -wq -t "$win" @ab_last_cmd "${_orchestra_last_cmd:-}" >/dev/null 2>&1 || true

        return "$exit_code"
    }

    _orchestra_preexec() {
        _orchestra_last_cmd=$1
    }

    case " ${precmd_functions[*]:-} " in
        *" _orchestra_precmd "*) ;;
        *) precmd_functions=(_orchestra_precmd ${precmd_functions[@]:-}) ;;
    esac

    case " ${preexec_functions[*]:-} " in
        *" _orchestra_preexec "*) ;;
        *) preexec_functions=(_orchestra_preexec ${preexec_functions[@]:-}) ;;
    esac
fi