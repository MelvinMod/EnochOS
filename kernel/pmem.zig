const std = @import("std");
const tty = @import("tty.zig");

const MemoryMapEntry = extern struct {
    base: u64,
    length: u64,
    type: u32,
};

var memory_map: []MemoryMapEntry = &.{};
var mem_lower: u32 = 0;
var mem_upper: u32 = 0;
var heap_start: u32 = 0;
var heap_end: u32 = 0;
var heap_pos: u32 = 0;

const MAX_MEM_MAP_ENTRIES = 128;
var temp_mem_map: [MAX_MEM_MAP_ENTRIES]MemoryMapEntry = undefined;
var mem_map_count: usize = 0;

pub fn initialize(boot_info: *const anyopaque) void {
    _ = boot_info;
    mem_map_count = 0;
    
    const EBDA_addr: *const u32 = @as(*const u32, @ptrFromInt(0x400));
    mem_lower = EBDA_addr.*;
    
    mem_upper = 64 * 1024;
    
    heap_start = 0x01000000;
    heap_pos = heap_start;
    heap_end = 0x7FFFFFFF;
}

pub fn getMemLower() u32 {
    return mem_lower;
}

pub fn getMemUpper() u32 {
    return mem_upper;
}

pub fn kmalloc(size: usize) ?[*]u8 {
    const aligned_size = (size + 4095) & ~4095;
    
    if (heap_pos + aligned_size > heap_end) {
        return null;
    }
    
    const ptr = heap_pos;
    heap_pos += @intCast(aligned_size);
    
    return @as([*]u8, @ptrFromInt(ptr));
}

pub fn kfree(ptr: [*]u8) void {
    _ = ptr;
}

pub fn allocPages(count: usize) ?[*]u8 {
    const size = count * 4096;
    return kmalloc(size);
}

pub fn freePages(ptr: [*]u8, count: usize) void {
    _ = ptr;
    _ = count;
}
