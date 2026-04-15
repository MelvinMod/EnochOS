//! Enhanced Buddy Allocator with Transparent Huge Pages support
//! Based on linux mm/page_alloc.c and mm/buddy_system.c

const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");

const MAX_ORDER = 11; // 2^11 = 2048 pages = 8MB
const MAX_ORDERED = MAX_ORDER + 1;
const MAX_MIGRATION_TYPES = 4;
const NR_FREE_BUCKETS = 4;

// ============================================================================
// Migration Types (from linux mm/internal.h)
// ============================================================================
pub const MigrationType = enum(u8) {
    MIGRATE_UNMOVABLE = 0,      // Fixed location objects
    MIGRATE_RECLAIMABLE = 1,    // Reclaimable objects
    MIGRATE_MOVABLE = 2,        // Movable objects
    MIGRATE_CMA = 3,            // Contiguous Memory Allocator
    MIGRATE_TYPES = 4,
};

// ============================================================================
// Page State (from linux include/linux/page-flags.h)
// ============================================================================
pub const PageState = enum(u8) {
    FREE = 0,
    RESERVED = 1,
    BUSY = 2,
};

// ============================================================================
// Free List (from linux mm/buddy_system.c)
// ============================================================================
pub const FreeList = struct {
    pages: [1024]u32, // Physical page frame numbers
    head: usize,
    tail: usize,
    count: usize,

    pub fn init() FreeList {
        return FreeList{
            .pages = undefined,
            .head = 0,
            .tail = 0,
            .count = 0,
        };
    }

    pub fn push(self: *FreeList, pfn: u32) bool {
        if (self.count >= 1024) return false;
        self.pages[self.tail] = pfn;
        self.tail = (self.tail + 1) % 1024;
        self.count += 1;
        return true;
    }

    pub fn pop(self: *FreeList) ?u32 {
        if (self.count == 0) return null;
        const pfn = self.pages[self.head];
        self.head = (self.head + 1) % 1024;
        self.count -= 1;
        return pfn;
    }

    pub fn isEmpty(self: *const FreeList) bool {
        return self.count == 0;
    }
};

// ============================================================================
// Free Area (from linux mm/buddy_system.c)
// ============================================================================
pub const FreeArea = struct {
    free_list: [MAX_MIGRATION_TYPES]FreeList,
    count: usize,
    
    pub fn init() FreeArea {
        var area = FreeArea{
            .free_list = undefined,
            .count = 0,
        };
        var i: usize = 0;
        while (i < MAX_MIGRATION_TYPES) : (i += 1) {
            area.free_list[i] = FreeList.init();
        }
        return area;
    }
};

// ============================================================================
// Page Struct (from linux include/linux/mm_types.h)
// Metadata for each physical page
// ============================================================================
pub const Page = struct {
    pfn: u32,                   // Page Frame Number
    order: u8,                  // Buddy order (2^order pages)
    migration_type: MigrationType,
    state: PageState,
    refcount: u32,
    list_index: usize,          // Index in free list
};

