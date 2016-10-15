ROOTDIR = /c/devkitPro/devkitARM

LDSCRIPTSDIR = $(ROOTDIR)/$(TARGET)/lib

# gba_cart.ld and gba_crt0.s refer to the ones from devkitPro

TARGET = arm-none-eabi
LIBPATH = -L$(ROOTDIR)/$(TARGET)/lib -L$(ROOTDIR)/../libgba/lib
INCPATH = -I. -I$(ROOTDIR)/$(TARGET)/include -I$(ROOTDIR)/../libgba/include

CCFLAGS = -std=c99 -O2 -nostartfiles -mlittle-endian -mthumb -mthumb-interwork -mtune=arm7tdmi -mcpu=arm7tdmi -Wall -c -fomit-frame-pointer
HWFLAGS = -m2 -mb -O1 -std=c99 -Wall -c -fomit-frame-pointer
LDFLAGS = -T gba_cart.ld -mthumb -mthumb-interwork -Wl,-Map=output.map -nostdlib -nostartfiles
ASFLAGS = -mcpu=arm7tdmi -EL --defsym LINEAR_CROSSFADE=1

PREFIX = $(ROOTDIR)/bin/$(TARGET)-
CC = $(PREFIX)gcc
AS = $(PREFIX)as
LD = $(PREFIX)ld
OBJC = $(PREFIX)objcopy

DD = dd
RM = rm -f

OUTPUT = sidthekid
LIBS = $(LIBPATH) -lgba -lc -lgcc -lnosys
OBJS = \
    gba_crt0.o \
    main.o \
    arm_6510.o \
    arm_sidmapper.o \
    arm_mos6581.o \
    sidmapper.o \
    sidplayer.o \
    songs/songs.o \
    gfx.o


all: $(OUTPUT).gba

$(OUTPUT).gba: $(OUTPUT).elf
	$(OBJC) -O binary $< $(OUTPUT).gba
	$(ROOTDIR)/bin/gbafix $@

$(OUTPUT).elf: $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $(OUTPUT).elf

%.o: %.c
	$(CC) $(CCFLAGS) $(INCPATH) $< -o $@

%.o: %.s
	$(AS) $(ASFLAGS) $(INCPATH) $< -o $@

clean:
	$(RM) music/*.o *.o *.bin *.gba *.elf output.map
