# Pure rendering helpers for the sidebar. Tests source this file directly with
# fixture data, while the renderer feeds it one line per tmux window.

render_supports_color() {
	[ "${TERM:-}" != 'dumb' ] || return 1
	[ -z "${NO_COLOR:-}" ] || return 1
	[ -t 1 ] || return 1
}

render_reset() {
	render_supports_color || return 0
	printf '\033[0m'
}

render_inverse_start() {
	render_supports_color || return 0
	printf '\033[7m'
}

render_color_start() {
	color=$1
	render_supports_color || return 0

	case "$color" in
		'#'*)
			hex=${color#\#}
			case ${#hex} in
				6)
					r=$(printf '%s' "$hex" | cut -c1-2)
					g=$(printf '%s' "$hex" | cut -c3-4)
					b=$(printf '%s' "$hex" | cut -c5-6)
					printf '\033[38;2;%d;%d;%dm' "0x$r" "0x$g" "0x$b"
					;;
			esac
			;;
		black) tput setaf 0 2>/dev/null || true ;;
		red) tput setaf 1 2>/dev/null || true ;;
		green) tput setaf 2 2>/dev/null || true ;;
		yellow) tput setaf 3 2>/dev/null || true ;;
		blue) tput setaf 4 2>/dev/null || true ;;
		magenta) tput setaf 5 2>/dev/null || true ;;
		cyan) tput setaf 6 2>/dev/null || true ;;
		white|default) tput setaf 7 2>/dev/null || true ;;
		*)
			printf '%s' ''
			;;
	esac
}

render_repeat() {
	char=$1
	count=$2
	i=0
	while [ "$i" -lt "$count" ]; do
		printf '%s' "$char"
		i=$((i + 1))
	done
}

render_trim() {
	width=$1
	text=$2

	if [ "$width" -le 0 ]; then
		return 0
	fi

	printf '%s' "$text" | awk -v width="$width" '
		BEGIN { ORS = "" }
		{
			line = $0
			if (length(line) <= width) {
				print line
			} else if (width <= 1) {
				print substr(line, 1, width)
			} else {
				print substr(line, 1, width - 1) "…"
			}
		}
	'
}

render_named_branch() {
	branch=$1
	nerd=$2
	[ -n "$branch" ] || return 0
	if [ "$nerd" = 'on' ]; then
		printf '  %s' "$branch"
	else
		printf ' git:%s' "$branch"
	fi
}

render_state_glyph() {
	state=$1
	frame=$2
	nerd=$3
	case "$state" in
		running)
			if [ "$nerd" = 'on' ]; then
				set -- '⠋' '⠙' '⠹' '⠸'
				eval "printf '%s' \"\${$((frame % 4 + 1))}\""
			else
				printf '%s' '*'
			fi
			;;
		waiting)
			if [ "$nerd" = 'on' ]; then
				set -- '◐' '◓' '◑' '◒'
				eval "printf '%s' \"\${$((frame % 4 + 1))}\""
			else
				printf '%s' '?'
			fi
			;;
		done)
			if [ "$nerd" = 'on' ]; then
				printf '%s' '✓'
			else
				printf '%s' 'OK'
			fi
			;;
		*)
			printf '%s' ''
			;;
	esac
}

render_progress() {
	progress=$1
	label=$2
	nerd=$3

	[ -n "$progress" ] || return 0

	if [ "$nerd" = 'on' ]; then
		fill='█'
		empty='░'
	else
		fill='#'
		empty='-'
	fi

	filled=$(awk -v progress="$progress" 'BEGIN {
		if (progress < 0) progress = 0
		if (progress > 1) progress = 1
		printf "%d", int(progress * 10 + 0.5)
	}')
	empty_count=$((10 - filled))
	percent=$(awk -v progress="$progress" 'BEGIN {
		if (progress < 0) progress = 0
		if (progress > 1) progress = 1
		printf "%d", int(progress * 100 + 0.5)
	}')

	render_repeat "$fill" "$filled"
	render_repeat "$empty" "$empty_count"
	printf ' %s%%' "$percent"
	[ -n "$label" ] && printf ' %s' "$label"
}

render_unread() {
	unread=$1
	nerd=$2
	[ "$unread" = '1' ] || return 0

	if [ "$nerd" = 'on' ]; then
		dot='●'
	else
		dot='!'
	fi

	render_color_start red
	printf '%s' "$dot"
	render_reset
}

render_phase_pill() {
	text=$1
	icon=$2
	color=$3
	[ -n "$text" ] || return 0

	render_color_start "$color"
	if [ -n "$icon" ]; then
		printf '%s %s' "$icon" "$text"
	else
		printf '%s' "$text"
	fi
	render_reset
}

