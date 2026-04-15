.section .text

.globl lidt
.type lidt, @function
lidt:
    lidt 4(%esp)
    ret

.globl sti
.type sti, @function
sti:
    sti
    ret

.globl cli
.type cli, @function
cli:
    cli
    ret

.globl hlt
.type hlt, @function
hlt:
    hlt
    ret