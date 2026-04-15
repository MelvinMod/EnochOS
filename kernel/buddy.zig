const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");

const PAGE_SIZE = 4096;
const BUCKET_COUNT = 16;

const BuddyAllocator = struct {
    orders: [16]usize,
    total_pages: usize,
    base_addr: u32,

    pub fn init(base: u32, total_pages: usize) BuddyAllocator {
        var allocator = BuddyAllocator{
            .orders = undefined,
            .total_pages = total_pages,
            .base_addr = base,
        };
        var i: usize = 0;
        while (i < BUCKET_COUNT) : (i += 1) {
            allocator.orders[i] = 0;
        }
        allocator.orders[12] = total_pages;
        return allocator;
    }

    fn orderForSize(size: usize) usize {
        var order: usize = 0;
        const pages: usize = (size + PAGE_SIZE - 1) / PAGE_SIZE;
        while ((@as(usize, 1) << order) < pages) : (order += 1) {}
        return @min(order, 12);
    }

    pub fn allocate(alloc: *BuddyAllocator, size: usize) ?[*]u8 {
        const order = orderForSize(size);
        return alloc.allocateOrder(order);
    }

    fn allocateOrder(alloc: *BuddyAllocator, order: usize) ?[*]u8 {
        if (order > 12) return null;
        
        if (alloc.orders[order] > 0) {
            alloc.orders[order] -= 1;
            return @as([*]u8, @ptrFromInt(alloc.base_addr + (order << 12)));
        }

        var current_order = order + 1;
        while (current_order <= 12 and alloc.orders[current_order] == 0) : (current_order += 1) {}
        
        if (current_order > 12) return null;
        
        alloc.orders[current_order] -= 1;
        
        var split_order = current_order;
        while (split_order > order) : (split_order -= 1) {
            alloc.orders[split_order - 1] += 1;
        }
        
        return @as([*]u8, @ptrFromInt(alloc.base_addr + (order << 12)));
    }

    pub fn free(alloc: *BuddyAllocator, ptr: [*]u8, size: usize) void {
        const order = orderForSize(size);
        alloc.freeOrder(ptr, order);
    }

    fn freeOrder(alloc: *BuddyAllocator, _: [*]u8, order: usize) void {
        if (order > 12) return;
        
        alloc.orders[order] += 1;
        
        while (order < 12) {
            const buddy_order = order + 1;
            if (alloc.orders[buddy_order] < 1) break;
            
            alloc.orders[buddy_order] -= 1;
            alloc.orders[order] -= 1;
            order = buddy_order;
        }
    }
};

var buddy: ?BuddyAllocator = null;
var heap_start: u32 = 0;
var heap_size: usize = 0;

pub fn initialize(base_addr: u32, size: usize) void {
    heap_start = base_addr;
    heap_size = size;
    buddy = BuddyAllocator.init(base_addr, size / PAGE_SIZE);
    tty.print("[Buddy] Allocator initialized at 0x{x} with {} pages\n", .{ base_addr, size / PAGE_SIZE });
}

pub fn allocate(size: usize) ?[*]u8 {
    if (buddy) |*b| {
        return b.allocate(size);
    }
    return pmem.kmalloc(size);
}

pub fn free(ptr: [*]u8, size: usize) void {
    if (buddy) |*b| {
        b.free(ptr, size);
    }
}

pub fn allocatePages(count: usize) ?[*]u8 {
    return allocate(count * PAGE_SIZE);
}

pub fn freePages(ptr: [*]u8, count: usize) void {
    free(ptr, count * PAGE_SIZE);
}
