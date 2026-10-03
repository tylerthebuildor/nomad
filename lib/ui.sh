# shellcheck shell=bash disable=SC2034 # sourced; its variables are used by the sourcing scripts
# Nomad terminal UI kit, sourced by bin/t and bin/auth (and auth/ services).
# Phone first: everything here fits ~50 columns (Termux on a phone is ~52).

# Palette (256-color): a warm "desert sun" accent, everything else quiet.
e=$'\e'
R="${e}[0m" B="${e}[1m" DIM="${e}[38;5;244m" FAINT="${e}[38;5;240m"
ACC="${e}[38;5;208m" SUN1="${e}[38;5;214m" SUN2="${e}[38;5;208m" SUN3="${e}[38;5;202m"
LIVE="${e}[38;5;114m" IDLE="${e}[38;5;179m" DIR="${e}[38;5;110m" NAME="${e}[38;5;255m"
BAD="${e}[38;5;203m"

# fzf colors matching the palette.
FZF_COLORS='fg:252,bg+:236,fg+:255,hl:208,hl+:214,pointer:208,prompt:208,query:255,header:-1,gutter:-1,border:240'

# Terminal width, read from the tty since callers' stdout is often a pipe.
cols() { local c; c="$(stty size 2>/dev/null </dev/tty | cut -d' ' -f2)"; echo "${c:-80}"; }

# Cut to n columns with an ellipsis, then pad to n.
fit() { local s="$1" n="$2"; [ "${#s}" -gt "$n" ] && s="${s:0:n-1}…"; printf '%-*s' "$n" "$s"; }

# Block-letter "nomad" in a sunset gradient, with two short info lines beside it.
nomad_header() {
  printf '%s\n' \
    "${SUN1}┏┓╻┏━┓┏┳┓┏━┓┳━┓${R}" \
    "${SUN2}┃┗┫┃ ┃┃┃┃┣━┫┃ ┃${R}   ${DIM}${1:-}${R}" \
    "${SUN3}╹ ╹┗━┛╹ ╹╹ ╹┻━┛${R}   ${DIM}${2:-}${R}"
}
