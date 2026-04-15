//! Enhanced Device Management Layer
//! Based on linux-master drivers/base/ and darwin-xnu-main iokit/

const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");

const MAX_DEVICES = 256;
const MAX_DRIVERS = 64;
const MAX_CHILDREN = 16;
const MAX_NAME_LEN = 64;
const MAX_ATTR_NAME_LEN = 32;

// ============================================================================
// Device Classes (from linux-master include/linux/device.h)
// ============================================================================
pub const DeviceClass = enum(u8) {
    CLASS_UNSPECIFIED = 0,
    CLASS_BLOCK = 1,
    CLASS_CHAR = 2,
    CLASS_NET = 3,
    CLASS_INPUT = 4,
    CLASS_MEMORY = 5,
    CLASS_BUS = 6,
    CLASS_DRIVER = 7,
    CLASS_CUSTOM = 8,
};

// ============================================================================
// Device Type (from linux-master include/linux/device.h)
// ============================================================================
pub const DeviceType = enum(u8) {
    TYPE_UNSPECIFIED = 0,
    TYPE_PCI = 1,
    TYPE_USB = 2,
    TYPE_ISA = 3,
    TYPE_ACPI = 4,
    TYPE_PLATFORM = 5,
    TYPE_VIRTUAL = 6,
    TYPE_CUSTOM = 7,
};

// ============================================================================
// Device State
// ============================================================================
pub const DeviceState = enum(u8) {
    DEV_INIT = 0,
    DEV_RUNNING = 1,
    DEV_SUSPENDED = 2,
    DEV_ERROR = 3,
    REMOVED = 4,
};

// ============================================================================
// Device Attributes (sysfs-like, from linux-master drivers/base/core.c)
// ============================================================================
pub const DeviceAttr = struct {
    name: [MAX_ATTR_NAME_LEN]u8,
    name_len: usize,
    value: [256]u8,
    value_len: usize,
    permissions: u8,
    
    pub const R: u8 = 0o444;
    pub const W: u8 = 0o644;
    pub const RW: u8 = 0o666;
    
    pub fn init(name: []const u8, val: []const u8, perm: u8) DeviceAttr {
        var attr = DeviceAttr{
            .name = undefined,
            .name_len = @min(name.len, MAX_ATTR_NAME_LEN - 1),
            .value = undefined,
            .value_len = @min(val.len, 255),
            .permissions = perm,
        };
        @memset(&attr.name, 0);
        @memset(&attr.value, 0);
        @memcpy(attr.name[0..attr.name_len], name[0..attr.name_len]);
        @memcpy(attr.value[0..attr.value_len], val[0..attr.value_len]);
        return attr;
    }
};

// ============================================================================
// Device (from linux-master include/linux/device.h)
// Core device structure with sysfs support
// ============================================================================
pub const Device = struct {
    device_id: u32,
    name: [MAX_NAME_LEN]u8,
    name_len: usize,
    dev_class: DeviceClass,
    dev_type: DeviceType,
    state: DeviceState,
    
    // Parent/children hierarchy
    parent: ?*Device,
    children: [MAX_CHILDREN]*Device,
    child_count: usize,
    
    // Device-specific data
    data: ?*anyopaque,
    
    // Device attributes (sysfs)
    attributes: [8]DeviceAttr,
    attr_count: usize,
    
    // Major/minor numbers (for block/char devices)
    major: u32,
    minor: u32,
    
    // Driver attached
    driver: ?*Driver,
    
    // Reference counting
    refcount: u32,
    
    pub fn init(
        id: u32,
        name: []const u8,
        class: DeviceClass,
        dev_type: DeviceType,
    ) Device {
        var dev = Device{
            .device_id = id,
            .name = undefined,
            .name_len = @min(name.len, MAX_NAME_LEN - 1),
            .dev_class = class,
            .dev_type = dev_type,
            .state = .DEV_INIT,
            .parent = null,
            .children = undefined,
            .child_count = 0,
            .data = null,
            .attributes = undefined,
            .attr_count = 0,
            .major = 0,
            .minor = 0,
            .driver = null,
            .refcount = 1,
        };
        @memset(&dev.name, 0);
        @memset(&dev.attributes, undefined);
        @memcpy(dev.name[0..dev.name_len], name[0..dev.name_len]);
        return dev;
    }
    
    pub fn acquire(self: *Device) void {
        self.refcount += 1;
    }
    
    pub fn release(self: *Device) void {
        self.refcount -= 1;
    }
    
    pub fn addAttribute(self: *Device, attr: DeviceAttr) bool {
        if (self.attr_count >= 8) return false;
        self.attributes[self.attr_count] = attr;
        self.attr_count += 1;
        return true;
    }
    
    pub fn addAttributeByName(
        self: *Device,
        name: []const u8,
        value: []const u8,
        perm: u8,
    ) bool {
        const attr = DeviceAttr.init(name, value, perm);
        return self.addAttribute(attr);
    }
    
    pub fn findAttribute(self: *const Device, name: []const u8) ?*DeviceAttr {
        var i: usize = 0;
        while (i < self.attr_count) : (i += 1) {
            if (std.mem.eql(u8, self.attributes[i].name[0..self.attributes[i].name_len], name)) {
                return &self.attributes[i];
            }
        }
        return null;
    }
    
    pub fn addChild(self: *Device, child: *Device) bool {
        if (self.child_count >= MAX_CHILDREN) return false;
        self.children[self.child_count] = child;
        self.child_count += 1;
        child.parent = self;
        return true;
    }
    
    pub fn isRunning(self: *const Device) bool {
        return self.state == .DEV_RUNNING;
    }
    
    pub fn isRemoved(self: *const Device) bool {
        return self.state == .REMOVED;
    }
};

