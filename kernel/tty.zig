const std = @import("std");
const fmt = std.fmt;
const x86 = @import("x86.zig");

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_ADDR = 0xB8000;

pub const Color = enum(u8) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    magenta = 5,
    brown = 6,
    light_grey = 7,
    dark_grey = 8,
    light_blue = 9,
    light_green = 10,
    light_cyan = 11,
    light_red = 12,
    light_magenta = 13,
    light_brown = 14,
    white = 15,
};

const VGAEntry = packed struct {
    char: u8,
    color: u8,
};

var vga_buffer: *[VGA_WIDTH * VGA_HEIGHT]VGAEntry = @ptrFromInt(VGA_ADDR);
var cursor_x: usize = 0;
var cursor_y: usize = 0;
var current_fg: Color = Color.light_grey;
var current_bg: Color = Color.black;

pub fn initialize() void {
    clear();
}

pub fn clear() void {
    const blank = VGAEntry{ .char = ' ', .color = (@intFromEnum(current_bg) << 4) | @intFromEnum(current_fg) };
    var i: usize = 0;
    while (i < VGA_WIDTH * VGA_HEIGHT) : (i += 1) {
        vga_buffer[i] = blank;
    }
    cursor_x = 0;
    cursor_y = 0;
    update_cursor();
}

pub fn writeChar(c: u8) void {
    if (c == '\n') {
        cursor_x = 0;
        cursor_y += 1;
    } else if (c == '\r') {
        cursor_x = 0;
    } else if (c == '\t') {
        cursor_x = (cursor_x + 8) & ~@as(usize, 7);
    } else {
        const index = cursor_y * VGA_WIDTH + cursor_x;
        vga_buffer[index] = VGAEntry{
            .char = c,
            .color = (@intFromEnum(current_bg) << 4) | @intFromEnum(current_fg),
        };
        cursor_x += 1;
    }

    if (cursor_x >= VGA_WIDTH) {
        cursor_x = 0;
        cursor_y += 1;
    }

    if (cursor_y >= VGA_HEIGHT) {
        scroll();
    }

    update_cursor();
}

fn scroll() void {
    var i: usize = 0;
    while (i < (VGA_HEIGHT - 1) * VGA_WIDTH) : (i += 1) {
        vga_buffer[i] = vga_buffer[i + VGA_WIDTH];
    }

    const blank = VGAEntry{ .char = ' ', .color = (@intFromEnum(current_bg) << 4) | @intFromEnum(current_fg) };
    i = (VGA_HEIGHT - 1) * VGA_WIDTH;
    while (i < VGA_WIDTH * VGA_HEIGHT) : (i += 1) {
        vga_buffer[i] = blank;
    }

    cursor_y = VGA_HEIGHT - 1;
}

fn update_cursor() void {
    const pos = cursor_y * VGA_WIDTH + cursor_x;
    const low_port: u16 = 0x3D4;
    const high_port: u16 = 0x3D5;
    
    outb(low_port, 0x0F);
    outb(high_port, @truncate(pos & 0xFF));
    outb(low_port, 0x0E);
    outb(high_port, @truncate((pos >> 8) & 0xFF));
}

fn outb(port: u16, value: u8) void {
    x86.outb(port, value);
}

pub fn setForeground(color: Color) void {
    current_fg = color;
}

pub fn setBackground(color: Color) void {
    current_bg = color;
}

pub fn print(comptime format: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const result = fmt.bufPrint(&buf, format, args) catch {
        writeChar('!');
        return;
    };

    for (result) |c| {
        writeChar(c);
    }
}

pub fn colorPrint(fg: Color, comptime format: []const u8, args: anytype) void {
    const save = current_fg;
    current_fg = fg;
    print(format, args);
    current_fg = save;
}

pub fn alignCenter(str_len: usize) void {
    const offset = (VGA_WIDTH - str_len) / 2;
    while (cursor_x < offset) {
        writeChar(' ');
    }
}

pub fn alignRight(offset: usize) void {
    const target = VGA_WIDTH - offset;
    while (cursor_x < target) {
        writeChar(' ');
    }
}

pub fn panic(comptime format: []const u8, args: anytype) noreturn {
    const save_fg = current_fg;
    const save_bg = current_bg;

    current_fg = Color.white;
    current_bg = Color.red;

    clear();
    alignCenter(18);
    colorPrint(Color.white, "KERNEL PANIC", .{});
    print("\n\n", .{});
    print("Error: ", .{});
    colorPrint(Color.brown, format ++ "\n", args);

    current_fg = save_fg;
    current_bg = save_bg;

    asm volatile ("1: hlt\n\tjmp 1b");
    unreachable;
}

pub fn step(comptime format: []const u8, args: anytype) void {
    colorPrint(Color.light_blue, ">> ", .{});
    print(format ++ "...", args);
}

pub fn stepOK() void {
    const ok = " [ OK ]";
    alignRight(ok.len);
    colorPrint(Color.light_green, ok, .{});
    print("\n", .{});
}
