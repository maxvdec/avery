OUTPUT_FORMAT(elf32-i386)

ENTRY(_start)

SECTIONS {
    . = 1M;  /* Load kernel at 1MB */

    .multiboot2 ALIGN(4K) : {
        *(.multiboot2)
    }

    .text ALIGN(4K) : {
        *(.text)
    }

    .rodata ALIGN(4K) : {
        *(.rodata)
    }

    .data ALIGN(4K) : {
        *(.data)
    }

    .bss ALIGN(4K) : {
        *(COMMON)
        *(.bss)
    }

    PROVIDE(kernel_end = .);
}
