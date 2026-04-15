pub fn sti() void {
    asm volatile ("sti");
}

pub fn cli() void {
    asm volatile ("cli");
}

pub fn hlt() void {
    asm volatile ("hlt");
}

pub extern fn outb(port: u16, value: u8) void;
pub extern fn inb(port: u16) u8;
pub extern fn lidt(idtp: *const anyopaque) void;
pub extern fn lgdt(gdtp: *const anyopaque) void;
