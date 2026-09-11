# Drives

An Omarchy bar widget for managing drives — mount, unmount, and open removable storage from the panel.

## Features

- Lists all labeled/mounted drives (skips system partitions)
- Click unmounted drive → mount (with password prompt if needed)
- Click mounted drive → open in file manager
- Right-click or use ✕ button → unmount
- Live updates on plug/unplug
- Usage bars with percentages
- Configurable refresh interval

## Installation

```bash
# Clone to your Omarchy plugins directory
git clone https://github.com/arsinghin/drives.git ~/.config/omarchy/plugins/drives

# Restart the shell to load
omarchy restart shell
```

## Configuration

Right-click the bar icon → Settings, or edit `~/.config/omarchy/shell.json`:

```json
"drives": {
  "refreshSeconds": 5
}
```

## Screenshot

![Drives plugin](screenshot.png)

## Author

Alok Ranjan Singh