// ============================================================================
// Driver (from linux-master include/linux/device.h)
// Device driver with probe/remove callbacks
// ============================================================================
pub const Driver = struct {
    driver_id: u32,
    name: [MAX_NAME_LEN]u8,
    name_len: usize,
    dev_class: DeviceClass,
    
    // Driver callbacks
    probe: ?*const fn (*Device) callconv(.C) void,
    remove: ?*const fn (*Device) callconv(.C) void,
    
    // Driver data
    data: ?*anyopaque,
    
    // Attached devices
    devices: [MAX_CHILDREN]*Device,
    device_count: usize,
    
    pub fn init(
        id: u32,
        name: []const u8,
        class: DeviceClass,
        probe_fn: ?*const fn (*Device) callconv(.C) void,
        remove_fn: ?*const fn (*Device) callconv(.C) void,
    ) Driver {
        var drv = Driver{
            .driver_id = id,
            .name = undefined,
            .name_len = @min(name.len, MAX_NAME_LEN - 1),
            .dev_class = class,
            .probe = probe_fn,
            .remove = remove_fn,
            .data = null,
            .devices = undefined,
            .device_count = 0,
        };
        @memset(&drv.name, 0);
        @memcpy(drv.name[0..drv.name_len], name[0..drv.name_len]);
        return drv;
    }
    
    pub fn attachToDevice(self: *Driver, dev: *Device) bool {
        if (self.device_count >= MAX_CHILDREN) return false;
        
        dev.driver = self;
        self.devices[self.device_count] = dev;
        self.device_count += 1;
        
        // Call probe function
        if (self.probe) |probe_fn| {
            probe_fn(dev);
        }
        
        dev.state = .DEV_RUNNING;
        return true;
    }
    
    pub fn detachFromDevice(self: *Driver, dev: *Device) bool {
        var i: usize = 0;
        while (i < self.device_count) : (i += 1) {
            if (self.devices[i] == dev) {
                // Call remove function
                if (self.remove) |remove_fn| {
                    remove_fn(dev);
                }
                
                dev.driver = null;
                dev.state = .DEV_INIT;
                
                // Shift remaining devices
                var j: usize = i;
                while (j < self.device_count - 1) : (j += 1) {
                    self.devices[j] = self.devices[j + 1];
                }
                self.device_count -= 1;
                return true;
            }
        }
        return false;
    }
};

// ============================================================================
// Bus (from linux-master include/linux/device.h)
//! Device bus for enumeration and driver matching
// ============================================================================
pub const Bus = struct {
    bus_id: u32,
    name: [MAX_NAME_LEN]u8,
    name_len: usize,
    
    // Devices on this bus
    devices: [MAX_DEVICES]*Device,
    device_count: usize,
    
    // Drivers on this bus
    drivers: [MAX_DRIVERS]*Driver,
    driver_count: usize,
    
    pub fn init(id: u32, name: []const u8) Bus {
        var bus = Bus{
            .bus_id = id,
            .name = undefined,
            .name_len = @min(name.len, MAX_NAME_LEN - 1),
            .devices = undefined,
            .device_count = 0,
            .drivers = undefined,
            .driver_count = 0,
        };
        @memset(&bus.name, 0);
        @memcpy(bus.name[0..bus.name_len], name[0..bus.name_len]);
        return bus;
    }
    
    pub fn addDevice(self: *Bus, dev: *Device) bool {
        if (self.device_count >= MAX_DEVICES) return false;
        self.devices[self.device_count] = dev;
        self.device_count += 1;
        return true;
    }
    
    pub fn addDriver(self: *Bus, drv: *Driver) bool {
        if (self.driver_count >= MAX_DRIVERS) return false;
        self.drivers[self.driver_count] = drv;
        self.driver_count += 1;
        
        // Try to match with existing devices
        self.matchDrivers();
        return true;
    }
    
    fn matchDrivers(self: *Bus) void {
        var d: usize = 0;
        while (d < self.device_count) : (d += 1) {
            const dev = self.devices[d];
            if (dev.driver != null) continue; // Already bound
            
            var i: usize = 0;
            while (i < self.driver_count) : (i += 1) {
                const drv = self.drivers[i];
                if (drv.dev_class == dev.dev_class) {
                    drv.attachToDevice(dev);
                    break;
                }
            }
        }
    }
};