// ============================================================================
// Buddy Allocator (Enhanced from linux mm/page_alloc.c)
// ============================================================================
pub const BuddyAllocator = struct {
    // Configuration
    base_pfn: u32,
    total_pages: u32,
    page_size: u32,
    
    // Free areas by order
    free_area: [MAX_ORDERED]FreeArea,
    
    // Page metadata
    pages: [65536]Page, // 64K pages = 256MB with 4KB pages
    page_count: u32,
    
    // Statistics
    total_free: u32,
    total_reserved: u32,
    
    // Huge page support
    thp_enabled: bool,
    thp_count: u32,
    
    // Watermarks (from linux mm/page_alloc.c)
    watermark_min: u32,
    watermark_low: u32,
    watermark_high: u32,

    pub fn init(base: u32, size_bytes: u32, page_size: u32) BuddyAllocator {
        const total_pages = size_bytes / page_size;
        
        var allocator = BuddyAllocator{
            .base_pfn = base,
            .total_pages = total_pages,
            .page_size = page_size,
            .free_area = undefined,
            .pages = undefined,
            .page_count = 0,
            .total_free = total_pages,
            .total_reserved = 0,
            .thp_enabled = true,
            .thp_count = 0,
            .watermark_min = 0,
            .watermark_low = 0,
            .watermark_high = 0,
        };
        
        // Initialize free areas
        var i: usize = 0;
        while (i < MAX_ORDERED) : (i += 1) {
            allocator.free_area[i] = FreeArea.init();
        }
        
        // Initialize pages
        i = 0;
        while (i < total_pages and i < 65536) : (i += 1) {
            allocator.pages[i] = Page{
                .pfn = @intCast(base + @as(u32, @intCast(i))),
                .order = 0,
                .migration_type = .MIGRATE_MOVABLE,
                .state = .FREE,
                .refcount = 0,
                .list_index = 0,
            };
        }
        allocator.page_count = @intCast(i);
        
        // Calculate watermarks
        allocator.watermark_min = allocator.page_count / 64;
        allocator.watermark_low = allocator.page_count / 32;
        allocator.watermark_high = allocator.page_count / 16;
        
        // Initialize buddy system - add all pages as order-0
        allocator.initBuddySystem();
        
        return allocator;
    }

    fn initBuddySystem(self: *BuddyAllocator) void {
        // Add all pages to order-0 free list
        var i: u32 = 0;
        while (i < self.page_count) : (i += 1) {
            if (self.free_area[0].free_list[0].push(self.pages[i].pfn)) {
                self.pages[i].state = .FREE;
            }
        }
        
        tty.print("[BUDDY] Initialized {d} pages ({d} MB)\n", .{
            self.page_count, self.page_count * self.page_size / (1024 * 1024)
        });
    }

    // ========================================================================
    // Page Allocation (from linux mm/page_alloc.c)
    // ========================================================================
    pub fn allocatePages(self: *BuddyAllocator, order: u8, migration: MigrationType) ?u32 {
        if (order >= MAX_ORDER) return null;
        
        const num_pages = @as(u32, 1) << order;
        
        // Try to allocate from the requested order
        if (self.allocateBuddy(order, migration)) |pfn| {
            // Mark pages as busy
            const start_idx = pfn - self.base_pfn;
            var i: u32 = 0;
            while (i < num_pages and (start_idx + i) < self.page_count) : (i += 1) {
                self.pages[start_idx + i].state = .BUSY;
                self.pages[start_idx + i].order = order;
                self.pages[start_idx + i].migration_type = migration;
                self.pages[start_idx + i].refcount = 1;
            }
            self.total_free -= num_pages;
            self.total_reserved += num_pages;
            
            if (order > 0) {
                self.thp_count += 1;
            }
            
            return pfn;
        }
        
        // Try to break higher-order pages
        return self.expandAndAllocate(order, migration);
    }

    fn allocateBuddy(self: *BuddyAllocator, order: u8, migration: MigrationType) ?u32 {
        // Try all migration types
        var mt: u8 = 0;
        while (mt < MAX_MIGRATION_TYPES) : (mt += 1) {
            if (!self.free_area[order].free_list[mt].isEmpty()) {
                return self.free_area[order].free_list[mt].pop();
            }
        }
        return null;
    }

    fn expandAndAllocate(self: *BuddyAllocator, order: u8, migration: MigrationType) ?u32 {
        // Find a higher-order block to break
        var search_order: u8 = order + 1;
        while (search_order < MAX_ORDER) : (search_order += 1) {
            if (self.allocateBuddy(search_order, migration)) |pfn| {
                // Break the block into smaller pieces
                return self.breakBlock(pfn, search_order, order, migration);
            }
        }
        
        // Compaction attempt (from linux mm/compaction.c)
        if (self.tryCompact()) {
            if (self.allocateBuddy(order, migration)) |pfn| {
                return pfn;
            }
        }
        
        return null;
    }

    fn breakBlock(self: *BuddyAllocator, pfn: u32, high_order: u8, target_order: u8, migration: MigrationType) ?u32 {
        var current_order = high_order;
        var current_pfn = pfn;
        
        while (current_order > target_order) {
            current_order -= 1;
            const buddy_pfn = current_pfn + (@as(u32, 1) << current_order);
            
            // Add buddy to free list
            const mt_idx: u8 = @intFromEnum(migration);
            self.free_area[current_order].free_list[mt_idx].push(buddy_pfn);
            
            self.pages[buddy_pfn - self.base_pfn].state = .FREE;
            self.pages[buddy_pfn - self.base_pfn].order = current_order;
            
            current_pfn = current_pfn; // Keep one half
        }
        
        self.total_free += (@as(u32, 1) << high_order) - (@as(u32, 1) << target_order);
        return current_pfn;
    }

    // ========================================================================
    // Page Deallocation (from linux mm/page_alloc.c)
    // ========================================================================
    pub fn freePages(self: *BuddyAllocator, pfn: u32, order: u8) void {
        if (pfn < self.base_pfn or pfn >= self.base_pfn + self.page_count) {
            return;
        }
        
        const start_idx = pfn - self.base_pfn;
        
        // Mark pages as free
        const num_pages = @as(u32, 1) << order;
        var i: u32 = 0;
        while (i < num_pages and (start_idx + i) < self.page_count) : (i += 1) {
            self.pages[start_idx + i].state = .FREE;
            self.pages[start_idx + i].refcount = 0;
        }
        
        self.total_free += num_pages;
        self.total_reserved -= num_pages;
        
        if (order > 0 and self.thp_count > 0) {
            self.thp_count -= 1;
        }
        
        // Coalesce with buddies
        self.coalesce(pfn, order);
    }

    fn coalesce(self: *BuddyAllocator, pfn: u32, order: u8) void {
        var current_pfn = pfn;
        var current_order = order;
        
        while (current_order < MAX_ORDER - 1) {
            // Calculate buddy
            const is_higher = (current_pfn & (@as(u32, 1) << current_order)) != 0;
            const buddy_pfn = if (is_higher)
                current_pfn - (@as(u32, 1) << current_order)
            else
                current_pfn + (@as(u32, 1) << current_order);
            
            // Check if buddy is free and same order
            if (!self.isBuddyFree(buddy_pfn, current_order)) {
                break;
            }
            
            // Remove buddy from free list
            self.removeBuddyFromFreeList(buddy_pfn, current_order);
            
            // Update current_pfn to the lower address
            if (is_higher) {
                current_pfn = buddy_pfn;
            }
            
            current_order += 1;
        }
        
        // Add merged block to free list
        const mt_idx: u8 = @intFromEnum(.MIGRATE_MOVABLE);
        self.free_area[current_order].free_list[mt_idx].push(current_pfn);
        self.pages[current_pfn - self.base_pfn].order = current_order;
    }

    fn isBuddyFree(self: *BuddyAllocator, pfn: u32, order: u8) bool {
        if (pfn < self.base_pfn or pfn >= self.base_pfn + self.page_count) {
            return false;
        }
        
        const idx = pfn - self.base_pfn;
        return self.pages[idx].state == .FREE and self.pages[idx].order == order;
    }

    fn removeBuddyFromFreeList(self: *BuddyAllocator, pfn: u32, order: u8) void {
        // Simple approach - just mark as busy
        const idx = pfn - self.base_pfn;
        self.pages[idx].state = .BUSY;
    }

    // ========================================================================
    // Memory Compaction (from linux mm/compaction.c)
    // ========================================================================
    fn tryCompact(self: *BuddyAllocator) bool {
        // Simplified compaction - in real implementation, migrate pages
        // to create larger contiguous free blocks
        
        // For now, just return false (no compaction)
        return false;
    }

    // ========================================================================
    // Transparent Huge Pages (THP) Support
    // ========================================================================
    pub fn enableTHP(self: *BuddyAllocator) void {
        self.thp_enabled = true;
        tty.print("[BUDDY] Transparent Huge Pages enabled\n", .{});
    }

    pub fn disableTHP(self: *BuddyAllocator) void {
        self.thp_enabled = false;
        tty.print("[BUDDY] Transparent Huge Pages disabled\n", .{});
    }

    pub fn allocateTHP(self: *BuddyAllocator) ?u32 {
        if (!self.thp_enabled) return null;
        
        // Allocate 2MB huge page (order-9 with 4KB pages)
        return self.allocatePages(9, .MIGRATE_MOVABLE);
    }

    // ========================================================================
    // Statistics
    // ========================================================================
    pub fn getFreePages(self: *const BuddyAllocator) u32 {
        return self.total_free;
    }

    pub fn getUsedPages(self: *const BuddyAllocator) u32 {
        return self.total_pages - self.total_free;
    }

    pub fn getFreeMemory(self: *const BuddyAllocator) u64 {
        return @as(u64, self.total_free) * self.page_size;
    }

    pub fn getUsedMemory(self: *const BuddyAllocator) u64 {
        return @as(u64, self.getUsedPages()) * self.page_size;
    }

    pub fn dumpStats(self: *const BuddyAllocator) void {
        tty.print("[BUDDY] Memory Statistics:\n", .{});
        tty.print("  Total: {d} pages ({d} MB)\n", .{
            self.total_pages, self.total_pages * self.page_size / (1024 * 1024)
        });
        tty.print("  Free: {d} pages ({d} MB)\n", .{
            self.total_free, self.getFreeMemory() / (1024 * 1024)
        });
        tty.print("  Used: {d} pages ({d} MB)\n", .{
            self.getUsedPages(), self.getUsedMemory() / (1024 * 1024)
        });
        tty.print("  THP enabled: {s}\n", .{if (self.thp_enabled) "yes" else "no"});
        tty.print("  THP count: {d}\n", .{self.thp_count});
        
        tty.print("  Free areas:\n", .{});
        var i: u8 = 0;
        while (i < MAX_ORDERED) : (i += 1) {
            var total: usize = 0;
            var j: u8 = 0;
            while (j < MAX_MIGRATION_TYPES) : (j += 1) {
                total += self.free_area[i].free_list[j].count;
            }
            if (total > 0) {
                tty.print("    Order {d}: {d} blocks\n", .{ i, total });
            }
        }
    }
};

