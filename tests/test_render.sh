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
