//! FAT32 File System Driver - Enhanced version with caching
//! Based on linux fs/fat and darwin-xnu VFS components

const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");
const buddy = @import("buddy.zig");

const BLOCK_SIZE = 512;
const CLUSTER_CACHE_SIZE = 8;
const MAX_FAT32_FS = 4;

// ============================================================================
// FAT32 Boot Sector (from linux fs/fat/boot.h)
// ============================================================================
pub const FAT32BootSector = packed struct {
    boot_jmp: [3]u8,
    oem_name: [8]u8,
    bytes_per_sector: u16,
    sectors_per_cluster: u8,
    reserved_sector_count: u16,
    fat_count: u8,
    root_entry_count: u16,
    total_sectors_16: u16,
    media_type: u8,
    fat_size_16: u16,
    sectors_per_track: u16,
    head_count: u16,
    hidden_sectors: u32,
    total_sectors_32: u32,
    
    // FAT32 specific
    fat_size_32: u32,
    ext_flags: u16,
    fs_version: u16,
    root_cluster: u32,
    fs_info: u16,
    backup_boot_sector: u16,
    reserved: [12]u8,
    drive_number: u8,
    reserved1: u8,
    boot_signature: u8,
    volume_id: u32,
    volume_label: [11]u8,
    fs_type_label: [8]u8,
    boot_code: [420]u8,
    boot_signature_word: u16,
};

// ============================================================================
// FAT32 Directory Entry (from linux fs/fat/dir.h)
// ============================================================================
pub const FAT32DirEntry = packed struct {
    name: [8]u8,
    ext: [3]u8,
    attrs: u8,
    reserved: u8,
    create_time_cs: u8,
    create_time: u16,
    create_date: u16,
    access_date: u16,
    cluster_high: u16,
    modify_time: u16,
    modify_date: u16,
    cluster_low: u16,
    file_size: u32,

    pub const ATTR_READ_ONLY: u8 = 0x01;
    pub const ATTR_HIDDEN: u8 = 0x02;
    pub const ATTR_SYSTEM: u8 = 0x04;
    pub const ATTR_VOLUME_ID: u8 = 0x08;
    pub const ATTR_DIRECTORY: u8 = 0x10;
    pub const ATTR_ARCHIVE: u8 = 0x20;

    pub fn isDirectory(self: *const FAT32DirEntry) bool {
        return (self.attrs & ATTR_DIRECTORY) != 0;
    }

    pub fn isFile(self: *const FAT32DirEntry) bool {
        return (self.attrs & ATTR_DIRECTORY) == 0 and 
               (self.attrs & ATTR_VOLUME_ID) == 0;
    }

    pub fn getName(self: *const FAT32DirEntry) [11]u8 {
        var name: [11]u8 = undefined;
        @memcpy(name[0..8], &self.name);
        @memcpy(name[8..11], &self.ext);
        return name;
    }

    pub fn getCluster(self: *const FAT32DirEntry) u32 {
        return (@as(u32, self.cluster_high) << 16) | self.cluster_low;
    }
};

// ============================================================================
// Cluster Cache (from old files of EnochCore (mm/page_cache.h))
// ============================================================================
pub const ClusterCache = struct {
    cluster: u32,
    data: [BLOCK_SIZE * 8]u8, // Max cluster size
    valid: bool,
    last_access: u64,

    pub fn init() ClusterCache {
        return ClusterCache{
            .cluster = 0,
            .data = undefined,
            .valid = false,
            .last_access = 0,
        };
    }
};

