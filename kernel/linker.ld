/* EnochOS Kernel Linker Script */
OUTPUT_FORMAT("elf32-i386")
ENTRY(boot_entry)

SECTIONS
{
    /* Start at 1MB to avoid real mode area */
    . = 1M;

    /* Multiboot header must be at the beginning */
    .multiboot ALIGN(4K) :
    {
        *(.multiboot)
    }

    /* Text section (read-only) */
    .text ALIGN(4K) :
    {
        *(.text)
        *(.text.*)
    }

    /* Read-only data */
    .rodata ALIGN(4K) :
    {
        *(.rodata)
        *(.rodata.*)
    }

    /* Initialized data */
    .data ALIGN(4K) :
    {
        *(.data)
        *(.data.*)
    }

    /* Uninitialized data (BSS) */
    .bss ALIGN(4K) :
    {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
    }

    /* Kernel end marker */
    __kernel_end = .;

    /* Stack - 16KB */
    .stack (NOLOAD) :
    {
        . = ALIGN(16);
        __stack_start = .;
        . += 16K;
        __stack_end = .;
    }
}