render_activity() {
	state=$1
	action=$2
	cwd=$3
	last_cmd=$4

	case "$state" in
		running|waiting)
			printf '%s' "$action"
			;;
		*)
			if [ -n "$cwd" ] && [ -n "$last_cmd" ]; then
				printf 'cwd=%s  $ %s' "$cwd" "$last_cmd"
			elif [ -n "$last_cmd" ]; then
				printf '$ %s' "$last_cmd"
			else
				printf '%s' "$cwd"
			fi
			;;
	esac
}

render_window_block() {
	width=$1
	frame=$2
	nerd=$3
	wait_color=$4
	session_name=$5
	window_id=$6
	window_name=$7
	window_active=$8
	state=$9
	action=${10}
	branch=${11}
	cwd=${12}
	last_cmd=${13}
	progress=${14}
	progress_label=${15}
	unread=${16}
	last_notification=${17}
	phase=${18}
	phase_icon=${19}
	phase_color=${20}

	title_text=$window_name
	title_text=$title_text$(render_named_branch "$branch" "$nerd")
	title_body=$(render_trim $((width - 3)) "$title_text")
	title_len=$(printf '%s' "$title_body" | awk 'BEGIN { ORS = "" } { print length($0) }')
	pad=$((width - title_len - 3))
	[ "$pad" -lt 0 ] && pad=0

	activity=$(render_activity "$state" "$action" "$cwd" "$last_cmd")
	glyph=$(render_state_glyph "$state" "$frame" "$nerd")
	if [ -n "$glyph" ] && [ -n "$activity" ]; then
		detail_text="$glyph $activity"
	elif [ -n "$glyph" ]; then
		detail_text=$glyph
	else
		detail_text=$activity
	fi
	detail_text=$(render_trim $((width - 2)) "$detail_text")

	pill=$(render_phase_pill "$phase" "$phase_icon" "$phase_color")
	progress_text=$(render_progress "$progress" "$progress_label" "$nerd")
	unread_text=$(render_unread "$unread" "$nerd")

	meta_text=''
	if [ -n "$pill" ]; then
		meta_text=$pill
	fi
	if [ -n "$progress_text" ]; then
		[ -n "$meta_text" ] && meta_text="$meta_text  "
		meta_text=$meta_text$progress_text
	fi
	if [ -n "$unread_text" ]; then
		[ -n "$meta_text" ] && meta_text="$meta_text  "
		meta_text=$meta_text$unread_text
	fi
	if [ -z "$meta_text" ] && [ -n "$last_notification" ]; then
		meta_text=$(render_trim $((width - 2)) "$last_notification")
	else
		meta_text=$(render_trim $((width - 2)) "$meta_text")
	fi

	# Title row: active window gets inverse highlight; waiting windows get colored border.
	if [ "$window_active" = '1' ]; then
		render_inverse_start
	elif [ "$state" = 'waiting' ]; then
		render_color_start "$wait_color"
	fi
	printf '┌─%s' "$title_body"
	render_repeat '─' "$pad"
	if [ "$window_active" = '1' ] || [ "$state" = 'waiting' ]; then
		render_reset
	fi
	printf '\n'

	# Detail row.
	if [ "$state" = 'waiting' ]; then
		render_color_start "$wait_color"
	fi
	printf '│ %s\n' "$detail_text"
	if [ "$state" = 'waiting' ]; then
		render_reset
	fi

	# Meta row.
	if [ "$state" = 'waiting' ]; then
		render_color_start "$wait_color"
	fi
	printf '│ %s\n' "$meta_text"
	if [ "$state" = 'waiting' ]; then
		render_reset
	fi

	# Bottom border.
	if [ "$state" = 'waiting' ]; then
		render_color_start "$wait_color"
	fi
	printf '└'
	render_repeat '─' $((width - 1))
	if [ "$state" = 'waiting' ]; then
		render_reset
	fi
	printf '\n'
}

render_rows() {
	width=$1
	frame=$2
	nerd=$3
	wait_color=$4

	while IFS='|' read -r session_name window_id window_name window_active state action branch cwd last_cmd progress progress_label unread last_notification phase phase_icon phase_color; do
		[ -n "$window_id" ] || continue
		render_window_block "$width" "$frame" "$nerd" "$wait_color" \
			"$session_name" "$window_id" "$window_name" "$window_active" \
			"$state" "$action" "$branch" "$cwd" "$last_cmd" \
			"$progress" "$progress_label" "$unread" "$last_notification" \
			"$phase" "$phase_icon" "$phase_color"
	done
}
