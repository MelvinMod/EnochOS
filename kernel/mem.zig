const std = @import("std");
const pmem = @import("pmem.zig");

const HeapBlock = struct {
    size: usize,
    used: bool,
    next: ?*HeapBlock,
};

var heap_start: ?[*]u8 = null;
var heap_end: ?[*]u8 = null;
var first_block: ?*HeapBlock = null;

const BLOCK_HEADER_SIZE = @sizeOf(HeapBlock);

pub fn initialize(min_size: usize) void {
    const mem = pmem.kmalloc(min_size) orelse return;
    heap_start = mem;
    heap_end = mem + min_size;
    
    const first_block_addr = @intFromPtr(mem) + BLOCK_HEADER_SIZE;
    first_block = @as(*HeapBlock, @ptrFromInt(first_block_addr));
    first_block.?.size = min_size - BLOCK_HEADER_SIZE;
    first_block.?.used = false;
    first_block.?.next = null;
}

pub fn kmalloc(size: usize) ?[*]u8 {
    if (first_block == null) return null;
    
    const aligned_size = (size + @alignOf(usize) - 1) & ~(@alignOf(usize) - 1);
    
    var current = first_block;
    while (current != null) {
        const blk = current.?;
        if (!blk.used and blk.size >= aligned_size) {
            blk.used = true;
            
            if (blk.size > aligned_size + BLOCK_HEADER_SIZE + @sizeOf(usize)) {
                const new_block_addr = @intFromPtr(blk) + BLOCK_HEADER_SIZE + aligned_size;
                const new_block = @as(*HeapBlock, @ptrFromInt(new_block_addr));
                new_block.* = HeapBlock{
                    .size = blk.size - aligned_size - BLOCK_HEADER_SIZE,
                    .used = false,
                    .next = blk.next,
                };
                blk.size = aligned_size;
                blk.next = new_block;
            }
            
            return @as([*]u8, @ptrFromInt(@intFromPtr(blk) + BLOCK_HEADER_SIZE));
        }
        current = blk.next;
    }
    
    return null;
}

pub fn kfree(ptr: [*]u8) void {
    if (first_block == null) return;
    
    const block_addr = @intFromPtr(ptr) - BLOCK_HEADER_SIZE;
    const block = @as(*HeapBlock, @ptrFromInt(block_addr));
    block.used = false;
    
    var current = first_block;
    while (current != null) {
        const blk = current.?;
        if (blk.next != null and !blk.next.?.used and blk.next == @as(*HeapBlock, @ptrFromInt(@intFromPtr(blk) + BLOCK_HEADER_SIZE + blk.size))) {
            const next = blk.next.?;
            blk.size += BLOCK_HEADER_SIZE + next.size;
            blk.next = next.next;
        }
        current = blk.next;
    }
}
