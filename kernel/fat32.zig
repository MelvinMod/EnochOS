const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");
const vfs = @import("vfs.zig");

const CLUSTER_SIZE = 4096;
const SECTOR_SIZE = 512;
const ROOT_DIR_CLUSTER = 2;

const FAT32Header = packed struct {
    boot_jump: [3]u8,
    oem_name: [8]u8,
    bytes_per_sector: u16,
    sectors_per_cluster: u8,
    reserved_sector_count: u16,
    fat_count: u8,
    root_entry_count: u16,
    total_sectors_16: u16,
    media_type: u8,
    sectors_per_fat_16: u16,
    sectors_per_track: u16,
    head_count: u16,
    hidden_sectors: u32,
    total_sectors_32: u32,
    sectors_per_fat_32: u32,
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
    fs_type: [8]u8,
};

const DirectoryEntry = packed struct {
    name: [11]u8,
    attributes: u8,
    reserved: u8,
    create_time_tenths: u8,
    create_time: u16,
    create_date: u16,
    access_date: u16,
    high_cluster: u16,
    modify_time: u16,
    modify_date: u16,
    low_cluster: u16,
    file_size: u32,
};

const FAT32SuperBlock = struct {
    header: *FAT32Header,
    fat_start: u32,
    data_start: u32,
    fat_size: u32,
    cluster_count: u32,
    root_cluster: u32,
    fat_cache: [4096]u8,

    pub fn init(boot_sector: *const FAT32Header) FAT32SuperBlock {
        const sectors_per_cluster: u32 = boot_sector.sectors_per_cluster;
        const fat_start = boot_sector.reserved_sector_count;
        const fat_size = boot_sector.sectors_per_fat_32;
        const data_start = fat_start + (fat_size * @as(u32, boot_sector.fat_count));
        const total_sectors = boot_sector.total_sectors_32;
        const data_sectors = total_sectors - data_start;
        const cluster_count = data_sectors / sectors_per_cluster;

        return FAT32SuperBlock{
            .header = boot_sector,
            .fat_start = fat_start,
            .data_start = data_start,
            .fat_size = fat_size,
            .cluster_count = cluster_count,
            .root_cluster = boot_sector.root_cluster,
            .fat_cache = undefined,
        };
    }

    pub fn clusterToSector(self: *const FAT32SuperBlock, cluster: u32) u32 {
        return self.data_start + (cluster - 2) * self.header.sectors_per_cluster;
    }

    pub fn getClusterFat(self: *FAT32SuperBlock, cluster: u32) ?u32 {
        const offset = cluster * 4;
        const fat_sector = self.fat_start + (offset / SECTOR_SIZE);
        const sector_offset = offset % SECTOR_SIZE;
        
        _ = fat_sector;
        _ = sector_offset;
        
        return null;
    }

    pub fn nextCluster(self: *FAT32SuperBlock, cluster: u32) ?u32 {
        if (self.getClusterFat(cluster)) |fat_entry| {
            return fat_entry & 0x0FFFFFFF;
        }
        return null;
    }
};

const FAT32Inode = struct {
    cluster: u32,
    size: u32,
    is_directory: bool,
    name: [11]u8,
    sb: *FAT32SuperBlock,

    pub fn read(self: *const FAT32Inode, offset: usize, buf: []u8) !usize {
        if (offset >= self.size) return 0;
        
        const bytes_to_read = @min(buf.len, self.size - @as(usize, @intCast(offset)));
        var remaining = bytes_to_read;
        var current_offset = offset;
        var current_cluster = self.cluster;
        
        while (remaining > 0) {
            const cluster_offset = current_offset % CLUSTER_SIZE;
            const bytes_in_cluster = @min(remaining, CLUSTER_SIZE - cluster_offset);
            
            const sector = self.sb.clusterToSector(current_cluster);
            const data: [*]u8 = @ptrFromInt(0x00200000 + sector * SECTOR_SIZE);
            
            var i: usize = 0;
            while (i < bytes_in_cluster and i < buf.len) : (i += 1) {
                buf[i] = data[cluster_offset + i];
            }
            
            buf = buf[bytes_in_cluster..];
            remaining -= bytes_in_cluster;
            current_offset += bytes_in_cluster;
            
            if (remaining > 0) {
                if (self.sb.nextCluster(current_cluster)) |next| {
                    current_cluster = next;
                } else {
                    break;
                }
            }
        }
        
        return bytes_to_read;
    }

    pub fn list(self: *const FAT32Inode) ![]DirectoryEntry {
        _ = self;
        return error.NotImplemented;
    }
};

const FAT32FS = struct {
    sb: *FAT32SuperBlock,
    root_inode: FAT32Inode,
    block_device: u8,

    pub fn init(block_device: u8, boot_sector: *const FAT32Header) ?FAT32FS {
        const sb: *FAT32SuperBlock = @ptrFromInt(pmem.kmalloc(@sizeOf(FAT32SuperBlock)).?);
        sb.* = FAT32SuperBlock.init(boot_sector);
        
        const root_inode = FAT32Inode{
            .cluster = sb.root_cluster,
            .size = 0,
            .is_directory = true,
            .name = [11]u8{ ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
            .sb = sb,
        };
        
        return FAT32FS{
            .sb = sb,
            .root_inode = root_inode,
            .block_device = block_device,
        };
    }

    pub fn openFile(self: *FAT32FS, path: []const u8) ?*FAT32Inode {
        _ = self;
        _ = path;
        return null;
    }
};

var fat32_instances: [4]?FAT32FS = .{null} ** 4;
var fat32_count: usize = 0;

pub fn mountFat32(block_device: u8, _: u32) void {
    const boot_sector: *const FAT32Header = @ptrFromInt(0x00200000);
    
    if (fat32_count < 4) {
        if (fat32_instances[fat32_count]) |*fs| {
            fs.* = FAT32FS.init(block_device, boot_sector) orelse return;
            fat32_count += 1;
            tty.print("[FAT32] Mounted device {d}\n", .{block_device});
        }
    }
}

pub fn readFat32File(fs_index: usize, cluster: u32, offset: usize, buf: []u8) !usize {
    if (fs_index >= fat32_count) return error.InvalidFileSystem;
    if (fat32_instances[fs_index]) |fs| {
        const inode = FAT32Inode{
            .cluster = cluster,
            .size = 0,
            .is_directory = false,
            .name = [11]u8{ ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
            .sb = fs.sb,
        };
        return inode.read(offset, buf);
    }
    return error.InvalidFileSystem;
}

pub fn scanDirectory(fs_index: usize, cluster: u32) !void {
    if (fs_index >= fat32_count) return error.InvalidFileSystem;
    if (fat32_instances[fs_index]) |fs| {
        _ = fs;
        tty.print("[FAT32] Scanning cluster {d}\n", .{cluster});
    }
}

pub fn readBootSector(block_device: u8, sector: u32) *const FAT32Header {
    _ = block_device;
    _ = sector;
    return @ptrFromInt(0x00200000);
}