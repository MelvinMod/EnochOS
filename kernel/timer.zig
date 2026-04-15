const std = @import("std");
const tty = @import("tty.zig");
const x86 = @import("x86.zig");
const idt = @import("idt.zig");
const pic = @import("pic.zig");

const TIMER_FREQ = 1000;
const PIT_FREQ = 1193182;

var tick_count: u32 = 0;
var timer_initialized = false;

pub fn initialize(freq: u32) void {
    const divisor: u32 = @divTrunc(PIT_FREQ, freq);
    const lsb: u8 = @truncate(divisor & 0xFF);
    const msb: u8 = @truncate((divisor >> 8) & 0xFF);

    x86.outb(0x43, 0x36);
    x86.outb(0x40, lsb);
    x86.outb(0x40, msb);

    pic.remap();

    idt.set_handler(32, timer_handler);

    timer_initialized = true;
}

fn timer_handler(frame: *idt.InterruptFrame) void {
    _ = frame;
    tick_count += 1;
}

pub fn getTicks() u32 {
    return tick_count;
}

pub fn sleep(ms: u32) void {
    const start = tick_count;
    const target = start + (ms * tick_count / 1000);

    while (tick_count < target) {
        x86.hlt();
    }
}