const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");

// Page table entry structure
const PageTableEntry = packed struct {
    present: u1,
    writable: u1,
    user_accessible: u1,
    write_through: u1,
    cache_disabled: u1,
    accessed: u1,
    dirty: u1,
    pat: u1,
    global: u1,
    _unused: u3,
    addr: u20,
    
    pub fn init(phys_addr: usize, writable: bool, user: bool) PageTableEntry {
        return PageTableEntry{
            .present = 1,
            .writable = if (writable) 1 else 0,
            .user_accessible = if (user) 1 else 0,
            .write_through = 0,
            .cache_disabled = 0,
            .accessed = 0,
            .dirty = 0,
            .pat = 0,
            .global = 0,
            ._unused = 0,
            .addr = @truncate(phys_addr >> 12),
        };
    }
    
    pub fn getPhysAddr(self: PageTableEntry) usize {
        return @as(usize, self.addr) << 12;
    }
};

// Page directory entry (same structure on i386 with 4KB pages)
const PageDirectoryEntry = PageTableEntry;

// Page table (1024 entries for 4MB)
var page_table: [1024]PageTableEntry = undefined;
var page_directory: [1024]PageDirectoryEntry = undefined;

// CR3 register value
var cr3: u32 = 0;

/// Initialize virtual memory
pub fn initialize() void {
    // Clear page table and directory
    @memset(&page_table, undefined);
    @memset(&page_directory, undefined);
    
    // Map first few pages for kernel
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        page_table[i] = PageTableEntry.init(i * pmem.PAGE_SIZE, true, false);
        page_directory[i] = PageDirectoryEntry.init(0, false, false);
    }
    
    // Set page table address in CR3
    cr3 = @intFromPtr(&page_table);
    
    // Load CR3
    asm volatile (
        "mov %%cr3, %0"
        : "=r"(cr3)
    );
    cr3 = @intFromPtr(&page_table);
    asm volatile (
        "mov %0, %%cr3"
        :
        : "r"(cr3)
    );
    
    // Enable paging in CR0
    var cr0: u32 = 0;
    asm volatile (
        "mov %%cr0, %0"
        : "=r"(cr0)
    );
    cr0 |= 0x80000000; // Set PG bit
    asm volatile (
        "mov %0, %%cr0"
        :
        : "r"(cr0)
    );
    
    tty.print("  Page directory at: 0x{x}\n", .{cr3});
    tty.print("  Page table at: 0x{x}\n", .{@intFromPtr(&page_table)});
}

/// Map a virtual address to a physical address
pub fn map(virtual_addr: usize, physical_addr: usize, writable: bool, user: bool) void {
    const virtual_page = @divTrunc(virtual_addr, pmem.PAGE_SIZE);
    const physical_page = @divTrunc(physical_addr, pmem.PAGE_SIZE);
    
    const table_idx = virtual_page % 1024;
    page_table[table_idx] = PageTableEntry.init(physical_page * pmem.PAGE_SIZE, writable, user);
    
    // Flush TLB entry
    asm volatile (
        "invlpg (%0)"
        :
        : "r"(virtual_addr)
        : "memory"
    );
}

/// Unmap a virtual address
pub fn unmap(virtual_addr: usize) void {
    const virtual_page = @divTrunc(virtual_addr, pmem.PAGE_SIZE);
    const table_idx = virtual_page % 1024;
    
    page_table[table_idx] = PageTableEntry{
        .present = 0,
        .writable = 0,
        .user_accessible = 0,
        .write_through = 0,
        .cache_disabled = 0,
        .accessed = 0,
        .dirty = 0,
        .pat = 0,
        .global = 0,
        ._unused = 0,
        .addr = 0,
    };
    
    // Flush TLB
    asm volatile (
        "invlpg (%0)"
        :
        : "r"(virtual_addr)
        : "memory"
    );
}

/// Get physical address from virtual address
pub fn virtToPhys(virtual_addr: usize) ?usize {
    const virtual_page = @divTrunc(virtual_addr, pmem.PAGE_SIZE);
    const table_idx = virtual_page % 1024;
    
    if (page_table[table_idx].present == 1) {
        const physical_base = page_table[table_idx].getPhysAddr();
        const offset = virtual_addr % pmem.PAGE_SIZE;
        return physical_base + offset;
    }
    
    return null;
}
