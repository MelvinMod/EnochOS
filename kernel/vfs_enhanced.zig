//! Enhanced VFS - Virtual File System
//! Based on darwin-xnu bsd/vfs and linux fs components

const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");
const buddy = @import("buddy.zig");

const MAX_VNODES = 1024;
const MAX_MOUNTS = 16;
const MAX_PATH_LEN = 256;
const MAX_NAME_LEN = 256;
const VNODE_CACHE_SIZE = 64;

// ============================================================================
// VFS File Types (from darwin-xnu bsd/sys/vnode.h)
// ============================================================================
pub const VNodeType = enum(u8) {
    VNON = 0,       // Non-existent
    VREG = 1,       // Regular file
    VDIR = 2,       // Directory
    VBLK = 3,       // Block device
    VCHR = 4,       // Character device
    VLNK = 5,       // Symbolic link
    VSOCK = 6,      // Socket
    VFIFO = 7,      // FIFO
    VBAD = 8,       // Bad node
};

// ============================================================================
// VFS File Flags
// ============================================================================
pub const VNodeFlags = packed struct {
    is_root: bool = false,
    is_mountpoint: bool = false,
    is_stale: bool = false,
    is_locked: bool = false,
    reserved: u29 = 0,
};

// ============================================================================
// VFS Times (from darwin-xnu bsd/sys/vnode.h)
// ============================================================================
pub const VTimes = packed struct {
    atime: u64,     // Last access time
    mtime: u64,     // Last modification time
    ctime: u64,     // Last status change time
    btime: u64,     // Birth time
};

// ============================================================================
// VFS Attributes (from darwin-xnu bsd/sys/vnode.h)
// ============================================================================
pub const VAttr = packed struct {
    mode: u32,      // File mode (permissions + type)
    uid: u32,       // Owner user ID
    gid: u32,       // Owner group ID
    size: u64,      // File size in bytes
    nlink: u32,     // Number of hard links
    vtype: VNodeType,
    flags: VNodeFlags,
    times: VTimes,
    
    pub const MODE_MASK: u32 = 0o7777;
    pub const MODE_DIR: u32 = 0o040000;
    pub const MODE_REG: u32 = 0o100000;
    pub const MODE_LNK: u32 = 0o120000;
    pub const MODE_BLK: u32 = 0o060000;
    pub const MODE_CHR: u32 = 0o020000;
    pub const MODE_FIFO: u32 = 0o010000;
    
    pub const PERM_R: u32 = 0o400;
    pub const PERM_W: u32 = 0o200;
    pub const PERM_X: u32 = 0o100;
    pub const PERM_RU: u32 = 0o400;
    pub const PERM_WU: u32 = 0o200;
    pub const PERM_XU: u32 = 0o100;
    pub const PERM_RG: u32 = 0o040;
    pub const PERM_WG: u32 = 0o020;
    pub const PERM_XG: u32 = 0o010;
    pub const PERM_RO: u32 = 0o004;
    pub const PERM_WO: u32 = 0o002;
    pub const PERM_XO: u32 = 0o001;
};

// ============================================================================
// VFS Offset Type
// ============================================================================
pub const OffT = u64;

// ============================================================================
// VNode (from darwin-xnu bsd/sys/vnode.h)
// Core VFS structure representing an open file/directory
// ============================================================================
pub const VNode = struct {
    vnode_id: u32,
    vtype: VNodeType,
    flags: VNodeFlags,
    attr: VAttr,
    
    // File position for sequential access
    offset: OffT,
    
    // Parent vnode (for directories)
    parent: ?*VNode,
    
    // Children (for directories)
    children: [32]*VNode,
    child_count: usize,
    
    // Backend data (filesystem-specific)
    data: ?*anyopaque,
    
    // Reference counting
    reference_count: u32,
    
    pub fn init(id: u32, vtype: VNodeType, attr: VAttr) VNode {
        return VNode{
            .vnode_id = id,
            .vtype = vtype,
            .flags = attr.flags,
            .attr = attr,
            .offset = 0,
            .parent = null,
            .children = undefined,
            .child_count = 0,
            .data = null,
            .reference_count = 1,
        };
    }
    
    pub fn acquire(self: *VNode) void {
        self.reference_count += 1;
    }
    
    pub fn release(self: *VNode) void {
        self.reference_count -= 1;
        if (self.reference_count == 0) {
            // VNode can be freed
        }
    }
    
    pub fn isDirectory(self: *const VNode) bool {
        return self.vtype == .VDIR;
    }
    
    pub fn isRegularFile(self: *const VNode) bool {
        return self.vtype == .VREG;
    }
    
    pub fn isSymlink(self: *const VNode) bool {
        return self.vtype == .VLNK;
    }
    
    pub fn hasPermission(self: *const VNode, mode: u32) bool {
        // Simplified permission check
        _ = mode;
        return true;
    }
};

