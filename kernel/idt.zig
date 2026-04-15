const std = @import("std");
const tty = @import("tty.zig");
const x86 = @import("x86.zig");

const IDTEntry = packed struct {
    base_low: u16,
    selector: u16,
    zero: u8,
    type_attr: u8,
    base_mid: u16,
    base_high: u8,
    reserved: u24 = 0,
};

const IDTPointer = packed struct {
    limit: u16,
    base: u32,
};

const IDT_SIZE = 256;
var idt_table: [IDT_SIZE]IDTEntry = undefined;
var idt_ptr: IDTPointer = undefined;

extern fn isr0() void;
extern fn isr1() void;
extern fn isr2() void;
extern fn isr3() void;
extern fn isr4() void;
extern fn isr5() void;
extern fn isr6() void;
extern fn isr7() void;
extern fn isr8() void;
extern fn isr9() void;
extern fn isr10() void;
extern fn isr11() void;
extern fn isr12() void;
extern fn isr13() void;
extern fn isr14() void;
extern fn isr15() void;
extern fn isr16() void;
extern fn isr17() void;
extern fn isr18() void;
extern fn isr19() void;
extern fn isr32() void;
extern fn isr33() void;
extern fn isr34() void;
extern fn isr35() void;
extern fn isr36() void;
extern fn isr37() void;
extern fn isr38() void;
extern fn isr39() void;
extern fn isr40() void;
extern fn isr41() void;
extern fn isr42() void;
extern fn isr43() void;
extern fn isr44() void;
extern fn isr45() void;
extern fn isr46() void;
extern fn isr47() void;
extern fn isr128() void;

var isr_handlers: [IDT_SIZE]?*const fn (frame: *InterruptFrame) void = undefined;

pub const InterruptFrame = extern struct {
    ds: u32,
    edi: u32,
    esi: u32,
    ebp: u32,
    esp_dummy: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    int_no: u32,
    err_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
    esp: u32,
    ss: u32,
};

const IDT_PRESENT = 0x80;
const IDT_RING0 = 0x00;
const IDT_INT_GATE = 0x0E;

pub fn set_handler(index: u8, handler: *const fn (*InterruptFrame) void) void {
    if (index < IDT_SIZE) {
        isr_handlers[index] = handler;
    }
}

fn set_gate(index: u16, base: usize, selector: u16, flags: u8) void {
    const offset: u32 = @intCast(base);
    idt_table[index] = IDTEntry{
        .base_low = @truncate(offset),
        .selector = selector,
        .zero = 0,
        .type_attr = flags,
        .base_mid = @truncate(offset >> 16),
        .base_high = @truncate(offset >> 24),
    };
}

pub fn initialize() void {
    var i: usize = 0;
    while (i < IDT_SIZE) : (i += 1) {
        idt_table[i] = IDTEntry{
            .base_low = 0,
            .selector = 0,
            .zero = 0,
            .type_attr = 0,
            .base_mid = 0,
            .base_high = 0,
        };
        isr_handlers[i] = null;
    }

    const KERNEL_CODE_SEG: u16 = 0x08;
    const INTERRUPT_FLAG: u8 = IDT_PRESENT | IDT_RING0 | IDT_INT_GATE;

    set_gate(0, @intFromPtr(&isr0), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(1, @intFromPtr(&isr1), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(2, @intFromPtr(&isr2), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(3, @intFromPtr(&isr3), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(4, @intFromPtr(&isr4), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(5, @intFromPtr(&isr5), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(6, @intFromPtr(&isr6), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(7, @intFromPtr(&isr7), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(8, @intFromPtr(&isr8), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(9, @intFromPtr(&isr9), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(10, @intFromPtr(&isr10), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(11, @intFromPtr(&isr11), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(12, @intFromPtr(&isr12), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(13, @intFromPtr(&isr13), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(14, @intFromPtr(&isr14), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(15, @intFromPtr(&isr15), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(16, @intFromPtr(&isr16), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(17, @intFromPtr(&isr17), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(18, @intFromPtr(&isr18), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(19, @intFromPtr(&isr19), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(32, @intFromPtr(&isr32), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(33, @intFromPtr(&isr33), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(34, @intFromPtr(&isr34), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(35, @intFromPtr(&isr35), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(36, @intFromPtr(&isr36), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(37, @intFromPtr(&isr37), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(38, @intFromPtr(&isr38), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(39, @intFromPtr(&isr39), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(40, @intFromPtr(&isr40), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(41, @intFromPtr(&isr41), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(42, @intFromPtr(&isr42), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(43, @intFromPtr(&isr43), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(44, @intFromPtr(&isr44), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(45, @intFromPtr(&isr45), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(46, @intFromPtr(&isr46), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(47, @intFromPtr(&isr47), KERNEL_CODE_SEG, INTERRUPT_FLAG);
    set_gate(128, @intFromPtr(&isr128), KERNEL_CODE_SEG, INTERRUPT_FLAG);

    idt_ptr = IDTPointer{
        .limit = @as(u16, @truncate(@sizeOf(@TypeOf(idt_table)))) - 1,
        .base = @intFromPtr(&idt_table),
    };

    x86.lidt(&idt_ptr);
}

export fn isr_handler(frame: *InterruptFrame) void {
    if (frame.int_no < IDT_SIZE and isr_handlers[frame.int_no] != null) {
        isr_handlers[frame.int_no].?(frame);
    }
}

pub fn eoi() void {
    x86.outb(0x20, 0x20);
    x86.outb(0xA0, 0x20);
}