// ============================================================================
// FAT32 File System Instance
// ============================================================================
pub const FAT32FS = struct {
    block_device: u8,
    boot_sector: FAT32BootSector,
    fat_start_sector: u32,
    data_start_sector: u32,
    bytes_per_cluster: u32,
    root_cluster: u32,
    total_clusters: u32,
    fat_entries: u32,
    
    // Cache
    cluster_cache: [CLUSTER_CACHE_SIZE]ClusterCache,
    cache_access_counter: u64,

    pub fn init(device: u8, boot: FAT32BootSector) FAT32FS {
        const bytes_per_cluster = @as(u32, boot.bytes_per_sector) * boot.sectors_per_cluster;
        const fat_start = boot.reserved_sector_count;
        const fat_size = boot.fat_size_32;
        const data_start = fat_start + (boot.fat_count * fat_size);
        
        var fs = FAT32FS{
            .block_device = device,
            .boot_sector = boot,
            .fat_start_sector = fat_start,
            .data_start_sector = data_start,
            .bytes_per_cluster = bytes_per_cluster,
            .root_cluster = boot.root_cluster,
            .total_clusters = 0, // Will be calculated
            .fat_entries = 0,
            .cluster_cache = undefined,
            .cache_access_counter = 0,
        };
        
        // Initialize cache
        var i: usize = 0;
        while (i < CLUSTER_CACHE_SIZE) : (i += 1) {
            fs.cluster_cache[i] = ClusterCache.init();
        }
        
        // Calculate total clusters
        fs.total_clusters = (boot.total_sectors_32 - data_start) / boot.sectors_per_cluster;
        fs.fat_entries = boot.fat_size_32 * (boot.bytes_per_sector / 4);
        
        return fs;
    }

    pub fn readCluster(self: *FAT32FS, cluster: u32) ?[]const u8 {
        if (cluster < 2 or cluster >= self.total_clusters) return null;
        
        // Check cache first
        if (self.findInCache(cluster)) |cache_idx| {
            self.cluster_cache[cache_idx].last_access = self.cache_access_counter;
            self.cache_access_counter += 1;
            return &self.cluster_cache[cache_idx].data;
        }
        
        // Read from disk (simulate)
        _ = self.data_start_sector + (cluster - 2) * self.boot_sector.sectors_per_cluster;
        
        // Find free cache slot or evict LRU
        const cache_idx = self.findFreeSlot() orelse self.evictLRU();
        if (cache_idx == null) return null;
        
        // Simulate disk read
        const cache = &self.cluster_cache[cache_idx.?];
        cache.cluster = cluster;
        cache.valid = true;
        cache.last_access = self.cache_access_counter;
        self.cache_access_counter += 1;
        
        // Fill with dummy data (in real implementation, read from disk)
        @memset(&cache.data, 0);
        
        return &cache.data;
    }

    fn findInCache(self: *FAT32FS, cluster: u32) ?usize {
        var i: usize = 0;
        while (i < CLUSTER_CACHE_SIZE) : (i += 1) {
            if (self.cluster_cache[i].valid and 
                self.cluster_cache[i].cluster == cluster) {
                return i;
            }
        }
        return null;
    }

    fn findFreeSlot(self: *FAT32FS) ?usize {
        var i: usize = 0;
        while (i < CLUSTER_CACHE_SIZE) : (i += 1) {
            if (!self.cluster_cache[i].valid) {
                return i;
            }
        }
        return null;
    }

    fn evictLRU(self: *FAT32FS) usize {
        var lru_idx: usize = 0;
        var lru_time: u64 = std.math.maxInt(u64);
        
        var i: usize = 0;
        while (i < CLUSTER_CACHE_SIZE) : (i += 1) {
            if (self.cluster_cache[i].valid and 
                self.cluster_cache[i].last_access < lru_time) {
                lru_time = self.cluster_cache[i].last_access;
                lru_idx = i;
            }
        }
        
        self.cluster_cache[lru_idx].valid = false;
        return lru_idx;
    }

    pub fn readFATEntry(self: *FAT32FS, cluster: u32) ?u32 {
        if (cluster >= self.fat_entries) return null;
        
        _ = self.fat_start_sector + (cluster * 4 / BLOCK_SIZE);
        
        // Simulate reading FAT entry
        // In real implementation, read from disk and return next cluster
        if (cluster == self.root_cluster) {
            return 0x0FFFFFFF; // End of chain
        }
        
        return 0x0FFFFFF8; // End of chain
    }

    pub fn findFile(self: *FAT32FS, path: []const u8) ?FAT32DirEntry {
        // Simple path parsing (only root directory for now)
        _ = path;
        
        // Read root directory clusters
        if (self.readCluster(self.root_cluster)) |root_data| {
            // Parse directory entries
            var i: usize = 0;
            while (i < root_data.len) : (i += BLOCK_SIZE * 8) {
                if (i + BLOCK_SIZE <= root_data.len) {
                    // Try to read as directory entry (skip for now)
                    // TODO: Compare names
                }
            }
        }
        
        return null;
    }

    pub fn readClusterChain(self: *FAT32FS, start_cluster: u32, buffer: []u8) !usize {
        var cluster = start_cluster;
        var offset: usize = 0;
        
        while (cluster >= 2 and cluster < 0x0FFFFFF8) {
            if (self.readCluster(cluster)) |data| {
                const to_copy = @min(data.len, buffer.len - offset);
                @memcpy(buffer[offset..offset + to_copy], data[0..to_copy]);
                offset += to_copy;
                
                if (offset >= buffer.len) break;
                
                // Get next cluster from FAT
                cluster = self.readFATEntry(cluster) orelse break;
            } else {
                break;
            }
        }
        
        return offset;
    }
};

