.section .text

.globl lgdt
.type lgdt, @function
lgdt:
    mov 4(%esp), %eax
    lgdt (%eax)
    ret

.globl far_jump
.type far_jump, @function
far_jump:
    mov $.far_jump_label, %eax
    push $0x08
    push %eax
    lret
.far_jump_label:
    ret

.globl load_data_segments
.type load_data_segments, @function
load_data_segments:
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss
    ret
