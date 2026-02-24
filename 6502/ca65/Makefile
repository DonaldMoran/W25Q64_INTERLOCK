# Makefile for RAM Shell and Transient Commands

# Tools
AS = ca65
LD = ld65
RM = rm -f
CC = gcc

# Flags
ASFLAGS = -I . --cpu 65c02
LDFLAGS_SHELL = -C common/ram.cfg

# Directories
SHELL_DIR = shell
COMMON_DIR = common
BIN_DIR = bin
OBJ_DIR = obj

# Host Tools
BINTOMON_SRC = ../../tools/utilities/bintomon/bintomon.c
BINTOMON = $(BIN_DIR)/bintomon

# Targets
SHELL_BIN = $(BIN_DIR)/cmd_shell.bin
SHELL_MON = $(BIN_DIR)/cmd_shell.mon
COMMON_OBJ = $(COMMON_DIR)/pico_lib.o

.PHONY: all clean commands

all: $(SHELL_BIN) $(SHELL_MON) commands

# Build Shell
$(SHELL_BIN): $(OBJ_DIR)/cmd_shell.o $(COMMON_OBJ) common/ram.cfg
	@mkdir -p $(BIN_DIR)
	$(LD) $(LDFLAGS_SHELL) -o $@ $(OBJ_DIR)/cmd_shell.o $(COMMON_OBJ)

# Convert Shell to Woz Monitor format
$(SHELL_MON): $(SHELL_BIN) $(BINTOMON)
	@echo "MON $< -> $@"
	$(BINTOMON) -l 0x1000 -r - $< > $@

$(OBJ_DIR)/cmd_shell.o: $(SHELL_DIR)/cmd_shell.s
	@mkdir -p $(OBJ_DIR)
	$(AS) $(ASFLAGS) -o $@ $<

# Build Common Lib
$(COMMON_OBJ): $(COMMON_DIR)/pico_lib.s
	$(AS) $(ASFLAGS) -o $@ $<

# Build Host Tools
$(BINTOMON): $(BINTOMON_SRC)
	@mkdir -p $(dir $@)
	$(CC) -o $@ $<

# Build Transient Commands (recurse)
commands:
	$(MAKE) -C commands

clean:
	$(RM) -r $(BIN_DIR) $(OBJ_DIR)
	$(RM) $(COMMON_OBJ)
	$(MAKE) -C commands clean