// ============================================================================
// Global State
// ============================================================================
var devices: [MAX_DEVICES]?*Device = undefined;
var device_count: usize = 0;
var next_device_id: u32 = 1;

var drivers: [MAX_DRIVERS]?*Driver = undefined;
var driver_count: usize = 0;
var next_driver_id: u32 = 1;

var buses: [8]?*Bus = undefined;
var bus_count: usize = 0;
var next_bus_id: u32 = 1;

// ============================================================================
// Initialization
// ============================================================================
pub fn initialize() void {
    var i: usize = 0;
    while (i < MAX_DEVICES) : (i += 1) {
        devices[i] = null;
    }
    while (i < MAX_DRIVERS) : (i += 1) {
        drivers[i] = null;
    }
    while (i < 8) : (i += 1) {
        buses[i] = null;
    }
    
    device_count = 0;
    driver_count = 0;
    bus_count = 0;
    next_device_id = 1;
    next_driver_id = 1;
    next_bus_id = 1;
    
    tty.print("[DEVICE] Device manager initialized\n", .{});
}

// ============================================================================
// Device Management
// ============================================================================
pub fn createDevice(
    name: []const u8,
    class: DeviceClass,
    dev_type: DeviceType,
) ?u32 {
    if (device_count >= MAX_DEVICES) return null;
    
    var i: usize = 0;
    while (i < MAX_DEVICES) : (i += 1) {
        if (devices[i] == null) {
            const dev: *Device = @ptrFromInt(
                pmem.kmalloc(@sizeOf(Device)) catch return null
            );
            dev.* = Device.init(next_device_id, name, class, dev_type);
            devices[i] = dev;
            device_count += 1;
            next_device_id += 1;
            
            tty.print("[DEVICE] Created device '{s}' (id={d}, class={d})\n", .{
                name, dev.device_id, @intFromEnum(class)
            });
            
            return dev.device_id;
        }
    }
    return null;
}

pub fn removeDevice(device_id: u32) void {
    var i: usize = 0;
    while (i < MAX_DEVICES) : (i += 1) {
        if (devices[i]) |dev| {
            if (dev.device_id == device_id) {
                // Detach from driver
                if (dev.driver) |drv| {
                    drv.detachFromDevice(dev);
                }
                
                dev.state = .REMOVED;
                devices[i] = null;
                device_count -= 1;
                
                tty.print("[DEVICE] Removed device id={d}\n", .{device_id});
                return;
            }
        }
    }
}

pub fn findDeviceByName(name: []const u8) ?*Device {
    var i: usize = 0;
    while (i < MAX_DEVICES) : (i += 1) {
        if (devices[i]) |dev| {
            if (std.mem.eql(u8, dev.name[0..dev.name_len], name)) {
                return dev;
            }
        }
    }
    return null;
}

pub fn findDeviceById(device_id: u32) ?*Device {
    var i: usize = 0;
    while (i < MAX_DEVICES) : (i += 1) {
        if (devices[i]) |dev| {
            if (dev.device_id == device_id) {
                return dev;
            }
        }
    }
    return null;
}

// ============================================================================
// Driver Management
// ============================================================================
pub fn registerDriver(
    name: []const u8,
    class: DeviceClass,
    probe_fn: ?*const fn (*Device) callconv(.C) void,
    remove_fn: ?*const fn (*Device) callconv(.C) void,
) ?u32 {
    if (driver_count >= MAX_DRIVERS) return null;
    
    var i: usize = 0;
    while (i < MAX_DRIVERS) : (i += 1) {
        if (drivers[i] == null) {
            const drv: *Driver = @ptrFromInt(
                pmem.kmalloc(@sizeOf(Driver)) catch return null
            );
            drv.* = Driver.init(next_driver_id, name, class, probe_fn, remove_fn);
            drivers[i] = drv;
            driver_count += 1;
            next_driver_id += 1;
            
            tty.print("[DEVICE] Registered driver '{s}' (id={d})\n", .{
                name, drv.driver_id
            });
            
            return drv.driver_id;
        }
    }
    return null;
}

