ZIG = zig build-obj
AS = nasm
LD = x86_64-elf-ld

ZIGFLAGS = -target x86-freestanding -OReleaseSafe 
LDFLAGS = -m elf_i386 -T linker.ld

BUILD_DIR = build/obj
KERNEL_DIR = kernel
BOOT_ASM = boot/boot.asm
ISO_DIR = iso
ISO_BOOT = $(ISO_DIR)/boot
ISO_GRUB = $(ISO_BOOT)/grub
GRUB_CFG = grub.cfg

KERNEL_ZIG_SRCS := $(shell find $(KERNEL_DIR) -name '*.zig')
KERNEL_ASM_SRCS := $(shell find $(KERNEL_DIR) -name '*.asm')
KERNEL_ZIG_OBJS := $(patsubst $(KERNEL_DIR)/%.zig,$(BUILD_DIR)/%.o,$(KERNEL_ZIG_SRCS))
KERNEL_ASM_OBJS := $(patsubst $(KERNEL_DIR)/%.asm,$(BUILD_DIR)/%.o,$(KERNEL_ASM_SRCS))
BOOT_OBJ = $(BUILD_DIR)/boot.o

all: avery.iso

$(BUILD_DIR)/%.o: $(KERNEL_DIR)/%.zig
	@mkdir -p $(dir $@)
	$(ZIG) $(ZIGFLAGS) $< -femit-bin=$@

$(BUILD_DIR)/%.o: $(KERNEL_DIR)/%.asm
	@mkdir -p $(dir $@)
	$(AS) -f elf32 $< -o $@

$(BOOT_OBJ): $(BOOT_ASM)
	@mkdir -p $(dir $@)
	$(AS) -f elf32 $< -o $@

$(BUILD_DIR)/avery.bin: $(KERNEL_ZIG_OBJS) $(KERNEL_ASM_OBJS) $(BOOT_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo "Kernel binary created at $@"

avery.iso: $(BUILD_DIR)/avery.bin
	@mkdir -p $(ISO_GRUB)
	cp $(GRUB_CFG) $(ISO_GRUB)
	cp $(BUILD_DIR)/avery.bin $(ISO_BOOT)
	cp grub.cfg $(ISO_GRUB)
	grub-mkrescue -o avery.iso $(ISO_DIR)
	@echo "ISO image created at avery.iso"

clean:
	rm -rf $(BUILD_DIR)/* avery.iso $(ISO_DIR)

.PHONY: all clean run stdio terminal

run: avery.iso
	qemu-system-x86_64 -cdrom avery.iso -m 128M -boot d -serial stdio 

nographic:
	qemu-system-x86_64 -cdrom avery.iso -m 128M -boot d -nographic
	@echo "Running in non-graphical mode"

stdio: avery.iso
	qemu-system-x86_64 -cdrom avery.iso -m 128M -boot d -monitor stdio
	@echo "Running with stdio"

terminal: avery.iso
	qemu-system-x86_64 -cdrom avery.iso -m 128M -boot d -terminal stdio
	@echo "Running with terminal"

