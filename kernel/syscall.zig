const std = @import("std");
const tty = @import("tty.zig");
const x86 = @import("x86.zig");
const idt = @import("idt.zig");

var syscall_table: [256]?*const fn (args: *SyscallArgs) i32 = undefined;

pub const SyscallArgs = extern struct {
    arg0: u32,
    arg1: u32,
    arg2: u32,
    arg3: u32,
};

pub fn initialize() void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        syscall_table[i] = null;
    }
    
    idt.set_handler(128, syscall_handler);
}

pub fn registerSyscall(num: u8, handler: *const fn (*SyscallArgs) i32) void {
    if (num < 256) {
        syscall_table[num] = handler;
    }
}

fn syscall_handler(frame: *idt.InterruptFrame) void {
    if (syscall_table[0]) |handler| {
        const args: *SyscallArgs = @ptrFromInt(frame.ebx);
        frame.eax = @intCast(handler(args));
    }
}