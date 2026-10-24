# tmux-url-picker

A small tmux helper that extracts URLs from the current pane.

- **One URL in pane**: notifies via the tmux status bar (no popup, no pane output) and copies it to the clipboard.
- **Multiple URLs**: opens an `fzf` picker in a popup.

## Files

- `bin/tmux-url-picker` — core script
- `bin/tmux-url-picker-launch` — decides notify vs picker

## Install

```bash
mkdir -p ~/.local/bin
cp bin/tmux-url-picker bin/tmux-url-picker-launch ~/.local/bin/
chmod +x ~/.local/bin/tmux-url-picker ~/.local/bin/tmux-url-picker-launch
```

Add to `~/.tmux.conf`:

```tmux
set -g set-clipboard on
bind-key -T prefix u run-shell -b "/home/user/.local/bin/tmux-url-picker-launch #{pane_id} >/dev/null 2>&1"
```

Reload:

```bash
tmux source-file ~/.tmux.conf
```
