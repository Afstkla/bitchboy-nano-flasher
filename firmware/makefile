# ===================================================================================
# BitchBoy Nano - CH551 / CH552 / CH554
# ===================================================================================
# Normally driven through ../flasher.py; 'make bin' is the only target you need.
# ===================================================================================

TARGET     = keypad
SKETCH     = keypad.c
DIRS       = . src

FREQ_SYS   = 16000000
XRAM_LOC   = 0x0100
XRAM_SIZE  = 0x0300
CODE_SIZE  = 0x3800

CC         = sdcc
OBJCOPY    = sdobjcopy
PACK_HEX   = packihx

CFLAGS  = -mmcs51 --model-small --no-xinit-opt
CFLAGS += --xram-size $(XRAM_SIZE) --xram-loc $(XRAM_LOC) --code-size $(CODE_SIZE)
CFLAGS += $(addprefix -I,$(DIRS)) -DF_CPU=$(FREQ_SYS)

CFILES  = $(SKETCH) $(wildcard src/*.c)
RFILES  = $(CFILES:.c=.rel)
CLEAN   = rm -f *.ihx *.lk *.map *.mem *.lst *.rel *.rst *.sym *.asm *.adb

%.rel : %.c
	@echo "Compiling $< ..."
	@$(CC) -c $(CFLAGS) $<

$(TARGET).ihx: $(RFILES)
	@echo "Linking $(TARGET).ihx ..."
	@$(CC) $(notdir $(RFILES)) $(CFLAGS) -o $(TARGET).ihx

$(TARGET).bin: $(TARGET).ihx
	@$(OBJCOPY) -I ihex -O binary $(TARGET).ihx $(TARGET).bin
	@echo "Built $(TARGET).bin - FLASH: $(shell awk '$$1 == "ROM/EPROM/FLASH" {print $$4}' $(TARGET).mem) bytes"

bin: $(TARGET).bin removetemp

removetemp:
	@$(CLEAN)

clean:
	@$(CLEAN)
	@rm -f $(TARGET).bin
