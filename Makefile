
CC = x86_64-elf-gcc
CXX = x86_64-elf-g++
AS = nasm
LD = x86_64-elf-ld
CFLAGS = -m32 -ffreestanding -Wall -Wextra -Iinclude
CXXFLAGS = -m32 -ffreestanding -Wall -Wextra -Iinclude -fno-exceptions -fno-rtti
LDFLAGS = -m elf_i386 -T linker.ld

BUILD_DIR = build/obj
KERNEL_DIR = kernel
BOOT_DIR = boot
INCLUDE_DIR = include
ISO_DIR = iso
ISO_BOOT = $(ISO_DIR)/boot
ISO_GRUB = $(ISO_BOOT)/grub

KERNEL_C_SOURCES := $(shell find $(KERNEL_DIR) -name '*.c')
KERNEL_CPP_SOURCES := $(shell find $(KERNEL_DIR) -name '*.cpp')
KERNEL_ASM_SOURCES := $(shell find $(KERNEL_DIR) -name '*.asm')
KERNEL_C_OBJS := $(patsubst $(KERNEL_DIR)/%.c, $(BUILD_DIR)/%.o, $(KERNEL_C_SOURCES))
KERNEL_CPP_OBJS := $(patsubst $(KERNEL_DIR)/%.cpp, $(BUILD_DIR)/%.o, $(KERNEL_CPP_SOURCES))
KERNEL_ASM_OBJS := $(patsubst $(KERNEL_DIR)/%.asm, $(BUILD_DIR)/%.o, $(KERNEL_ASM_SOURCES))
BOOT_OBJ = $(BUILD_DIR)/boot.o 

all: avery.iso 

$(BUILD_DIR)/%.o: $(KERNEL_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(KERNEL_DIR)/%.cpp 
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(KERNEL_DIR)/%.asm
	@mkdir -p $(dir $@)
	$(AS) -f elf32 $< -o $@

$(BOOT_OBJ): $(BOOT_DIR)/boot.asm 
	@mkdir -p $(dir $@)
	$(AS) -f elf32 $< -o $@

$(BUILD_DIR)/kernel.bin: $(KERNEL_C_OBJS) $(KERNEL_CPP_OBJS) $(KERNEL_ASM_OBJS) $(BOOT_OBJ)
	$(LD) $(LDFLAGS) $^ -o $@

avery.iso: $(BUILD_DIR)/kernel.bin 
	@mkdir -p $(ISO_GRUB)
	cp grub.cfg $(ISO_GRUB)
	cp $(BUILD_DIR)/kernel.bin $(ISO_BOOT)
	grub-mkrescue -o avery.iso $(ISO_DIR)

clean:
	rm -rf $(BUILD_DIR) avery.iso $(ISO_DIR)

.PHONY: all clean run stdio terminal

run: avery.iso 
	qemu-system-x86_64 -cdrom avery.iso -m 128M -drive file=disk.img,format=raw -boot d

stdio: avery.iso
	qemu-system-x86_64 -cdrom avery.iso -m 128M -monitor stdio -drive file=disk.img,format=raw -boot d

terminal: avery.iso
	qemu-system-x86_64 -cdrom avery.iso -m 128M -drive file=disk.img,format=raw -boot d -nographic