// ============================================================================
// VNode Cache (from linux fs/dcache.c)
//! LRU cache for frequently accessed vnodes
// ============================================================================
pub const VNodeCache = struct {
    vnodes: [VNODE_CACHE_SIZE]?*VNode,
    access_order: [VNODE_CACHE_SIZE]usize,
    head: usize,
    tail: usize,
    count: usize,
    
    pub fn init() VNodeCache {
        var cache = VNodeCache{
            .vnodes = undefined,
            .access_order = undefined,
            .head = 0,
            .tail = 0,
            .count = 0,
        };
        @memset(&cache.vnodes, null);
        @memset(&cache.access_order, 0);
        return cache;
    }
    
    pub fn lookup(self: *VNodeCache, vnode_id: u32) ?*VNode {
        _ = vnode_id;
        // TODO: Implement cache lookup
        return null;
    }
    
    pub fn insert(self: *VNodeCache, vnode: *VNode) void {
        // Find free slot or evict LRU
        var i: usize = 0;
        while (i < VNODE_CACHE_SIZE) : (i += 1) {
            if (self.vnodes[i] == null) {
                self.vnodes[i] = vnode;
                self.access_order[i] = self.count;
                self.count += 1;
                return;
            }
        }
        // Evict LRU (simplified)
        self.vnodes[self.head] = vnode;
        self.head = (self.head + 1) % VNODE_CACHE_SIZE;
    }
    
    pub fn remove(self: *VNodeCache, vnode: *VNode) void {
        _ = vnode;
        // TODO: Implement cache removal
    }
};

// ============================================================================
// Mount Point (from darwin-xnu bsd/sys/mount.h)
// ============================================================================
pub const MountPoint = struct {
    mount_id: u32,
    device: u8,
    root_vnode: *VNode,
    fs_type: []const u8,
    mount_path: [MAX_PATH_LEN]u8,
    mount_path_len: usize,
    flags: u32,
    
    pub const MNT_RDONLY: u32 = 0x00000001;
    pub const MNT_WRITER: u32 = 0x00000002;
    pub const MNT_NOEXEC: u32 = 0x00000004;
    pub const MNT_NOSUID: u32 = 0x00000008;
    
    pub fn init(id: u32, device: u8, root: *VNode, fs_type: []const u8) MountPoint {
        var mp = MountPoint{
            .mount_id = id,
            .device = device,
            .root_vnode = root,
            .fs_type = fs_type,
            .mount_path = undefined,
            .mount_path_len = 0,
            .flags = MNT_RDONLY,
        };
        @memset(&mp.mount_path, 0);
        return mp;
    }
};

// ============================================================================
// File Descriptor (from darwin-xnu bsd/sys/file.h)
// ============================================================================
pub const FileDescriptor = struct {
    fd_number: u32,
    vnode: *VNode,
    flags: u32,
    offset: OffT,
    
    pub const FD_CLOEXEC: u32 = 0x01;
    pub const FD_APPEND: u32 = 0x02;
    pub const FD_NONBLOCK: u32 = 0x04;
    
    pub const MODE_RDONLY: u32 = 0;
    pub const MODE_WRONLY: u32 = 1;
    pub const MODE_RDWR: u32 = 2;
    
    pub fn init(num: u32, vn: *VNode, mode: u32) FileDescriptor {
        return FileDescriptor{
            .fd_number = num,
            .vnode = vn,
            .flags = 0,
            .offset = 0,
        };
    }
};

// ============================================================================
// Directory Entry (from linux fs/readdir.c)
// ============================================================================
pub const DirEntry = struct {
    inode: u32,
    name: [MAX_NAME_LEN]u8,
    name_len: usize,
    type: u8,
    next_offset: u32,
};

// ============================================================================
// Global VFS State
// ============================================================================
var vnodes: [MAX_VNODES]?*VNode = undefined;
var vnode_count: usize = 0;
var next_vnode_id: u32 = 1;

var mounts: [MAX_MOUNTS]?*MountPoint = undefined;
var mount_count: usize = 0;
var next_mount_id: u32 = 1;

var file_descriptors: [256]?*FileDescriptor = undefined;
var fd_count: usize = 0;

var vnode_cache: VNodeCache = undefined;

// ============================================================================
// Initialization
// ============================================================================
pub fn initialize() void {
    var i: usize = 0;
    while (i < MAX_VNODES) : (i += 1) {
        vnodes[i] = null;
    }
    while (i < MAX_MOUNTS) : (i += 1) {
        mounts[i] = null;
    }
    while (i < 256) : (i += 1) {
        file_descriptors[i] = null;
    }
    
    vnode_count = 0;
    mount_count = 0;
    fd_count = 0;
    next_vnode_id = 1;
    next_mount_id = 1;
    
    vnode_cache = VNodeCache.init();
    
    tty.print("[VFS] Virtual File System initialized\n", .{});
    tty.print("[VFS] Vnodes: {d}, Mounts: {d}, FDs: {d}\n", .{
        MAX_VNODES, MAX_MOUNTS, 256
    });
}

