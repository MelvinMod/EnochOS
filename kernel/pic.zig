const x86 = @import("x86.zig");

const PIC1_COMMAND = 0x20;
const PIC1_DATA = 0x21;
const PIC2_COMMAND = 0xA0;
const PIC2_DATA = 0xA1;

const ICW1_ICW4 = 0x01;
const ICW1_INIT = 0x10;
const ICW4_8086 = 0x01;
const PIC_EOI = 0x20;

pub fn remap() void {
    const mask1: u8 = x86.inb(PIC1_DATA);
    const mask2: u8 = x86.inb(PIC2_DATA);

    x86.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    x86.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);

    x86.outb(PIC1_DATA, 0x20);
    x86.outb(PIC2_DATA, 0x28);

    x86.outb(PIC1_DATA, 4);
    x86.outb(PIC2_DATA, 2);

    x86.outb(PIC1_DATA, ICW4_8086);
    x86.outb(PIC2_DATA, ICW4_8086);

    x86.outb(PIC1_DATA, mask1);
    x86.outb(PIC2_DATA, mask2);
}

pub fn sendEOI() void {
    x86.outb(PIC1_COMMAND, PIC_EOI);
}

pub fn disable() void {
    x86.outb(PIC1_DATA, 0xFF);
    x86.outb(PIC2_DATA, 0xFF);
}