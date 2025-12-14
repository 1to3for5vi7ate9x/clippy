# Compiler settings
CC = gcc
CFLAGS = -Wall -Wextra -Wpedantic -std=c11
LDFLAGS =

# Directories
SRC_DIR = src
INC_DIR = include
BUILD_DIR = build
BIN_DIR = bin
TEST_DIR = tests

# Project name
TARGET = clipboard-history

# Source files
SRCS = $(wildcard $(SRC_DIR)/*.c)
OBJS = $(SRCS:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)

# Test files
TEST_SRCS = $(wildcard $(TEST_DIR)/*.c)
TEST_OBJS = $(filter-out $(BUILD_DIR)/main.o, $(OBJS))

# Default target
all: $(BIN_DIR)/$(TARGET)

$(BIN_DIR)/$(TARGET): $(OBJS) | $(BIN_DIR)
	$(CC) $(OBJS) -o $@ $(LDFLAGS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(INC_DIR) -c $< -o $@

# Test target
test: $(BIN_DIR)/test_$(TARGET)
	./$(BIN_DIR)/test_$(TARGET)

$(BIN_DIR)/test_$(TARGET): $(TEST_DIR)/test_main.c $(TEST_OBJS) | $(BIN_DIR)
	$(CC) $(CFLAGS) -I$(INC_DIR) $^ -o $@

# Directories
$(BUILD_DIR) $(BIN_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)

run: all
	./$(BIN_DIR)/$(TARGET)

.PHONY: all test clean run