// ============================================================================
// Global State
// ============================================================================
var allocator: ?BuddyAllocator = null;

// ============================================================================
// Public API (compatible with original buddy.zig)
// ============================================================================
pub fn initialize(base: u32, size: u32) void {
    const PAGE_SIZE = 4096;
    allocator = BuddyAllocator.init(base, size, PAGE_SIZE);
}

pub fn allocate(order: u8) ?u32 {
    if (allocator) |*alloc| {
        return alloc.allocatePages(order, .MIGRATE_MOVABLE);
    }
    return null;
}

pub fn free(pfn: u32, order: u8) void {
    if (allocator) |*alloc| {
        alloc.freePages(pfn, order);
    }
}

pub fn allocatePages(count: u32) ?u32 {
    // Calculate order needed
    var order: u8 = 0;
    var pages: u32 = 1;
    while (pages < count) : (order += 1) {
        pages *= 2;
    }
    
    return allocate(order);
}

pub fn freePages(pfn: u32, count: u32) void {
    // Calculate order from count
    var order: u8 = 0;
    var pages: u32 = 1;
    while (pages < count) : (order += 1) {
        pages *= 2;
    }
    
    free(pfn, order);
}

pub fn getFreeMemory() u64 {
    if (allocator) |*alloc| {
        return alloc.getFreeMemory();
    }
    return 0;
}

pub fn getUsedMemory() u64 {
    if (allocator) |*alloc| {
        return alloc.getUsedMemory();
    }
    return 0;
}

pub fn dumpStats() void {
    if (allocator) |*alloc| {
        alloc.dumpStats();
    }
}
