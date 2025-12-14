# Clippy

A clipboard history tool for macOS written in pure Objective-C with only Apple's native frameworks. Zero external dependencies.

## Features

- **Text & Image Support** - Captures both text and images (screenshots, copied images)
- **Pin System** - Save important items permanently with optional labels
- **Auto-Cleanup** - Entries older than 30 days are automatically deleted
- **Runtime Config** - Customize via `~/.clippy.conf` without recompiling
- **Error Recovery** - Automatic backup/restore for corrupted data files
- **Zero Dependencies** - Only Apple's AppKit and Foundation frameworks

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

### Start the daemon

```bash
./bin/clipd              # Foreground (testing)

# Or install as service:
sudo make install        # Install to /usr/local/bin
make install-service     # Auto-start on login
```

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
make              Build clipd and clippy
make test         Run test suite
make clean        Remove build artifacts
make install      Install to /usr/local/bin
make uninstall    Remove from /usr/local/bin

make run-daemon   Run daemon in foreground
make status       Check daemon status

make install-service    Start on login
make uninstall-service  Remove from login
make restart-service    Restart daemon
```

## Project Structure

```
├── include/
│   └── clippy_common.h    # Shared code (config, JSON ops, image handling)
├── src/
│   ├── clipd.m            # Daemon - monitors clipboard
│   └── clippy.m           # CLI - user interface
├── tests/
│   └── test_clippy.m      # Test suite (14 tests)
├── Makefile
└── com.local.clipd.plist  # launchd config
```

## License

MIT
