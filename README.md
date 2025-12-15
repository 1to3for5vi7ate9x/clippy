# Clippy

A clipboard history tool for macOS written in pure Objective-C with only Apple's native frameworks. Zero external dependencies.

## Features

- **Global Hotkey Picker** - Press `Cmd+Shift+V` from any app to fuzzy-search clipboard history
- **Text & Image Support** - Captures both text and images (screenshots, copied images)
- **Pin System** - Save important items permanently with optional labels
- **Auto-Cleanup** - Entries older than 30 days are automatically deleted
- **Runtime Config** - Customize via `~/.clippy.conf` without recompiling
- **Error Recovery** - Automatic backup/restore for corrupted data files
- **Zero Dependencies** - Only Apple's AppKit, Foundation, and Carbon frameworks

## Security

- **No supply chain attack surface** - you can audit every line of code
- **Restrictive file permissions** - all data files are chmod 600/700
- **Local storage only** - nothing leaves your machine
- **Auto-expiry** - old entries deleted after 30 days

## Building

```bash
make           # Build
make test      # Run tests
```

## Usage

### Quick Start

```bash
make                     # Build everything
sudo make install        # Install to /usr/local/bin
make install-all-services  # Start clipd + picker on login
```

### Start the daemon

```bash
./bin/clipd              # Foreground (testing)

# Or install as service:
sudo make install        # Install to /usr/local/bin
make install-service     # Auto-start on login
```

### Global Hotkey Picker (Cmd+Shift+V)

The picker provides a fuzzy-search popup that works from any application.

```bash
# Install and start the picker service
make install-picker-service

# Grant Accessibility permission when prompted
# (System Settings > Privacy & Security > Accessibility)
```

**Usage:**
- Press `Cmd+Shift+V` from any app to open the picker
- Type to fuzzy-search your clipboard history
- Use arrow keys to navigate, Enter to select
- Press Escape or click outside to dismiss
- Selected item is copied to clipboard

The picker also appears in your menu bar for manual access.

### History Commands

```bash
clippy list [N]      # Show last N items (default: 10)
clippy get <N>       # Copy item N to clipboard (text or image)
clippy search <Q>    # Search history
clippy clear         # Clear all history
clippy raw <N>       # Raw output (for scripting)
```

### Pin Commands

```bash
clippy pin <N> [label]   # Pin item from history
clippy pins              # List all pins
clippy paste <N>         # Copy pin to clipboard
clippy unpin <N>         # Remove pin
```

### Configuration

```bash
clippy config        # Show current configuration
```

## Configuration File

Create `~/.clippy.conf` to customize (no recompile needed):

```ini
# Clipboard polling interval (ms)
poll_interval_ms = 500

# Maximum items in history
max_history_items = 50

# Maximum pinned items
max_pins = 50

# Maximum text entry length (chars)
max_entry_length = 10000

# Auto-delete entries older than N days
max_age_days = 30

# Cleanup check interval (seconds)
cleanup_interval_sec = 3600
```

## Files

| Path | Description |
|------|-------------|
| `~/.clipboard_history` | History JSON (max 50 items) |
| `~/.clipboard_pins` | Pins JSON (max 50 items) |
| `~/.clippy.conf` | Configuration file (optional) |
| `~/.clippy_data/images/` | Stored images |
| `~/.clipboard_*.backup` | Automatic backups |

## Make Targets

```
Build:
  make              Build clipd, clippy, and clippy-picker
  make clean        Remove build artifacts
  make test         Run all tests
  make test-fuzzy   Run fuzzy search tests only

Install:
  make install      Install to /usr/local/bin (may need sudo)
  make uninstall    Remove from /usr/local/bin

Run (foreground):
  make run-daemon   Run clipd in foreground
  make run-picker   Run clippy-picker in foreground
  make status       Check if services are running

Daemon Service (clipd):
  make install-service    Install and start clipd
  make uninstall-service  Stop and remove clipd
  make restart-service    Restart clipd

Picker Service (Cmd+Shift+V hotkey):
  make install-picker-service    Install and start picker
  make uninstall-picker-service  Stop and remove picker
  make restart-picker-service    Restart picker

All Services:
  make install-all-services      Install both services
  make uninstall-all-services    Remove both services
```

## Project Structure

```
├── include/
│   └── clippy_common.h        # Shared code (config, JSON ops, image handling)
├── src/
│   ├── clipd.m                # Daemon - monitors clipboard
│   ├── clippy.m               # CLI - user interface
│   └── clippy_picker.m        # GUI picker - global hotkey + fuzzy search
├── tests/
│   ├── test_clippy.m          # Core test suite (14 tests)
│   └── test_fuzzy_search.m    # Fuzzy search tests (22 tests)
├── Makefile
├── com.local.clipd.plist      # launchd config for daemon
└── com.local.clippy-picker.plist  # launchd config for picker
```

## License

MIT
