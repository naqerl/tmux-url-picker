#!/usr/bin/env bash
# Exercise tmux-url-picker against a private tmux server.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sock="tmux-url-picker-test"
work="$(mktemp -d)"
cleanup() {
  tmux -L "$sock" kill-server 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

cat > "$work/tmux.conf" << 'EOF'
set -g set-clipboard on
set -g history-limit 1000
set -g default-terminal "tmux-256color"
set -g escape-time 0
set -g prefix C-b
set -g mouse off
EOF

tmux -L "$sock" kill-server 2>/dev/null || true
tmux -L "$sock" -f "$work/tmux.conf" new-session -d -s pick -x 40 -y 30
socket="$(tmux -L "$sock" display-message -p '#{socket_path}')"
pid="$(tmux -L "$sock" display-message -p '#{pid}')"
export TMUX="$socket,$pid,0"

fail=0
check() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok  %s\n' "$name"
  else
    printf 'FAIL %s\n--- got ---\n%s\n--- want ---\n%s\n' "$name" "$got" "$want" >&2
    fail=1
  fi
}

# Fixture is outside the pane command so the typed command is not a second copy.
{
  printf '%s\n' \
    'https://example.com/a.' \
    'wiki https://en.wikipedia.org/wiki/Foo_(bar) end' \
    'md (https://example.com/md) done' \
    'https://example.com/search?a=1&b=2#frag' \
    "quote https://example.com/it's next" \
    'https://example.com/dup' \
    'https://example.com/dup' \
    'http://[::1]:8080/health' \
    '<https://example.com/angle>' \
    'file:///tmp/note.txt' \
    'https://example.com/a,b, more' \
    'https://example.com/foo).' \
    'https://example.com/this/is/a/very/long/path/that/wraps/ok'
  printf '\033]8;;https://hidden.example/from-osc8\033\\click here\033]8;;\033\\\n'
} > "$work/fixture"

tmux send-keys -t pick:0.0 "cat '$work/fixture'" Enter
sleep 0.3
tmux clear-history -t pick:0.0

want="$(printf '%s\n' \
  'https://hidden.example/from-osc8' \
  'https://example.com/this/is/a/very/long/path/that/wraps/ok' \
  'https://example.com/foo' \
  'https://example.com/a,b' \
  'file:///tmp/note.txt' \
  'https://example.com/angle' \
  'http://[::1]:8080/health' \
  'https://example.com/dup' \
  "https://example.com/it's" \
  'https://example.com/search?a=1&b=2#frag' \
  'https://example.com/md' \
  'https://en.wikipedia.org/wiki/Foo_(bar)' \
  'https://example.com/a')"

got="$(TMUX_URL_PICKER_PRINT=1 "$root/bin/tmux-url-picker" '%0')"
check extract "$got" "$want"

# Empty pane: exit 0, no output, no crash.
tmux new-window -d -t pick -n empty
tmux send-keys -t pick:empty "printf 'nothing to see\n'" Enter
sleep 0.2
tmux clear-history -t pick:empty
empty_pane="$(tmux display-message -p -t pick:empty '#{pane_id}')"
set +e
empty_out="$(TMUX_URL_PICKER_PRINT=1 "$root/bin/tmux-url-picker" "$empty_pane" 2>"$work/empty.err")"
empty_rc=$?
set -e
check empty-rc "$empty_rc" "0"
check empty-out "$empty_out" ""

# A typed printf leaves the URL and a literal \n in the scrollback. That must
# collapse to the same URL as the printed line, and a single URL is copied.
tmux new-window -d -t pick -n one
tmux send-keys -t pick:one "printf 'only https://one.example/a.\n'" Enter
sleep 0.3
one_pane="$(tmux display-message -p -t pick:one '#{pane_id}')"
one_got="$(TMUX_URL_PICKER_PRINT=1 "$root/bin/tmux-url-picker" "$one_pane")"
check one-url "$one_got" "https://one.example/a"

# Client held open on a private pty so OSC 52 and the menu have a terminal.
# Key bytes are dropped in $work/keys; the holder writes them to the pty master.
# A second process cannot reliably write /proc/<pid>/fd of /dev/ptmx.
: > "$work/keys"
python3 - "$work/client.log" "$work/keys" << 'PY' &
import os, pty, select, struct, fcntl, termios, subprocess, sys
log_path, key_path = sys.argv[1], sys.argv[2]
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 36, 120, 0, 0))
env = os.environ.copy()
env.pop("TMUX", None)
env["TERM"] = "xterm-256color"
proc = subprocess.Popen(
    ["tmux", "-L", "tmux-url-picker-test", "attach", "-t", "pick"],
    stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True,
)
os.close(slave)
log = open(log_path, "wb")
while proc.poll() is None:
    r, _, _ = select.select([master], [], [], 0.1)
    if master in r:
        data = os.read(master, 65536)
        if not data:
            break
        log.write(data)
        log.flush()
    try:
        keys = open(key_path, "rb").read()
    except OSError:
        keys = b""
    if keys:
        os.write(master, keys)
        open(key_path, "wb").close()
log.close()
PY
holder=$!
sleep 0.6
client="$(tmux list-clients -F '#{client_name}' | head -n 1)"
if [[ -z "$client" ]]; then
  echo "FAIL no client attached" >&2
  exit 1
fi
printf 'ok  client %s\n' "$client"
send() { printf '%s' "$1" > "$work/keys"; }

"$root/bin/tmux-url-picker" "$one_pane" "$client"
sleep 0.2
check one-copy "$(tmux show-buffer)" "https://one.example/a"

# Copy a URL that contains # and &. The buffer must stay literal, and the
# client pty must receive OSC 52. This value is not one of the menu results,
# so a missed key cannot look like a pass.
: > "$work/client.log"
copy_url='https://clipboard.example/only#hash'
"$root/bin/tmux-url-open" --client "$client" -- "$copy_url"
sleep 0.4
check buffer "$(tmux show-buffer)" "$copy_url"
b64="$(printf '%s' "$copy_url" | base64 -w0)"
if grep -a -F -q "$b64" "$work/client.log"; then
  printf 'ok  osc52\n'
else
  echo "FAIL osc52 payload missing from client tty" >&2
  fail=1
fi

# Menu: key 1 copies the newest URL, key a copies the 11th.
# Newest is the hyperlink. 11th is https://example.com/md
: > "$work/client.log"
"$root/bin/tmux-url-picker" '%0' "$client"
sleep 0.3
send 1
sleep 0.4
check menu-1 "$(tmux show-buffer)" "https://hidden.example/from-osc8"

"$root/bin/tmux-url-picker" '%0' "$client"
sleep 0.3
send a
sleep 0.4
check menu-a "$(tmux show-buffer)" "https://example.com/md"

# Hash in the chosen URL must not be format-expanded by the menu command.
"$root/bin/tmux-url-picker" '%0' "$client"
sleep 0.3
# 10th item, most-recent order: key 0
send 0
sleep 0.4
check menu-hash "$(tmux show-buffer)" "https://example.com/search?a=1&b=2#frag"

# Apostrophe survives the menu round-trip. 9th item, key 9.
"$root/bin/tmux-url-picker" '%0' "$client"
sleep 0.3
send 9
sleep 0.4
check menu-quote "$(tmux show-buffer)" "https://example.com/it's"

kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true

if [[ "$fail" -ne 0 ]]; then
  echo "failed" >&2
  exit 1
fi
echo "all passed"
