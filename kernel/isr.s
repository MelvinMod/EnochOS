.section .text

.macro ISR_NOERR code
.globl isr\code
.type isr\code, @function
isr\code:
    cli
    pusha
    xor %eax, %eax
    push %eax
    push $\code
    call isr_handler
    add $8, %esp
    popa
    add $4, %esp
    iret
.endm

.macro ISR_ERR code
.globl isr\code
.type isr\code, @function
isr\code:
    cli
    pusha
    push $\code
    call isr_handler
    add $8, %esp
    popa
    add $4, %esp
    iret
.endm

ISR_NOERR 0
ISR_NOERR 1
ISR_NOERR 2
ISR_NOERR 3
ISR_NOERR 4
ISR_NOERR 5
ISR_NOERR 6
ISR_NOERR 7
ISR_ERR 8
ISR_NOERR 9
ISR_ERR 10
ISR_ERR 11
ISR_ERR 12
ISR_ERR 13
ISR_ERR 14
ISR_NOERR 15
ISR_NOERR 16
ISR_ERR 17
ISR_NOERR 18
ISR_NOERR 19
ISR_NOERR 32
ISR_NOERR 33
ISR_NOERR 34
ISR_NOERR 35
ISR_NOERR 36
ISR_NOERR 37
ISR_NOERR 38
ISR_NOERR 39
ISR_NOERR 40
ISR_NOERR 41
ISR_NOERR 42
ISR_NOERR 43
ISR_NOERR 44
ISR_NOERR 45
ISR_NOERR 46
ISR_NOERR 47
ISR_NOERR 128
