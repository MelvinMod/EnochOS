.section .multiboot
.align 4
.globl multiboot_header
multiboot_header:
    .long 0xE85250D6
    .long 0
    .long multiboot_header_end - multiboot_header
    .long 0x100000000 - (0xE85250D6 + 0 + (multiboot_header_end - multiboot_header))
    .short 0
    .short 0
    .long 8
multiboot_header_end:

.section .bss
.align 16
.globl kernel_stack
kernel_stack:
    .space 16384
.globl kernel_stack_top
kernel_stack_top:

.section .text
.globl boot_entry
.type boot_entry, @function
boot_entry:
    mov kernel_stack_top, %esp
    push %eax
    push %ebx
    call kmain
.hang:
    hlt
    jmp .hang

.globl outb
.type outb, @function
outb:
    movb 8(%esp), %al
    movw 4(%esp), %dx
    outb %al, %dx
    ret

.globl inb
.type inb, @function
inb:
    movw 4(%esp), %dx
    inb %dx, %al
    ret

.globl disable_cursor
.type disable_cursor, @function
disable_cursor:
    movw $0x0500, %ax
    int $0x10
    ret
