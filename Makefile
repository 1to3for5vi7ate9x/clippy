# Clippy - Clipboard History Tool
# Pure Objective-C with Apple frameworks only - zero external dependencies

CC = clang
CFLAGS = -Wall -Wextra -O2 -fobjc-arc
INCLUDES = -Iinclude
FRAMEWORKS = -framework AppKit -framework Foundation
FRAMEWORKS_PICKER = -framework AppKit -framework Foundation -framework Carbon

# Directories
SRC_DIR = src
INC_DIR = include
BIN_DIR = bin
TEST_DIR = tests

# Targets
DAEMON = clipd
CLI = clippy
PICKER = clippy-picker

# Install location
PREFIX = /usr/local

.PHONY: all clean install uninstall run-daemon help test test-fuzzy

all: $(BIN_DIR)/$(DAEMON) $(BIN_DIR)/$(CLI) $(BIN_DIR)/$(PICKER)

$(BIN_DIR)/$(DAEMON): $(SRC_DIR)/clipd.m $(INC_DIR)/clippy_common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(FRAMEWORKS) -o $@ $(SRC_DIR)/clipd.m

$(BIN_DIR)/$(CLI): $(SRC_DIR)/clippy.m $(INC_DIR)/clippy_common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(FRAMEWORKS) -o $@ $(SRC_DIR)/clippy.m

$(BIN_DIR)/$(PICKER): $(SRC_DIR)/clippy_picker.m $(INC_DIR)/clippy_common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(FRAMEWORKS_PICKER) -o $@ $(SRC_DIR)/clippy_picker.m

$(BIN_DIR):
	mkdir -p $@

clean:
	rm -rf $(BIN_DIR)

# Run tests
test: $(BIN_DIR)/test_clippy $(BIN_DIR)/test_fuzzy
	./$(BIN_DIR)/test_clippy
	./$(BIN_DIR)/test_fuzzy

test-fuzzy: $(BIN_DIR)/test_fuzzy
	./$(BIN_DIR)/test_fuzzy

$(BIN_DIR)/test_clippy: $(TEST_DIR)/test_clippy.m $(INC_DIR)/clippy_common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(FRAMEWORKS) -o $@ $(TEST_DIR)/test_clippy.m

$(BIN_DIR)/test_fuzzy: $(TEST_DIR)/test_fuzzy_search.m | $(BIN_DIR)
	$(CC) $(CFLAGS) $(FRAMEWORKS) -o $@ $(TEST_DIR)/test_fuzzy_search.m

install: all
	@echo "Installing to $(PREFIX)/bin..."
	install -d $(PREFIX)/bin
	install -m 755 $(BIN_DIR)/$(DAEMON) $(PREFIX)/bin/
	install -m 755 $(BIN_DIR)/$(CLI) $(PREFIX)/bin/
	install -m 755 $(BIN_DIR)/$(PICKER) $(PREFIX)/bin/
	@echo "Done. You may need to run with sudo."

uninstall:
	rm -f $(PREFIX)/bin/$(DAEMON)
	rm -f $(PREFIX)/bin/$(CLI)
	rm -f $(PREFIX)/bin/$(PICKER)
	@echo "Uninstalled from $(PREFIX)/bin"

# Run daemon in foreground for testing
run-daemon: $(BIN_DIR)/$(DAEMON)
	./$(BIN_DIR)/$(DAEMON)

# Run picker in foreground for testing
run-picker: $(BIN_DIR)/$(PICKER)
	./$(BIN_DIR)/$(PICKER)

# Install launchd service for auto-start (daemon)
install-service:
	@echo "Installing clipd launchd service..."
	@mkdir -p ~/Library/LaunchAgents
	@sed 's|{{BIN_PATH}}|$(PREFIX)/bin/$(DAEMON)|g' com.local.clipd.plist > ~/Library/LaunchAgents/com.local.clipd.plist
	@launchctl load ~/Library/LaunchAgents/com.local.clipd.plist
	@echo "clipd service installed and started."

uninstall-service:
	@echo "Removing clipd launchd service..."
	-@launchctl unload ~/Library/LaunchAgents/com.local.clipd.plist 2>/dev/null
	@rm -f ~/Library/LaunchAgents/com.local.clipd.plist
	@echo "clipd service removed."

# Restart the daemon service
restart-service:
	-@launchctl unload ~/Library/LaunchAgents/com.local.clipd.plist 2>/dev/null
	@launchctl load ~/Library/LaunchAgents/com.local.clipd.plist
	@echo "clipd service restarted."

# Install picker launchd service for auto-start
install-picker-service:
	@echo "Installing clippy-picker launchd service..."
	@mkdir -p ~/Library/LaunchAgents
	@sed 's|{{BIN_PATH}}|$(PREFIX)/bin/$(PICKER)|g' com.local.clippy-picker.plist > ~/Library/LaunchAgents/com.local.clippy-picker.plist
	@launchctl load ~/Library/LaunchAgents/com.local.clippy-picker.plist
	@echo "clippy-picker service installed and started."
	@echo "NOTE: Grant Accessibility permission in System Settings for Cmd+Shift+V hotkey."

uninstall-picker-service:
	@echo "Removing clippy-picker launchd service..."
	-@launchctl unload ~/Library/LaunchAgents/com.local.clippy-picker.plist 2>/dev/null
	@rm -f ~/Library/LaunchAgents/com.local.clippy-picker.plist
	@echo "clippy-picker service removed."

restart-picker-service:
	-@launchctl unload ~/Library/LaunchAgents/com.local.clippy-picker.plist 2>/dev/null
	@launchctl load ~/Library/LaunchAgents/com.local.clippy-picker.plist
	@echo "clippy-picker service restarted."

# Install all services
install-all-services: install-service install-picker-service

uninstall-all-services: uninstall-service uninstall-picker-service

# Check status
status:
	@echo "=== Clippy Status ==="
	@if pgrep -x clipd > /dev/null; then \
		echo "clipd:         running (PID: $$(pgrep -x clipd))"; \
	else \
		echo "clipd:         not running"; \
	fi
	@if pgrep -x clippy-picker > /dev/null; then \
		echo "clippy-picker: running (PID: $$(pgrep -x clippy-picker))"; \
	else \
		echo "clippy-picker: not running"; \
	fi

help:
	@echo "Clippy - Clipboard History Tool"
	@echo ""
	@echo "Build:"
	@echo "  make              Build clipd, clippy, and clippy-picker"
	@echo "  make clean        Remove build artifacts"
	@echo "  make test         Run all tests"
	@echo "  make test-fuzzy   Run fuzzy search tests only"
	@echo ""
	@echo "Install:"
	@echo "  make install      Install to $(PREFIX)/bin (may need sudo)"
	@echo "  make uninstall    Remove from $(PREFIX)/bin"
	@echo ""
	@echo "Run (foreground):"
	@echo "  make run-daemon   Run clipd in foreground"
	@echo "  make run-picker   Run clippy-picker in foreground"
	@echo "  make status       Check if services are running"
	@echo ""
	@echo "Daemon Service (clipd):"
	@echo "  make install-service    Install and start clipd"
	@echo "  make uninstall-service  Stop and remove clipd"
	@echo "  make restart-service    Restart clipd"
	@echo ""
	@echo "Picker Service (Cmd+Shift+V hotkey):"
	@echo "  make install-picker-service    Install and start picker"
	@echo "  make uninstall-picker-service  Stop and remove picker"
	@echo "  make restart-picker-service    Restart picker"
	@echo ""
	@echo "All Services:"
	@echo "  make install-all-services      Install both services"
	@echo "  make uninstall-all-services    Remove both services"
