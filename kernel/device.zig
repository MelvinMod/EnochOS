const tty = @import("tty.zig");
const x86 = @import("x86.zig");
const idt = @import("idt.zig");

const MAX_DEVICES = 32;

pub const DeviceType = enum(u8) {
    block = 0,
    char_device = 1,
    network = 2,
    misc = 3,
};

pub const Device = struct {
    major: u8,
    minor: u8,
    dev_type: DeviceType,
    name: []const u8,
    open: ?*const fn (*Device) void,
    close: ?*const fn (*Device) void,
    read: ?*const fn (*Device, []u8) usize,
    write: ?*const fn (*Device, []const u8) usize,
    ioctl: ?*const fn (*Device, u32, *anyopaque) void,
    private: ?*anyopaque,

    pub fn init(major: u8, dev_type: DeviceType, name: []const u8) Device {
        return Device{
            .major = major,
            .minor = 0,
            .dev_type = dev_type,
            .name = name,
            .open = null,
            .close = null,
            .read = null,
            .write = null,
            .ioctl = null,
            .private = null,
        };
    }
};

var devices: [MAX_DEVICES]Device = undefined;
var device_count: usize = 0;

pub fn initialize() void {
    var i: usize = 0;
    while (i < MAX_DEVICES) : (i += 1) {
        devices[i] = Device.init(0, .misc, "");
    }
    device_count = 0;
    tty.print("[Device] Initialized\n", .{});
}

pub fn registerDevice(dev: *Device) !void {
    if (device_count >= MAX_DEVICES) {
        return error.NoSpaceLeft;
    }
    devices[device_count] = dev.*;
    device_count += 1;
    tty.print("[Device] Registered {s} (major={d})\n", .{ dev.name, dev.major });
}

pub fn unregisterDevice(major: u8) void {
    var i: usize = 0;
    while (i < device_count) : (i += 1) {
        if (devices[i].major == major) {
            if (devices[i].close) |close_fn| {
                close_fn(&devices[i]);
            }
            var j: usize = i;
            while (j < device_count - 1) : (j += 1) {
                devices[j] = devices[j + 1];
            }
            device_count -= 1;
            return;
        }
    }
}

pub fn getDevice(major: u8, minor: u8) ?*Device {
    var i: usize = 0;
    while (i < device_count) : (i += 1) {
        if (devices[i].major == major and devices[i].minor == minor) {
            return &devices[i];
        }
    }
    return null;
}

pub fn openDevice(major: u8, minor: u8) !void {
    if (getDevice(major, minor)) |dev| {
        if (dev.open) |open_fn| {
            try open_fn(dev);
        }
    } else {
        return error.DeviceNotFound;
    }
}

pub fn closeDevice(major: u8, minor: u8) void {
    if (getDevice(major, minor)) |dev| {
        if (dev.close) |close_fn| {
            close_fn(dev);
        }
    }
}

pub fn readDevice(major: u8, minor: u8, buf: []u8) !usize {
    if (getDevice(major, minor)) |dev| {
        if (dev.read) |read_fn| {
            return read_fn(dev, buf);
        }
        return error.NotSupported;
    }
    return error.DeviceNotFound;
}

pub fn writeDevice(major: u8, minor: u8, buf: []const u8) !usize {
    if (getDevice(major, minor)) |dev| {
        if (dev.write) |write_fn| {
            return write_fn(dev, buf);
        }
        return error.NotSupported;
    }
    return error.DeviceNotFound;
}

const NullDevice = struct {
    name: []const u8 = "/dev/null",
    
    fn nullRead(_: *Device, buf: []u8) usize {
        _ = buf;
        return 0;
    }
    
    fn nullWrite(_: *Device, buf: []const u8) usize {
        return buf.len;
    }
};

const ZeroDevice = struct {
    name: []const u8 = "/dev/zero",
    
    fn zeroRead(_: *Device, buf: []u8) usize {
        var i: usize = 0;
        while (i < buf.len) : (i += 1) {
            buf[i] = 0;
        }
        return buf.len;
    }
    
    fn zeroWrite(_: *Device, buf: []const u8) usize {
        return buf.len;
    }
};

const RandomDevice = struct {
    name: []const u8 = "/dev/random",
    
    fn randomRead(_: *Device, buf: []u8) usize {
        var i: usize = 0;
        while (i < buf.len) : (i += 1) {
            buf[i] = @truncate(x86.inb(0x61) ^ (i * 7));
        }
        return buf.len;
    }
    
    fn randomWrite(_: *Device, buf: []const u8) usize {
        return buf.len;
    }
};

const ConsoleDevice = struct {
    name: []const u8 = "/dev/console",
    
    fn consoleRead(_: *Device, buf: []u8) usize {
        var i: usize = 0;
        while (i < buf.len) : (i += 1) {
            if (keyboard.readChar()) |c| {
                buf[i] = c;
            } else {
                break;
            }
        }
        return i;
    }
    
    fn consoleWrite(_: *Device, buf: []const u8) usize {
        for (buf) |c| {
            tty.writeChar(c);
        }
        return buf.len;
    }
};

const keyboard = @import("keyboard.zig");

pub fn registerStandardDevices() void {
    var null_dev = Device.init(1, .char_device, "null");
    null_dev.read = nullRead;
    null_dev.write = nullWrite;
    registerDevice(&null_dev) catch {};
    
    var zero_dev = Device.init(5, .char_device, "zero");
    zero_dev.read = zeroRead;
    zero_dev.write = zeroWrite;
    registerDevice(&zero_dev) catch {};
    
    var random_dev = Device.init(9, .char_device, "random");
    random_dev.read = randomRead;
    random_dev.write = randomWrite;
    registerDevice(&random_dev) catch {};
    
    var console_dev = Device.init(4, .char_device, "console");
    console_dev.read = consoleRead;
    console_dev.write = consoleWrite;
    registerDevice(&console_dev) catch {};
}

fn nullRead(_: *Device, _: []u8) usize {
    return 0;
}

fn nullWrite(_: *Device, buf: []const u8) usize {
    return buf.len;
}

fn zeroRead(_: *Device, buf: []u8) usize {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = 0;
    }
    return buf.len;
}

fn zeroWrite(_: *Device, buf: []const u8) usize {
    return buf.len;
}

fn randomRead(_: *Device, buf: []u8) usize {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = @truncate(x86.inb(0x61) ^ (i * 7));
    }
    return buf.len;
}

fn randomWrite(_: *Device, buf: []const u8) usize {
    return buf.len;
}

fn consoleRead(_: *Device, buf: []u8) usize {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        if (keyboard.readChar()) |c| {
            buf[i] = c;
        } else {
            break;
        }
    }
    return i;
}

fn consoleWrite(_: *Device, buf: []const u8) usize {
    for (buf) |c| {
        tty.writeChar(c);
    }
    return buf.len;
}
