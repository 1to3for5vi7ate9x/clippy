# Clippy - Clipboard History Tool
# Pure Objective-C with Apple frameworks only - zero external dependencies

CC = clang
CFLAGS = -Wall -Wextra -O2 -fobjc-arc
INCLUDES = -Iinclude
FRAMEWORKS = -framework AppKit -framework Foundation

# Directories
SRC_DIR = src
INC_DIR = include
BIN_DIR = bin
TEST_DIR = tests

# Targets
DAEMON = clipd
CLI = clippy

# Install location
PREFIX = /usr/local

.PHONY: all clean install uninstall run-daemon help test

all: $(BIN_DIR)/$(DAEMON) $(BIN_DIR)/$(CLI)

$(BIN_DIR)/$(DAEMON): $(SRC_DIR)/clipd.m $(INC_DIR)/clippy_common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(FRAMEWORKS) -o $@ $(SRC_DIR)/clipd.m

$(BIN_DIR)/$(CLI): $(SRC_DIR)/clippy.m $(INC_DIR)/clippy_common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(FRAMEWORKS) -o $@ $(SRC_DIR)/clippy.m

$(BIN_DIR):
	mkdir -p $@

clean:
	rm -rf $(BIN_DIR)

# Run tests
test: $(BIN_DIR)/test_clippy
	./$(BIN_DIR)/test_clippy

$(BIN_DIR)/test_clippy: $(TEST_DIR)/test_clippy.m $(INC_DIR)/clippy_common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(FRAMEWORKS) -o $@ $(TEST_DIR)/test_clippy.m

install: all
	@echo "Installing to $(PREFIX)/bin..."
	install -d $(PREFIX)/bin
	install -m 755 $(BIN_DIR)/$(DAEMON) $(PREFIX)/bin/
	install -m 755 $(BIN_DIR)/$(CLI) $(PREFIX)/bin/
	@echo "Done. You may need to run with sudo."

uninstall:
	rm -f $(PREFIX)/bin/$(DAEMON)
	rm -f $(PREFIX)/bin/$(CLI)
	@echo "Uninstalled from $(PREFIX)/bin"

# Run daemon in foreground for testing
run-daemon: $(BIN_DIR)/$(DAEMON)
	./$(BIN_DIR)/$(DAEMON)

# Install launchd service for auto-start
install-service:
	@echo "Installing launchd service..."
	@mkdir -p ~/Library/LaunchAgents
	@sed 's|{{BIN_PATH}}|$(PREFIX)/bin/$(DAEMON)|g' com.local.clipd.plist > ~/Library/LaunchAgents/com.local.clipd.plist
	@launchctl load ~/Library/LaunchAgents/com.local.clipd.plist
	@echo "Service installed and started."

uninstall-service:
	@echo "Removing launchd service..."
	-@launchctl unload ~/Library/LaunchAgents/com.local.clipd.plist 2>/dev/null
	@rm -f ~/Library/LaunchAgents/com.local.clipd.plist
	@echo "Service removed."

# Restart the daemon service
restart-service:
	-@launchctl unload ~/Library/LaunchAgents/com.local.clipd.plist 2>/dev/null
	@launchctl load ~/Library/LaunchAgents/com.local.clipd.plist
	@echo "Service restarted."

# Check daemon status
status:
	@if pgrep -x clipd > /dev/null; then \
		echo "clipd is running (PID: $$(pgrep -x clipd))"; \
	else \
		echo "clipd is not running"; \
	fi

help:
	@echo "Clippy - Clipboard History Tool"
	@echo ""
	@echo "Build:"
	@echo "  make              Build clipd and clippy"
	@echo "  make clean        Remove build artifacts"
	@echo "  make test         Run tests"
	@echo ""
	@echo "Install:"
	@echo "  make install      Install to $(PREFIX)/bin (may need sudo)"
	@echo "  make uninstall    Remove from $(PREFIX)/bin"
	@echo ""
	@echo "Daemon:"
	@echo "  make run-daemon   Run daemon in foreground (for testing)"
	@echo "  make status       Check if daemon is running"
	@echo ""
	@echo "Service:"
	@echo "  make install-service    Install and start launchd service"
	@echo "  make uninstall-service  Stop and remove launchd service"
	@echo "  make restart-service    Restart the launchd service"