// ============================================================================
// Global State
// ============================================================================
var fs_instances: [MAX_FAT32_FS]?*FAT32FS = undefined;
var fs_count: usize = 0;

// ============================================================================
// Public API
// ============================================================================
pub fn initialize() void {
    var i: usize = 0;
    while (i < MAX_FAT32_FS) : (i += 1) {
        fs_instances[i] = null;
    }
    fs_count = 0;
    tty.print("[FAT32] File system driver initialized\n", .{});
}

pub fn mountFat32(block_device: u8, sector: u32) !u32 {
    _ = sector;
    
    if (fs_count >= MAX_FAT32_FS) return error.TooManyFileSystems;
    
    // Read boot sector (simulate at address 0x00200000)
    const boot_sector_ptr: *const FAT32BootSector = @ptrFromInt(0x00200000);
    const boot_sector = boot_sector_ptr.*;
    
    // Validate FAT32
    if (boot_sector.fs_type_label[0] != 'F' or 
        boot_sector.fs_type_label[1] != 'A' or
        boot_sector.fs_type_label[2] != 'T') {
        return error.NotFAT32;
    }
    
    // Create FS instance
    const fs: *FAT32FS = @ptrFromInt(pmem.kmalloc(@sizeOf(FAT32FS)) catch return error.NoMemory);
    fs.* = FAT32FS.init(block_device, boot_sector);
    
    fs_instances[fs_count] = fs;
    fs_count += 1;
    
    tty.print("[FAT32] Mounted device {d}: {d} clusters, {d} bytes/cluster\n", .{
        block_device, fs.total_clusters, fs.bytes_per_cluster
    });
    
    return @intCast(fs_count - 1);
}

pub fn unmountFat32(fs_id: u32) !void {
    if (fs_id >= fs_count) return error.InvalidFileSystem;
    
    _ = fs_instances[fs_id]; // TODO: Free resources when implemented
    fs_instances[fs_id] = null;
    
    // Shift remaining instances
    var i = fs_id;
    while (i < fs_count - 1) : (i += 1) {
        fs_instances[i] = fs_instances[i + 1];
    }
    fs_count -= 1;
    
    tty.print("[FAT32] Unmounted fs_id={d}\n", .{fs_id});
}

pub fn readFile(fs_id: u32, path: []const u8, buffer: []u8) !usize {
    if (fs_id >= fs_count) return error.InvalidFileSystem;
    
    const fs = fs_instances[fs_id].?;
    
    // Find file
    if (fs.findFile(path)) |_| {
        _ = buffer;
        // TODO: Read file content
        return 0;
    }
    
    return error.FileNotFound;
}

pub fn listDirectory(fs_id: u32, path: []const u8) []FAT32DirEntry {
    _ = fs_id;
    _ = path;
    // TODO: Implement directory listing
    return &[_]FAT32DirEntry{};
}

pub fn createFile(fs_id: u32, path: []const u8) !void {
    _ = fs_id;
    _ = path;
    // TODO: Implement file creation
    return error.NotImplemented;
}

pub fn deleteFile(fs_id: u32, path: []const u8) !void {
    _ = fs_id;
    _ = path;
    // TODO: Implement file deletion
    return error.NotImplemented;
}

// ============================================================================
// Debug
// ============================================================================
pub fn dumpFSInfo(fs_id: u32) void {
    if (fs_id >= fs_count) return;
    
    const fs = fs_instances[fs_id].?;
    tty.print("[FAT32] FS Info (id={d}):\n", .{fs_id});
    tty.print("  Device: {d}\n", .{fs.block_device});
    tty.print("  Bytes/sector: {d}\n", .{fs.boot_sector.bytes_per_sector});
    tty.print("  Sectors/cluster: {d}\n", .{fs.boot_sector.sectors_per_cluster});
    tty.print("  Total clusters: {d}\n", .{fs.total_clusters});
    tty.print("  Root cluster: {d}\n", .{fs.root_cluster});
    tty.print("  Cache: {d}/{d} entries\n", .{
        CLUSTER_CACHE_SIZE, CLUSTER_CACHE_SIZE
    });
}