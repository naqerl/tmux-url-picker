# tmux-url-picker

Copy a URL from the current tmux pane.

- **No URL**: a status-line message, and nothing is copied.
- **One URL**: copied to the tmux paste buffer and the terminal clipboard. No menu.
- **Several URLs**: a menu, most recent first. Enter or the shown key copies that URL. `q` or Escape closes the menu. `j` and `k` move.

Wrapped lines are joined. OSC 8 hyperlinks are included even when the visible text is not the URL. Trailing sentence punctuation and an unmatched closing bracket are left off the URL.

The clipboard write uses `set-buffer -w`, which sends OSC 52 through the tmux client. `set -g set-clipboard on` (or `external`) and a terminal that advertises `Ms` are required for the system clipboard. The paste buffer works either way (`prefix` + `]`).

## Files

- `bin/tmux-url-picker` — extract, then copy or open the menu
- `bin/tmux-url-picker-launch` — key-binding entry
- `bin/tmux-url-open` — copy one URL

## Install

```bash
mkdir -p ~/.local/bin
install -m 755 bin/tmux-url-picker bin/tmux-url-picker-launch bin/tmux-url-open ~/.local/bin/
```

Add to `~/.tmux.conf`:

```tmux
set -g set-clipboard on
bind-key -T prefix u run-shell -b "$HOME/.local/bin/tmux-url-picker-launch '#{pane_id}' '#{client_name}'"
```

Reload:

```bash
tmux source-file ~/.tmux.conf
```

Prefix + `u` runs it. The client name is passed in because the binding runs in the background and the menu and the clipboard both need that client.

## Test

`tests/test-picker.sh` starts its own tmux server (`-L tmux-url-picker-test`) and does not attach to any other server.
