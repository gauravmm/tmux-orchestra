#!/bin/sh
set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO_DIR/lib/render.sh"

compare_fixture() {
    input=$1
    expected=$2
    actual=$(NO_COLOR=1 TERM=xterm render_rows 40 0 off '#d29922' <"$input")
    expected_text=$(cat "$expected")
    if [ "$actual" != "$expected_text" ]; then
        printf 'render mismatch for %s\n--- expected ---\n%s\n--- actual ---\n%s\n' "$input" "$expected_text" "$actual" >&2
        exit 1
    fi
}

compare_fixture "$REPO_DIR/tests/fixtures/render-idle.input" "$REPO_DIR/tests/fixtures/render-idle.expected"
compare_fixture "$REPO_DIR/tests/fixtures/render-running.input" "$REPO_DIR/tests/fixtures/render-running.expected"
compare_fixture "$REPO_DIR/tests/fixtures/render-waiting.input" "$REPO_DIR/tests/fixtures/render-waiting.expected"

check_inactive_border_color() {
    tmp_output=$(mktemp "${TMPDIR:-/tmp}/orchestra-render.XXXXXX")
    trap 'rm -f "$tmp_output"' EXIT INT TERM

    render_supports_color() {
        return 0
    }

    TERM=xterm render_rows 40 0 off '#d29922' <"$REPO_DIR/tests/fixtures/render-running.input" >"$tmp_output"

    esc=$(printf '\033')
    first_line=$(sed -n '1p' "$tmp_output")
    second_line=$(sed -n '2p' "$tmp_output")

    case "$first_line" in
        "${esc}[38;2;192;192;192m┌─ ${esc}[0m"*)
            :
            ;;
        *)
            printf 'inactive top border is not light grey\nactual: %s\n' "$first_line" >&2
            exit 1
            ;;
    esac

    case "$second_line" in
        "${esc}[38;2;192;192;192m│ ${esc}[0m"*)
            :
            ;;
        *)
            printf 'inactive side border is not light grey\nactual: %s\n' "$second_line" >&2
            exit 1
            ;;
    esac

    rm -f "$tmp_output"
    trap - EXIT INT TERM
}
check_inactive_border_color

check_cwd_label() {
    cwd=$1; expected=$2
    actual=$(render_cwd_label "$cwd")
    [ "$actual" = "$expected" ] || {
        printf 'cwd label for %s: expected "%s" got "%s"\n' "$cwd" "$expected" "$actual" >&2
        exit 1
    }
}
check_cwd_label '/tmp/project' 'project'
check_cwd_label '/tmp/abcdefghijklmnopq' 'bcdefghijklmnopq'
check_cwd_label '/' '/'

check_spinner() {
    name=$1; frame=$2; expected=$3
    actual=$(render_state_glyph running "$frame" off "$name")
    [ "$actual" = "$expected" ] || {
        printf 'spinner %s frame %d: expected "%s" got "%s"\n' "$name" "$frame" "$expected" "$actual" >&2
        exit 1
    }
}
check_spinner claude 0 '·'
check_spinner claude 1 '✻'
check_spinner claude 3 '✶'
check_spinner claude 5 '✢'
check_spinner claude 6 '·'
check_spinner opencode 0 '⢎⡱'
check_spinner opencode 1 '⢞⡳'
check_spinner opencode 4 '⢾⡱'
check_spinner opencode 5 '⠰⠆'
check_spinner opencode 8 '⢎⡱'