pub fn unregisterDriver(driver_id: u32) void {
    var i: usize = 0;
    while (i < MAX_DRIVERS) : (i += 1) {
        if (drivers[i]) |drv| {
            if (drv.driver_id == driver_id) {
                // Detach from all devices
                var j: usize = 0;
                while (j < drv.device_count) : (j += 1) {
                    drv.detachFromDevice(drv.devices[j]);
                }
                
                drivers[i] = null;
                driver_count -= 1;
                
                tty.print("[DEVICE] Unregistered driver id={d}\n", .{driver_id});
                return;
            }
        }
    }
}

// ============================================================================
// Bus Management
// ============================================================================
pub fn createBus(name: []const u8) ?u32 {
    if (bus_count >= 8) return null;
    
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (buses[i] == null) {
            const bus: *Bus = @ptrFromInt(
                pmem.kmalloc(@sizeOf(Bus)) catch return null
            );
            bus.* = Bus.init(next_bus_id, name);
            buses[i] = bus;
            bus_count += 1;
            next_bus_id += 1;
            
            tty.print("[DEVICE] Created bus '{s}' (id={d})\n", .{
                name, bus.bus_id
            });
            
            return bus.bus_id;
        }
    }
    return null;
}

// ============================================================================
// Standard Devices (from linux-master drivers/)
// ============================================================================
pub fn registerStandardDevices() void {
    // Create system buses
    _ = createBus("platform");
    _ = createBus("virtual");
    
    // Create standard devices
    _ = createDevice("tty0", .CLASS_CHAR, .TYPE_VIRTUAL);
    _ = createDevice("ttyS0", .CLASS_CHAR, .TYPE_ISA);
    _ = createDevice("ram0", .CLASS_BLOCK, .TYPE_VIRTUAL);
    _ = createDevice("input0", .CLASS_INPUT, .TYPE_PLATFORM);
    _ = createDevice("mem", .CLASS_MEMORY, .TYPE_VIRTUAL);
    _ = createDevice("null", .CLASS_CHAR, .TYPE_VIRTUAL);
    _ = createDevice("zero", .CLASS_CHAR, .TYPE_VIRTUAL);
    _ = createDevice("random", .CLASS_CHAR, .TYPE_VIRTUAL);
    
    tty.print("[DEVICE] Registered standard devices\n", .{});
}

// ============================================================================
// Device Tree (for hierarchy)
// ============================================================================
pub fn setDeviceParent(child_id: u32, parent_id: u32) bool {
    const child = findDeviceById(child_id) orelse return false;
    const parent = findDeviceById(parent_id) orelse return false;
    return parent.addChild(child);
}

// ============================================================================
// Debug
// ============================================================================
pub fn dumpDevices() void {
    tty.print("[DEVICE] Device List:\n", .{});
    var i: usize = 0;
    while (i < MAX_DEVICES) : (i += 1) {
        if (devices[i]) |dev| {
            const state_str = switch (dev.state) {
                .DEV_INIT => "init",
                .DEV_RUNNING => "running",
                .DEV_SUSPENDED => "suspended",
                .DEV_ERROR => "error",
                .REMOVED => "removed",
            };
            tty.print("  Device {d}: '{s}' (class={d}, type={d}, state={s})\n", .{
                dev.device_id,
                dev.name[0..dev.name_len],
                @intFromEnum(dev.dev_class),
                @intFromEnum(dev.dev_type),
                state_str,
            });
        }
    }
}

pub fn dumpDrivers() void {
    tty.print("[DEVICE] Driver List:\n", .{});
    var i: usize = 0;
    while (i < MAX_DRIVERS) : (i += 1) {
        if (drivers[i]) |drv| {
            tty.print("  Driver {d}: '{s}' (class={d}, devices={d})\n", .{
                drv.driver_id,
                drv.name[0..drv.name_len],
                @intFromEnum(drv.dev_class),
                drv.device_count,
            });
        }
    }
}

pub fn dumpBuses() void {
    tty.print("[DEVICE] Bus List:\n", .{});
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (buses[i]) |bus| {
            tty.print("  Bus {d}: '{s}' (devices={d}, drivers={d})\n", .{
                bus.bus_id,
                bus.name[0..bus.name_len],
                bus.device_count,
                bus.driver_count,
            });
        }
    }
}
