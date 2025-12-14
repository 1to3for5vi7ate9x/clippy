# Clippy

A simple clipboard history tool for macOS written in pure Objective-C with only Apple's native frameworks. Zero external dependencies.

## Why?

macOS doesn't have built-in clipboard history. This tool lets you retrieve your last 50 copied items and **pin important ones permanently** - without installing third-party apps.

## Security

- **Zero external dependencies** - only Apple's AppKit and Foundation frameworks
- **No supply chain attack surface** - you can audit every line of code
- **Restrictive file permissions** - all data files are chmod 600 (owner read/write only)
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

### History Commands

```bash
# Show recent items
clippy list        # Last 10 items
clippy list 20     # Last 20 items

# Copy an item back to clipboard
clippy get 1       # Most recent item
clippy get 3       # 3rd most recent

# Search history
clippy search api  # Find entries containing "api"

# Clear history
clippy clear

# For scripting (raw output, no formatting)
clippy raw 1
```

### Pin Commands

Pins are stored separately from history (max 50 pins). Both history and pins are **auto-deleted after 30 days** for security.

```bash
# Pin an item from history
clippy pin 3              # Pin item 3
clippy pin 3 "API Key"    # Pin with a label

# List all pinned items
clippy pins

# Copy a pinned item to clipboard
clippy paste 1            # Copy pin #1

# Remove a pinned item
clippy unpin 1
```

**Example workflow:**
```bash
$ clippy list
Clipboard History (showing 3 of 3):

   1. [Today 14:30] some random text
   2. [Today 14:29] my-email@example.com
   3. [Today 14:28] sk-proj-abc123xyz...

Use 'clippy get <N>' to copy, 'clippy pin <N>' to save permanently.

$ clippy pin 3 "OpenAI Key"
Pinned as #1 [OpenAI Key]: sk-proj-abc123xyz...

$ clippy pins
Pinned Items (1):

   1. [Today 14:31] {OpenAI Key} sk-proj-abc123xyz...

Use 'clippy paste <N>' to copy a pinned item to clipboard.

$ clippy paste 1
Copied pin #1 [OpenAI Key] to clipboard: sk-proj-abc123xyz...
```

## Make Targets

```
make              Build clipd and clippy
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

| File | Description |
|------|-------------|
| `~/.clipboard_history` | Clipboard history (max 50 items, auto-rotates) |
| `~/.clipboard_pins` | Pinned items (max 50 pins) |
| `/tmp/clipd.log` | Daemon log output (when running as service) |
| `/tmp/clipd.err` | Daemon error output |

**Security:** All entries older than 30 days are automatically deleted (checked hourly).

## Configuration

Edit constants in source files:

**`src/clipd.m`** (daemon):
| Constant | Default | Description |
|----------|---------|-------------|
| `POLL_INTERVAL_MS` | 500 | How often to check clipboard (ms) |
| `MAX_HISTORY_ITEMS` | 50 | Maximum history items to store |
| `MAX_ENTRY_LENGTH` | 10000 | Truncate entries longer than this |
| `MAX_AGE_DAYS` | 30 | Auto-delete entries older than this |

**`src/clippy.m`** (CLI):
| Constant | Default | Description |
|----------|---------|-------------|
| `MAX_PINS` | 50 | Maximum pinned items allowed |

## License

MIT
