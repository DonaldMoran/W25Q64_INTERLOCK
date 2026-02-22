# Makefile for W25Q64_INTERLOCK transient commands

# Tools
AS = ca65
LD = ld65
RM = rm -f
CC = gcc

# Common flags and configuration
ASFLAGS = -I .. -I ../common --cpu 65c02
LDFLAGS = -C transient.cfg

# Directories
OBJ_DIR = obj
BIN_DIR = bin

# Common objects that all transient commands need
COMMON_OBJ = ../common/pico_lib.o

# Host Tools
BINTOMON_SRC = $(realpath ../../../tools/utilities/bintomon/bintomon.c)
BINTOMON = $(BIN_DIR)/bintomon

# --- Auto-discovery of commands ---
# Filter out obj/, bin/, and any files (only keep directories)
COMMANDS := $(patsubst %/,%,$(filter-out obj bin GET, $(wildcard */)))

# Generate the list of target binary files
BINS := $(patsubst %,$(BIN_DIR)/%.bin,$(COMMANDS))
MONS := $(patsubst %,$(BIN_DIR)/%.mon,$(COMMANDS))

.PHONY: all clean

# Build common object first, then everything else
all: $(COMMON_OBJ) $(BINS) $(MONS)
	@echo "All transient commands (bin & mon) built successfully."

# Rule to build common object
$(COMMON_OBJ): ../common/pico_lib.s
	@echo "AS $< -> $@"
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

# --- Build Rules ---

# Link object file with common object to create binary
$(BIN_DIR)/%.bin: $(OBJ_DIR)/%.o $(COMMON_OBJ) transient.cfg
	@echo "LD $< $(COMMON_OBJ) -> $@"
	@mkdir -p $(@D)
	$(LD) $(LDFLAGS) -o $@ $< $(COMMON_OBJ)

# Convert binary to Woz Monitor format
$(BIN_DIR)/%.mon: $(BIN_DIR)/%.bin $(BINTOMON)
	@echo "MON $< -> $@"
	$(BINTOMON) -l 0x07FE -r - $< > $@

$(BINTOMON): $(BINTOMON_SRC)
	@mkdir -p $(dir $@)
	$(CC) -o $@ $<

# --- Alias Rules ---
$(BIN_DIR)/cp.bin: $(BIN_DIR)/copy.bin
	@echo "ALIAS (cp) $< -> $@"
	@cp $< $@

$(BIN_DIR)/GET.bin: $(BIN_DIR)/get.bin
	@echo "ALIAS (GET) $< -> $@"
	@cp $< $@

# --- Assemble source files to object files ---
define build_object_rule
$(OBJ_DIR)/$(1).o: $(1)/$(1).s transient.cfg
	@echo "AS $$< -> $$@"
	@mkdir -p $$(@D)
	$$(AS) $$(ASFLAGS) -o $$@ $$<
endef

$(foreach cmd,$(COMMANDS),$(eval $(call build_object_rule,$(cmd))))

# Also build GET alias object if needed (though it uses get.s)
$(OBJ_DIR)/GET.o: get/get.s transient.cfg
	@echo "AS $< -> $@ (GET alias)"
	@mkdir -p $(@D)
	$(AS) $(ASFLAGS) -o $@ $<
	@echo "WARNING: GET is an alias, use bin/get.bin instead"

clean:
	$(RM) $(BIN_DIR)/cp.bin $(BIN_DIR)/GET.bin
	$(RM) -r $(OBJ_DIR) $(BIN_DIR)
	$(RM) $(COMMON_OBJ)
	@echo "Cleaning build artifacts..."

# Help target
help:
	@echo "Available commands:"
	@echo "  make all              - Build all transient commands"
	@echo "  make bin/NAME.bin     - Build specific command (e.g., make bin/ping.bin)"
	@echo "  make clean            - Remove build artifacts"
	@echo ""
	@echo "Discovered commands: $(COMMANDS)"
	@echo ""
	@echo "Note: GET is an alias for get - use bin/get.bin"

# Debug target to show discovered commands
debug:
	@echo "COMMANDS: $(COMMANDS)"
	@echo "BINS: $(BINS)"
	@echo "MONS: $(MONS)"
