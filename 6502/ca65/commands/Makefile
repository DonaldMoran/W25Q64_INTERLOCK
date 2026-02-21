# Makefile for W25Q64_INTERLOCK transient commands

# Tools
AS = ca65
LD = ld65
RM = rm -f
CC = gcc

# Common flags and configuration
ASFLAGS = -I ..
LDFLAGS = -C transient.cfg -o

# Directories
OBJ_DIR = obj
BIN_DIR = bin

# Host Tools
BINTOMON_SRC = ../../../tools/utilities/bintomon/bintomon.c
BINTOMON = $(BIN_DIR)/bintomon

# --- Auto-discovery of commands ---
COMMANDS := $(patsubst %/,%,$(filter-out $(OBJ_DIR)/ $(BIN_DIR)/, $(wildcard */)))

# Generate the list of target binary files
BINS := $(patsubst %,$(BIN_DIR)/%.bin,$(COMMANDS))
MONS := $(patsubst %,$(BIN_DIR)/%.mon,$(COMMANDS))

# --- Add aliases here ---
#BINS += $(BIN_DIR)/cp.bin
#MONS += $(BIN_DIR)/cp.mon

.PHONY: all clean

all: $(BINS) $(MONS)
	@echo "All transient commands (bin & mon) built successfully."

# --- Build Rules ---

# Link object file to binary
$(BIN_DIR)/%.bin: $(OBJ_DIR)/%.o transient.cfg
	@echo "LD $< -> $@"
	@mkdir -p $(@D)
	$(LD) $(LDFLAGS) $@ $<

# Convert binary to Woz Monitor format
$(BIN_DIR)/%.mon: $(BIN_DIR)/%.bin $(BINTOMON)
	@echo "MON $< -> $@"
	$(BINTOMON) -l 0x07FE -r - $< > $@

$(BINTOMON): $(BINTOMON_SRC)
	@mkdir -p $(@D)
	$(CC) -o $@ $<

# --- Alias Rules ---
$(BIN_DIR)/cp.bin: $(BIN_DIR)/copy.bin
	@echo "ALIAS (cp) $< -> $@"
	@cp $< $@

# --- Assemble source files to object files ---
define build_object_rule
$(OBJ_DIR)/$(1).o: $(1)/$(1).s
	@echo "AS $$< -> $$@"
	@mkdir -p $$(@D)
	$$(AS) $$(ASFLAGS) -o $$@ $$<
endef

$(foreach cmd,$(COMMANDS),$(eval $(call build_object_rule,$(cmd))))

clean:
	@echo "Cleaning build artifacts..."
	$(RM) -r $(OBJ_DIR) $(BIN_DIR)
