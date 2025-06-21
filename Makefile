ZIG = zig build
AS = nasm
LD = x86_64-elf-ld
OBJCOPY = x86_64-elf-objcopy
OUTDIR=$(shell pwd)

ZIGFLAGS = -target x86-freestanding-none -OReleaseSafe -fno-stack-check 
LDFLAGS = -m elf_i386 -T linker.ld -nostdlib

BUILD_DIR = build/obj
KERNEL_DIR = kernel
BOOT_ASM = boot/boot.asm
ISO_DIR = $(OUTDIR)/iso
ISO_BOOT = $(ISO_DIR)/boot
ISO_GRUB = $(ISO_BOOT)/grub
GRUB_CFG = grub.cfg
ZIG_DIR = zig-out/build/obj
BITFONTS = $(shell find $(KERNEL_DIR) -name '*.bitfnt') # Standard PSF fonts

KERNEL_ZIG_OBJ := \
	$(BUILD_DIR)/init.o \
	$(BUILD_DIR)/idt_symbols.o \
	$(BUILD_DIR)/isr_symbols.o \
	$(BUILD_DIR)/gdt_symbols.o \
	$(BUILD_DIR)/irq_symbols.o \
	$(BUILD_DIR)/memcopy.o \
	$(BUILD_DIR)/syscall_handler.o \

KERNEL_ASM_SRCS := $(shell find $(KERNEL_DIR) -name '*.asm')
KERNEL_ASM_OBJS := $(patsubst $(KERNEL_DIR)/%.asm,$(BUILD_DIR)/%.o,$(KERNEL_ASM_SRCS))
BOOT_OBJ = $(BUILD_DIR)/boot.o
FONTS_OBJ = $(BUILD_DIR)/fonts.o

all: $(OUTDIR)/avery.iso

$(ZIG_DIR)/%.o: 
	$(ZIG)

$(BUILD_DIR)/%.o: $(ZIG_DIR)/%.o 
	@mkdir -p $(dir $@)
	@cp $< $@

$(BUILD_DIR)/%.o: $(KERNEL_DIR)/%.asm
	@mkdir -p $(dir $@)
	$(AS) -f elf32 $< -o $@

$(BOOT_OBJ): $(BOOT_ASM)
	@mkdir -p $(dir $@)
	$(AS) -f elf32 $< -o $@

$(FONTS_OBJ): $(BITFONTS)
	@mkdir -p $(dir $@)
	$(OBJCOPY) -I binary -O elf32-i386 -B i386 $< $@

$(BUILD_DIR)/avery.bin: $(KERNEL_ZIG_OBJ) $(KERNEL_ASM_OBJS) $(BOOT_OBJ) $(FONTS_OBJ)
	$(ZIG)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo "Kernel binary created at $@"

$(OUTDIR)/avery.iso: $(BUILD_DIR)/avery.bin
	@mkdir -p $(ISO_GRUB)
	cp $(GRUB_CFG) $(ISO_GRUB)
	cp $(BUILD_DIR)/avery.bin $(ISO_BOOT)
	cp grub.cfg $(ISO_GRUB)
	grub-mkrescue -o $(OUTDIR)/avery.iso $(ISO_DIR)
	@echo "ISO image created at avery.iso"

clean:
	rm -rf $(BUILD_DIR)/* avery.iso $(ISO_DIR) $(ZIG_DIR)

.PHONY: all clean run stdio terminal debug

run: $(OUTDIR)/avery.iso
	@clear
	@qemu-system-x86_64 -drive file=disk.img,format=raw -cdrom avery.iso -m 128M -boot d -serial stdio
	
debug: $(OUTDIR)/avery.iso
	@clear
	@qemu-system-x86_64 -drive file=disk.img,format=raw -cdrom avery.iso -m 128M -boot d -serial stdio -s -S

nographic:
	qemu-system-x86_64 -drive file=disk.img,format=raw -cdrom avery.iso -m 128M -boot d -nographic
	@echo "Running in non-graphical mode"

stdio: $(OUTDIR)/avery.iso
	qemu-system-x86_64 -drive file=disk.img,format=raw -cdrom avery.iso -m 128M -boot d -monitor stdio
	@echo "Running with stdio"

terminal: $(OUTDIR)/avery.iso
	qemu-system-x86_64 -cdrom avery.iso -drive file=disk.img,format=raw -m 128M -boot d -terminal stdio
	@echo "Running with terminal"
