const std = @import("std");
const tty = @import("tty.zig");

pub const Inode = struct {
    inode_number: u32,
    mode: Mode,
    uid: u16,
    gid: u16,
    size: u64,
    atime: u32,
    mtime: u32,
    ctime: u32,
    blocks: usize,
    private_data: ?*anyopaque,

    pub const Mode = packed struct {
        type: enum(u3) {
            unknown = 0,
            regular = 1,
            directory = 2,
            symlink = 3,
            char_device = 4,
            block_device = 5,
            fifo = 6,
            socket = 7,
        },
        permissions: u9,
        reserved: u20 = 0,

        pub fn isDir(self: Mode) bool {
            return self.type == .directory;
        }

        pub fn isRegular(self: Mode) bool {
            return self.type == .regular;
        }

        pub fn isSymlink(self: Mode) bool {
            return self.type == .symlink;
        }

        pub fn isDevice(self: Mode) bool {
            return self.type == .char_device or self.type == .block_device;
        }
    };

    pub fn read(self: *const Inode, offset: usize, buf: []u8) !usize {
        _ = self;
        _ = offset;
        _ = buf;
        return error.NotImplemented;
    }

    pub fn write(self: *const Inode, offset: usize, buf: []const u8) !usize {
        _ = self;
        _ = offset;
        _ = buf;
        return error.NotImplemented;
    }

    pub fn list(self: *const Inode) ![]const Inode {
        _ = self;
        return error.NotImplemented;
    }
};

pub const File = struct {
    inode: *Inode,
    offset: usize,
    flags: u32,
    ref_count: usize,

    pub const FLAGS = struct {
        pub const RDONLY: u32 = 0x00001;
        pub const WRONLY: u32 = 0x00002;
        pub const RDWR: u32 = 0x00003;
        pub const APPEND: u32 = 0x00400;
        pub const CREATE: u32 = 0x00200;
        pub const TRUNCATE: u32 = 0x00400;
    };

    pub fn read(self: *File, buf: []u8) !usize {
        const bytes_read = try self.inode.read(self.offset, buf);
        self.offset += bytes_read;
        return bytes_read;
    }

    pub fn write(self: *File, buf: []const u8) !usize {
        const bytes_written = try self.inode.write(self.offset, buf);
        self.offset += bytes_written;
        return bytes_written;
    }

    pub fn seek(self: *File, offset: usize, whence: enum(u8) {
        set_start = 0,
        set_current = 1,
        set_end = 2,
    }) usize {
        self.offset = switch (whence) {
            .set_start => offset,
            .set_current => @max(0, @as(i64, @intCast(self.offset)) + @as(i64, @intCast(offset))),
            .set_end => @max(0, @as(i64, @intCast(self.inode.size)) + @as(i64, @intCast(offset))),
        };
        return self.offset;
    }
};

pub const SuperBlock = struct {
    block_size: usize,
    total_blocks: u64,
    free_blocks: u64,
    total_inodes: u32,
    free_inodes: u32,
    mount_point: []const u8,
    private_data: ?*anyopaque,

    pub fn sync(self: *SuperBlock) !void {
        _ = self;
    }
};

pub const DirectoryEntry = struct {
    name: []const u8,
    inode_number: u32,
    entry_type: enum(u8) {
        unknown = 0,
        regular = 1,
        directory = 2,
        symlink = 3,
        char_device = 4,
        block_device = 5,
        fifo = 6,
        socket = 7,
    },
};

const MAX_PATH = 512;
const MAX_MOUNT_POINTS = 16;

var mount_points: [MAX_MOUNT_POINTS]MountPoint = undefined;
var mount_count: usize = 0;

const MountPoint = struct {
    path: []const u8,
    superblock: *SuperBlock,
};

pub fn mount(superblock: *SuperBlock, path: []const u8) !void {
    if (mount_count >= MAX_MOUNT_POINTS) {
        return error.TooManyMountPoints;
    }

    mount_points[mount_count] = MountPoint{
        .path = path,
        .superblock = superblock,
    };
    mount_count += 1;

    tty.print("[VFS] Mounted {s}\n", .{path});
}

pub fn unmount(path: []const u8) !void {
    var i: usize = 0;
    while (i < mount_count) : (i += 1) {
        if (std.mem.eql(u8, mount_points[i].path, path)) {
            // TODO: Sync and cleanup
            memmove(&mount_points[i], &mount_points[i + 1], @sizeOf(MountPoint) * (mount_count - i - 1));
            mount_count -= 1;
            return;
        }
    }
    return error.NotFound;
}

fn memmove(dest: *anyopaque, src: *const anyopaque, n: usize) void {
    const d: [*]u8 = @ptrCast(dest);
    const s: [*]const u8 = @ptrCast(src);

    if (d < s) {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            d[i] = s[i];
        }
    } else {
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            d[i] = s[i];
        }
    }
}

pub fn open(path: []const u8, flags: u32) !*File {
    _ = path;
    _ = flags;
    return error.NotImplemented;
}

pub fn close(file: *File) void {
    _ = file;
}

pub fn read(file: *File, buf: []u8) !usize {
    return file.read(buf);
}

pub fn write(file: *File, buf: []const u8) !usize {
    return file.write(buf);
}

pub fn mkdir(path: []const u8) !void {
    _ = path;
    return error.NotImplemented;
}

pub fn rmdir(path: []const u8) !void {
    _ = path;
    return error.NotImplemented;
}

pub fn unlink(path: []const u8) !void {
    _ = path;
    return error.NotImplemented;
}

pub fn stat(path: []const u8, buf: *Stat) !void {
    _ = path;
    _ = buf;
    return error.NotImplemented;
}

pub const Stat = extern struct {
    dev: u64,
    ino: u64,
    mode: u32,
    nlink: u32,
    uid: u32,
    gid: u32,
    rdev: u64,
    size: u64,
    blksize: u32,
    blocks: u64,
    atime: u64,
    mtime: u64,
    ctime: u64,
};

pub fn initialize() void {
    var i: usize = 0;
    while (i < MAX_MOUNT_POINTS) : (i += 1) {
        mount_points[i] = MountPoint{
            .path = "",
            .superblock = undefined,
        };
    }
    mount_count = 0;
    tty.print("[VFS] Initialized\n", .{});
}