// ============================================================================
// VNode Operations
// ============================================================================
fn createVNode(vtype: VNodeType, attr: VAttr) ?*VNode {
    if (vnode_count >= MAX_VNODES) return null;
    
    var i: usize = 0;
    while (i < MAX_VNODES) : (i += 1) {
        if (vnodes[i] == null) {
            const vn: *VNode = @ptrFromInt(pmem.kmalloc(@sizeOf(VNode)) catch return null);
            vn.* = VNode.init(next_vnode_id, vtype, attr);
            vnodes[i] = vn;
            vnode_count += 1;
            next_vnode_id += 1;
            
            vnode_cache.insert(vn);
            return vn;
        }
    }
    return null;
}

pub fn releaseVNode(vn: *VNode) void {
    // Find and nullify
    var i: usize = 0;
    while (i < MAX_VNODES) : (i += 1) {
        if (vnodes[i] == vn) {
            vnodes[i] = null;
            vnode_count -= 1;
            break;
        }
    }
    vnode_cache.remove(vn);
}

// ============================================================================
// Path Resolution (from darwin-xnu bsd/vfs/vfs_lookup.c)
// ============================================================================
pub fn lookupPath(path: []const u8) !*VNode {
    if (path.len == 0 or path.len > MAX_PATH_LEN) {
        return error.InvalidPath;
    }
    
    // Find root vnode (first mount point)
    if (mount_count == 0) {
        return error.NoMountpoints;
    }
    
    var current = mounts[0].?.root_vnode;
    
    // Parse path components
    var pos: usize = 0;
    while (pos < path.len) {
        // Skip leading slashes
        while (pos < path.len and path[pos] == '/') {
            pos += 1;
        }
        if (pos >= path.len) break;
        
        // Extract component
        const start = pos;
        while (pos < path.len and path[pos] != '/') {
            pos += 1;
        }
        const name = path[start..pos];
        
        // Look up in current directory
        if (current.isDirectory()) {
            var found: ?*VNode = null;
            var i: usize = 0;
            while (i < current.child_count) : (i += 1) {
                const child = current.children[i];
                if (std.mem.eql(u8, child.name[0..child.name_len], name)) {
                    found = child;
                    break;
                }
            }
            
            if (found) |vn| {
                current = vn;
            } else {
                return error.FileNotFound;
            }
        } else {
            return error.NotADirectory;
        }
    }
    
    return current;
}

// ============================================================================
// Mount Operations
// ============================================================================
pub fn mount(device: u8, path: []const u8, fs_type: []const u8, root_vnode: *VNode) !u32 {
    if (mount_count >= MAX_MOUNTS) return error.TooManyMounts;
    
    var i: usize = 0;
    while (i < MAX_MOUNTS) : (i += 1) {
        if (mounts[i] == null) {
            const mp: *MountPoint = @ptrFromInt(
                pmem.kmalloc(@sizeOf(MountPoint)) catch return error.NoMemory
            );
            mp.* = MountPoint.init(next_mount_id, device, root_vnode, fs_type);
            
            // Copy mount path
            mp.mount_path_len = @min(path.len, MAX_PATH_LEN - 1);
            @memcpy(mp.mount_path[0..mp.mount_path_len], path[0..mp.mount_path_len]);
            
            mounts[i] = mp;
            mount_count += 1;
            next_mount_id += 1;
            
            tty.print("[VFS] Mounted {s} on {s} (id={d})\n", .{
                fs_type, path[0..path.len], mp.mount_id
            });
            
            return mp.mount_id;
        }
    }
    return error.TooManyMounts;
}

pub fn unmount(mount_id: u32) !void {
    var i: usize = 0;
    while (i < MAX_MOUNTS) : (i += 1) {
        if (mounts[i] != null and mounts[i].?.mount_id == mount_id) {
            // TODO: Release resources
            mounts[i] = null;
            mount_count -= 1;
            
            tty.print("[VFS] Unmounted mount_id={d}\n", .{mount_id});
            return;
        }
    }
    return error.InvalidMount;
}

pub fn getMountByPath(path: []const u8) ?*MountPoint {
    var i: usize = 0;
    while (i < MAX_MOUNTS) : (i += 1) {
        if (mounts[i]) |mp| {
            if (std.mem.eql(u8, mp.mount_path[0..mp.mount_path_len], path)) {
                return mp;
            }
        }
    }
    return null;
}

