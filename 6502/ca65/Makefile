# Makefile for 6502 Smart Peripheral Shell

AS = ca65
LD = ld65
LDFLAGS_SHELL = -C common/ram.cfg
ASFLAGS = -I . -g

# Shell targets
SHELL_TARGET = shell/cmd_shell.bin
SHELL_WOZTARGET = shell/cmd_shell.mon
SHELL_SOURCES = shell/cmd_shell.s common/pico_lib.s
SHELL_OBJECTS = $(SHELL_SOURCES:.s=.o)

all: $(SHELL_TARGET) $(SHELL_WOZTARGET)

# Shell rules
$(SHELL_TARGET): $(SHELL_OBJECTS)
	$(LD) $(LDFLAGS_SHELL) -o $@ $^

$(SHELL_WOZTARGET): $(SHELL_TARGET)
	python3 -c 'import sys; data=sys.stdin.buffer.read(); start=0x1000; [print(f"{start+i:04X}: " + " ".join(f"{b:02X}" for b in data[i:i+8])) for i in range(0, len(data), 8)]' < $< > $@
	echo "1000R" >> $@

# Generic rules
%.o: %.s
	$(AS) $(ASFLAGS) -l $(@:.o=.lst) -o $@ $<

# Manual Dependencies
shell/cmd_shell.o: common/pico_def.inc
common/pico_lib.o: common/pico_def.inc

clean:
	rm -f $(SHELL_OBJECTS) $(SHELL_TARGET) $(SHELL_WOZTARGET)
	rm -f shell/*.lst common/*.lst *.lst
