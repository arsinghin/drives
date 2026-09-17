# Drives

An Omarchy bar widget for managing drives — mount, unmount, and open removable storage from the panel.

## Features

- Lists all labeled/mounted drives (skips system partitions)
- Click any drive row:
  - Mounted → opens in the file manager
  - Unmounted → mounts (password prompt if needed) **and opens automatically** — no second click
- **Search-first popup**: opens with the typing pointer already in the search box; type to filter drives live by label, display name, device, or mountpoint (e.g. `f:` for `Local F:` / `F:`)
- **Keyboard navigation**: ↑/↓ to move through the list, Enter to open the highlighted drive (mounts first if needed), Esc to close
- **Top result always highlighted**: on popup open and as search results change; theme-aware accent colors for the selection
- ✕/＋ buttons to unmount/mount, right-click a mounted row to unmount
- Right-click the bar icon to rescan, middle-click to open the first mounted drive
- Live updates on plug/unplug
- Usage bars with percentages
- Configurable refresh interval (default 5s, set via `shell.json`)

## Installation

```bash
# Download and verify release tarball (immutable, integrity-checked)
wget https://github.com/arsinghin/drives/releases/download/v1.0.3/drives.tar.gz
echo "6dc471e2b6f62fc39557d46508ee3165dac1d7c8cb3a10604fe5faef1609e012  drives.tar.gz" | sha256sum -c - && tar -xzf drives.tar.gz -C ~/.config/omarchy/plugins/
omarchy restart shell
```

## Removal

```bash
rm -rf ~/.config/omarchy/plugins/drives
omarchy restart shell
```

## Screenshot

![Drives plugin](preview.png)

## Configuration

Optional: set refresh interval in `~/.config/omarchy/shell.json`:

```json
"drives": {
  "refreshSeconds": 5
}
```

## Author

Alok Ranjan Singh