// ============================================================================
// File Descriptor Operations
// ============================================================================
pub fn openFile(path: []const u8, mode: u32) !u32 {
    const vn = try lookupPath(path);
    
    // Create file descriptor
    if (fd_count >= 256) return error.TooManyOpenFiles;
    
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (file_descriptors[i] == null) {
            const fd: *FileDescriptor = @ptrFromInt(
                pmem.kmalloc(@sizeOf(FileDescriptor)) catch return error.NoMemory
            );
            fd.* = FileDescriptor.init(@intCast(i), vn, mode);
            file_descriptors[i] = fd;
            fd_count += 1;
            
            tty.print("[VFS] Opened {s} (fd={d})\n", .{ path, fd.fd_number });
            return fd.fd_number;
        }
    }
    return error.TooManyOpenFiles;
}

pub fn closeFile(fd_number: u32) !void {
    if (fd_number >= 256 or file_descriptors[fd_number] == null) {
        return error.InvalidFileDescriptor;
    }
    
    file_descriptors[fd_number] = null;
    fd_count -= 1;
}

pub fn readFile(fd_number: u32, buffer: []u8) !usize {
    if (fd_number >= 256 or file_descriptors[fd_number] == null) {
        return error.InvalidFileDescriptor;
    }
    
    const fd = file_descriptors[fd_number].?;
    const vn = fd.vnode;
    
    if (!vn.isRegularFile()) {
        return error.NotAFile;
    }
    
    // TODO: Read from vnode data
    _ = buffer;
    return 0;
}

pub fn writeFile(fd_number: u32, data: []const u8) !usize {
    if (fd_number >= 256 or file_descriptors[fd_number] == null) {
        return error.InvalidFileDescriptor;
    }
    
    const fd = file_descriptors[fd_number].?;
    const vn = fd.vnode;
    
    if (!vn.isRegularFile()) {
        return error.NotAFile;
    }
    
    // TODO: Write to vnode data
    _ = data;
    return data.len;
}

pub fn seekFile(fd_number: u32, offset: OffT, whence: u32) !OffT {
    _ = whence;
    if (fd_number >= 256 or file_descriptors[fd_number] == null) {
        return error.InvalidFileDescriptor;
    }
    
    const fd = file_descriptors[fd_number].?;
    fd.offset = offset;
    return offset;
}

// ============================================================================
// Directory Operations
// ============================================================================
pub fn createDirectory(path: []const u8) !void {
    const attr: VAttr = .{
        .mode = VAttr.MODE_DIR | VAttr.PERM_RU | VAttr.PERM_WU | VAttr.PERM_XU,
        .uid = 0,
        .gid = 0,
        .size = 0,
        .nlink = 2, // . and ..
        .vtype = .VDIR,
        .flags = .{},
        .times = .{ .atime = 0, .mtime = 0, .ctime = 0, .btime = 0 },
    };
    
    const vn = createVNode(.VDIR, attr) orelse return error.NoMemory;
    
    // TODO: Add to parent directory
    _ = path;
    tty.print("[VFS] Created directory {s}\n", .{path});
}

pub fn createFile(path: []const u8) !void {
    const attr: VAttr = .{
        .mode = VAttr.MODE_REG | VAttr.PERM_RU | VAttr.PERM_WU,
        .uid = 0,
        .gid = 0,
        .size = 0,
        .nlink = 1,
        .vtype = .VREG,
        .flags = .{},
        .times = .{ .atime = 0, .mtime = 0, .ctime = 0, .btime = 0 },
    };
    
    const vn = createVNode(.VREG, attr) orelse return error.NoMemory;
    
    // TODO: Add to parent directory
    _ = path;
    tty.print("[VFS] Created file {s}\n", .{path});
}

pub fn deleteFile(path: []const u8) !void {
    const vn = try lookupPath(path);
    
    if (!vn.isRegularFile()) {
        return error.NotAFile;
    }
    
    // TODO: Remove from parent directory and free vnode
    releaseVNode(vn);
    tty.print("[VFS] Deleted file {s}\n", .{path});
}

// ============================================================================
// Debug
// ============================================================================
pub fn dumpVNodes() void {
    tty.print("[VFS] VNode Table:\n", .{});
    var i: usize = 0;
    while (i < MAX_VNODES) : (i += 1) {
        if (vnodes[i]) |vn| {
            tty.print("  VNode {d}: type={d}, refs={d}\n", .{
                vn.vnode_id, @intFromEnum(vn.vtype), vn.reference_count
            });
        }
    }
}

pub fn dumpMounts() void {
    tty.print("[VFS] Mount Points:\n", .{});
    var i: usize = 0;
    while (i < MAX_MOUNTS) : (i += 1) {
        if (mounts[i]) |mp| {
            tty.print("  Mount {d}: {s} on {s}\n", .{
                mp.mount_id, mp.fs_type, mp.mount_path[0..mp.mount_path_len]
            });
        }
    }
}