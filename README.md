# Drives

An Omarchy bar widget for managing drives — mount, unmount, and open removable storage from the panel.

## Features

- Lists all labeled/mounted drives (skips system partitions)
- Click unmounted drive → mount (with password prompt if needed)
- Click mounted drive → open in file manager
- Click ✕ button → unmount
- Live updates on plug/unplug
- Usage bars with percentages
- Configurable refresh interval

## Installation

```bash
# Download and install from latest release (immutable tarball)
wget https://github.com/arsinghin/drives/releases/latest/download/drives.tar.gz
tar -xzf drives.tar.gz -C ~/.config/omarchy/plugins/
omarchy restart shell
```

Or pin a specific version:
```bash
wget https://github.com/arsinghin/drives/releases/download/v1.0.1/drives.tar.gz
tar -xzf drives.tar.gz -C ~/.config/omarchy/plugins/
omarchy restart shell
```

## Removal

```bash
rm -rf ~/.config/omarchy/plugins/drives
omarchy restart shell
```

## Screenshot

![Drives plugin](screenshot.png)

## Author

Alok Ranjan Singh