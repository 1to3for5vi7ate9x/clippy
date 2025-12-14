# Clipboard History

A simple clipboard history tool for macOS written in pure Objective-C with only Apple's native frameworks. Zero external dependencies.

## Why?

macOS doesn't have built-in clipboard history. This tool lets you retrieve your last 50 copied items without installing third-party apps.

## Security

- **Zero external dependencies** - only Apple's AppKit and Foundation frameworks
- **No supply chain attack surface** - you can audit every line of code
- **Restrictive file permissions** - history file is chmod 600 (owner read/write only)
- **Local storage only** - nothing leaves your machine

## Building

```bash
make
```

## Usage

### Start the daemon

For testing (foreground):
```bash
./bin/clipd
```

For production (auto-start on login):
```bash
sudo make install          # Install binaries to /usr/local/bin
make install-service       # Install and start launchd service
```

### Use the CLI

```bash
# Show recent items
clip list        # Last 10 items
clip list 20     # Last 20 items

# Copy an item back to clipboard
clip get 1       # Most recent item
clip get 3       # 3rd most recent

# Search history
clip search api  # Find entries containing "api"

# Clear history
clip clear

# For scripting (raw output, no formatting)
clip raw 1
```

## Make Targets

```
make              Build clipd and clip
make clean        Remove build artifacts
make install      Install to /usr/local/bin (may need sudo)
make uninstall    Remove from /usr/local/bin

make run-daemon   Run daemon in foreground (for testing)
make status       Check if daemon is running

make install-service    Install and start launchd service
make uninstall-service  Stop and remove launchd service
make restart-service    Restart the launchd service
```

## Files

- `~/.clipboard_history` - JSON file storing your clipboard history
- `/tmp/clipd.log` - Daemon log output (when running as service)
- `/tmp/clipd.err` - Daemon error output

## Configuration

Edit these constants in `src/clipd.m`:

- `POLL_INTERVAL_MS` - How often to check clipboard (default: 500ms)
- `MAX_HISTORY_ITEMS` - Maximum items to store (default: 50)
- `MAX_ENTRY_LENGTH` - Truncate entries longer than this (default: 10000)
