const std = @import("std");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const tty = @import("tty.zig");
const mem = @import("mem.zig");
const pmem = @import("pmem.zig");
const buddy = @import("buddy_enhanced.zig");
const vmem = @import("vmem.zig");
const scheduler = @import("scheduler.zig");
const timer = @import("timer.zig");
const keyboard = @import("keyboard.zig");
const syscall = @import("syscall.zig");
const x86 = @import("x86.zig");
const pic = @import("pic.zig");
const vfs = @import("vfs_enhanced.zig");
const device = @import("device_enhanced.zig");
const fat32 = @import("fat32_enhanced.zig");
const ipc = @import("ipc_mach.zig"); // Using enhanced Mach IPC

const MULTIBOOT_BOOTLOADER_MAGIC = 0x2BADB002;

extern fn boot_entry() noreturn;
extern const kernel_stack_top: u8;

const MultibootInfo = extern struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
};

pub fn panic(message: []const u8, trace: ?*std.builtin.StackTrace, ra: ?usize) noreturn {
    _ = trace;
    _ = ra;
    tty.panic("{s}", .{message});
}

export fn kmain(magic: u32, info: *const MultibootInfo) noreturn {
    tty.initialize();
    
    const title = "EnochOS Kernel v1.0.0";
    const version = "A modern microkernel with Mach IPC & VFS";
    
    tty.alignCenter(title.len);
    tty.colorPrint(tty.Color.light_red, "{s}", .{title});
    tty.print("\n", .{});
    
    tty.alignCenter(version.len);
    tty.colorPrint(tty.Color.white, "{s}", .{version});
    tty.print("\n\n", .{});
    
    if (magic != MULTIBOOT_BOOTLOADER_MAGIC) {
        tty.panic("Invalid multiboot magic number!", .{});
    }
    
    tty.colorPrint(tty.Color.light_blue, "[1/10] Initializing GDT...\n", .{});
    gdt.initialize();
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[2/10] Initializing IDT & PIC...\n", .{});
    pic.remap();
    idt.initialize();
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[3/10] Initializing physical memory...\n", .{});
    pmem.initialize(info);
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[4/10] Initializing Buddy Allocator...\n", .{});
    buddy.initialize(0x01000000, 16 * 1024 * 1024);
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[5/10] Initializing virtual memory...\n", .{});
    vmem.initialize();
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[6/10] Initializing VFS...\n", .{});
    vfs.initialize();
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[7/10] Initializing device manager...\n", .{});
    device.initialize();
    device.registerStandardDevices();
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[8/10] Initializing Mach IPC...\n", .{});
    ipc.initialize();
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[9/10] Initializing timer & keyboard...\n", .{});
    timer.initialize(100);
    keyboard.initialize();
    tty.stepOK();
    
    tty.colorPrint(tty.Color.light_blue, "[10/10] Initializing scheduler & syscalls...\n", .{});
    scheduler.initialize();
    syscall.initialize();
    tty.stepOK();
    
    tty.print("\n", .{});
    tty.colorPrint(tty.Color.light_green, "EnochOS Kernel loaded successfully!\n", .{});
    tty.colorPrint(tty.Color.green, "Starting user-space processes...\n\n", .{});
    
    x86.sti();
    
    scheduler.run();
    
    while (true) {
        x86.hlt();
    }
}
