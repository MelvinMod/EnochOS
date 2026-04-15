//! Mach IPC subsystem - Enhanced version based on darwin-xnu
//! Provides ports, messages, and notifications for inter-process communication

const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");
const buddy = @import("buddy.zig");

const MAX_PORTS = 512;
const MAX_MESSAGES = 2048;
const MAX_MESSAGE_SIZE = 1024;
const MAX_PORT_NAME_LEN = 64;

// ============================================================================
// Mach Port Rights (from darwin-xnu ipc/port.h)
// ============================================================================
pub const PortRights = packed struct {
    send: bool = false,        // Send right to this port
    receive: bool = false,     // Receive right (unique)
    send_once: bool = false,   // Send-once right (destructive)
    reserved: u5 = 0,
};

// ============================================================================
// Mach Port State
// ============================================================================
pub const PortState = enum(u8) {
    dead = 0,           // Port is dead
    active = 1,         // Port is active in a space
    receiving = 2,      // Port has receive right
    send_only = 3,      // Send-only port
};

// ============================================================================
// Mach Message Header (from darwin-xnu mach/message.h)
// ============================================================================
pub const MachMessageHeader = packed struct {
    msgh_size: u32,                 // Total message size (header + body)
    msgh_id: u32,                   // Message ID (kernel/user defined)
    msgh_bits: u16,                 // Message attributes
    msgh_remote_port: u32,          // Destination port (send right)
    msgh_local_port: u32,           // Source port (send/receive right)
    msgh_reserved: u16,             // Reserved
    msgh_size_bits: u32,            // Body size in 4-byte units

    pub const BITS = packed struct {
        msgh_send_once: bool = false,
        msgh_id_valid: bool = true,
        msgh_type_normal: bool = true,
        reserved: u29 = 0,
    };
};

// ============================================================================
// Port Queue (Enhanced from darwin-xnu ipc/mqueue.h)
// ============================================================================
pub const PortQueue = struct {
    messages: [64]Message,
    head: usize,
    tail: usize,
    count: usize,
    high_water: usize,

    pub fn init() PortQueue {
        return PortQueue{
            .messages = undefined,
            .head = 0,
            .tail = 0,
            .count = 0,
            .high_water = 0,
        };
    }

    pub fn enqueue(self: *PortQueue, msg: Message) bool {
        if (self.count >= 64) return false;
        self.messages[self.tail] = msg;
        self.tail = (self.tail + 1) % 64;
        self.count += 1;
        if (self.count > self.high_water) self.high_water = self.count;
        return true;
    }

    pub fn dequeue(self: *PortQueue) ?Message {
        if (self.count == 0) return null;
        const msg = self.messages[self.head];
        self.head = (self.head + 1) % 64;
        self.count -= 1;
        return msg;
    }

    pub fn peek(self: *const PortQueue) ?Message {
        if (self.count == 0) return null;
        return self.messages[self.head];
    }

    pub fn isEmpty(self: *const PortQueue) bool {
        return self.count == 0;
    }

    pub fn isFull(self: *const PortQueue) bool {
        return self.count >= 64;
    }
};

// ============================================================================
// Mach Message (from darwin-xnu ipc/kmsg.h)
// ============================================================================
pub const Message = struct {
    header: MachMessageHeader,
    data: [MAX_MESSAGE_SIZE]u8,
    data_size: usize,
    sender_pid: u32,
    timestamp: u64,

    pub fn init(msg_id: u32, msg_type: u32, sender: u32) Message {
        return Message{
            .header = MachMessageHeader{
                .msgh_size = @sizeOf(MachMessageHeader) + 0,
                .msgh_id = msg_id,
                .msgh_bits = 0,
                .msgh_remote_port = 0,
                .msgh_local_port = 0,
                .msgh_reserved = 0,
                .msgh_size_bits = 0,
            },
            .data = undefined,
            .data_size = 0,
            .sender_pid = sender,
            .timestamp = 0, // TODO: Add time counter
        };
    }

    pub fn setData(self: *Message, data: []const u8) !void {
        if (data.len > MAX_MESSAGE_SIZE) return error.DataTooLarge;
        @memcpy(self.data[0..data.len], data);
        self.data_size = data.len;
        self.header.msgh_size = @sizeOf(MachMessageHeader) + @as(u32, @intCast(data.len));
    }
};

// ============================================================================
// Mach Port (Enhanced from darwin-xnu ipc/port.h)
// ============================================================================
pub const Port = struct {
    port_id: u32,
    name: [MAX_PORT_NAME_LEN]u8,
    name_len: usize,
    queue: PortQueue,
    owner_pid: u32,
    rights: PortRights,
    state: PortState,
    reference_count: u32,
    deleted: bool,

    pub fn init(id: u32, name: []const u8, owner: u32, rights: PortRights) Port {
        var p = Port{
            .port_id = id,
            .name = undefined,
            .name_len = @min(name.len, MAX_PORT_NAME_LEN - 1),
            .queue = PortQueue.init(),
            .owner_pid = owner,
            .rights = rights,
            .state = if (rights.receive) .receiving else .send_only,
            .reference_count = 1,
            .deleted = false,
        };
        @memset(&p.name, 0);
        @memcpy(p.name[0..p.name_len], name[0..p.name_len]);
        return p;
    }

    pub fn sendRight(self: *const Port) bool {
        return self.rights.send or self.rights.receive;
    }

    pub fn receiveRight(self: *const Port) bool {
        return self.rights.receive;
    }
};

// ============================================================================
// Port Space (from darwin-xnu ipc/space.h)
// ============================================================================
var ports: [MAX_PORTS]Port = undefined;
var port_bitmap: [(MAX_PORTS + 7) / 8]u8 = undefined;
var port_count: usize = 0;
var next_port_id: u32 = 1;

// ============================================================================
// Message Pool (from darwin-xnu ipc/kmsg.h)
// ============================================================================
var message_pool: [MAX_MESSAGES]Message = undefined;
var message_pool_bitmap: [(MAX_MESSAGES + 7) / 8]u8 = undefined;

// ============================================================================
// Notification System (from darwin-xnu ipc/notify.h)
// ============================================================================
pub const Notification = struct {
    notify_id: u32,
    port_id: u32,
    event_type: u32,
    data: [8]u8,
    data_size: usize,

    pub const EVENTS = enum(u32) {
        DATA_AVAILABLE = 1,
        PORT_DESTROYED = 2,
        MESSAGE_RECEIVED = 3,
        SEND_RIGHT_RELEASED = 4,
    };
};

var notifications: [128]Notification = undefined;
var notification_bitmap: [(128 + 7) / 8]u8 = undefined;
var notification_count: usize = 0;
var next_notify_id: u32 = 1;

// ============================================================================
// Initialization
// ============================================================================
pub fn initialize() void {
    // Initialize port bitmap
    @memset(&port_bitmap, 0);
    // Initialize message pool bitmap
    @memset(&message_pool_bitmap, 0);
    // Initialize notification bitmap
    @memset(&notification_bitmap, 0);
    
    port_count = 0;
    next_port_id = 1;
    notification_count = 0;
    next_notify_id = 1;
    
    tty.print("[IPC] Mach IPC subsystem initialized\n", .{});
    tty.print("[IPC] Ports: {d}, Messages: {d}, Notifications: {d}\n", .{
        MAX_PORTS, MAX_MESSAGES, 128
    });
}

// ============================================================================
// Port Management
// ============================================================================
pub fn portCreate(name: []const u8, owner: u32, rights: PortRights) ?u32 {
    if (port_count >= MAX_PORTS) return null;

    // Find free port slot
    var i: usize = 0;
    while (i < MAX_PORTS) : (i += 1) {
        if ((port_bitmap[i / 8] & (@as(u8, 1) << @truncate(i % 8))) == 0) {
            // Allocate port
            port_bitmap[i / 8] |= (@as(u8, 1) << @truncate(i % 8));
            port_count += 1;

            ports[i] = Port.init(next_port_id, name, owner, rights);
            const port_id = next_port_id;
            next_port_id += 1;

            tty.print("[IPC] Created port '{s}' (id={d}, owner={d})\n", .{
                name, port_id, owner
            });
            return port_id;
        }
    }
    return null;
}

pub fn portDestroy(port_id: u32) !void {
    if (port_id == 0 or port_id >= next_port_id) {
        return error.InvalidPort;
    }

    const index = @as(usize, @intCast(port_id - 1));
    if ((port_bitmap[index / 8] & (@as(u8, 1) << @truncate(index % 8))) == 0) {
        return error.InvalidPort;
    }

    // Free port slot
    port_bitmap[index / 8] &= ~(@as(u8, 1) << @truncate(index % 8));
    port_count -= 1;
    ports[index].deleted = true;

    tty.print("[IPC] Destroyed port id={d}\n", .{port_id});
}

pub fn portSend(port_id: u32, msg_id: u32, data: []const u8) !void {
    if (port_id == 0 or port_id >= next_port_id) {
        return error.InvalidPort;
    }

    const index = @as(usize, @intCast(port_id - 1));
    if (ports[index].deleted) return error.InvalidPort;
    if (!ports[index].sendRight()) return error.NoSendRight;

    // Allocate message from pool
    const msg = allocateMessage() orelse return error.NoMemory;
    msg.* = Message.init(msg_id, 0, 0);
    try msg.setData(data);

    if (!ports[index].queue.enqueue(msg.*)) {
        return error.QueueFull;
    }

    // Send notification
    _ = registerNotification(port_id, Notification.EVENTS.MESSAGE_RECEIVED, 0);
}

pub fn portReceive(port_id: u32) ?Message {
    if (port_id == 0 or port_id >= next_port_id) {
        return null;
    }

    const index = @as(usize, @intCast(port_id - 1));
    if (ports[index].deleted) return null;
    if (!ports[index].receiveRight()) return null;

    return ports[index].queue.dequeue();
}

pub fn portPeek(port_id: u32) ?Message {
    if (port_id == 0 or port_id >= next_port_id) {
        return null;
    }

    const index = @as(usize, @intCast(port_id - 1));
    if (ports[index].deleted) return null;

    return ports[index].queue.peek();
}

pub fn portLookup(name: []const u8) ?u32 {
    var i: usize = 0;
    while (i < MAX_PORTS) : (i += 1) {
        if ((port_bitmap[i / 8] & (@as(u8, 1) << @truncate(i % 8))) != 0) {
            if (std.mem.eql(u8, ports[i].name[0..ports[i].name_len], name)) {
                return ports[i].port_id;
            }
        }
    }
    return null;
}

pub fn portQueueSize(port_id: u32) usize {
    if (port_id == 0 or port_id >= next_port_id) return 0;
    const index = @as(usize, @intCast(port_id - 1));
    if (ports[index].deleted) return 0;
    return ports[index].queue.count;
}

// ============================================================================
// Message Pool Management
// ============================================================================
fn allocateMessage() ?*Message {
    var i: usize = 0;
    while (i < MAX_MESSAGES) : (i += 1) {
        if ((message_pool_bitmap[i / 8] & (@as(u8, 1) << @truncate(i % 8))) == 0) {
            message_pool_bitmap[i / 8] |= (@as(u8, 1) << @truncate(i % 8));
            return &message_pool[i];
        }
    }
    return null;
}

pub fn freeMessage(msg: *Message) void {
    const index = @intFromPtr(msg) - @intFromPtr(&message_pool[0]);
    if (index < MAX_MESSAGES) {
        message_pool_bitmap[index / 8] &= ~(@as(u8, 1) << @truncate(index % 8));
    }
}

// ============================================================================
// Notification Management
// ============================================================================
pub fn registerNotification(port_id: u32, event_type: u32, data: u32) ?u32 {
    if (notification_count >= 128) return null;

    var i: usize = 0;
    while (i < 128) : (i += 1) {
        if ((notification_bitmap[i / 8] & (@as(u8, 1) << @truncate(i % 8))) == 0) {
            notification_bitmap[i / 8] |= (@as(u8, 1) << @truncate(i % 8));
            notification_count += 1;

            notifications[i] = Notification{
                .notify_id = next_notify_id,
                .port_id = port_id,
                .event_type = event_type,
                .data = undefined,
                .data_size = 4,
            };
            @memcpy(notifications[i].data[0..4], @as([*]const u8, @ptrCast(&data))[0..4]);
            
            const notify_id = next_notify_id;
            next_notify_id += 1;
            return notify_id;
        }
    }
    return null;
}

pub fn checkNotifications() ?Notification {
    if (notification_count == 0) return null;

    var i: usize = 0;
    while (i < 128) : (i += 1) {
        if ((notification_bitmap[i / 8] & (@as(u8, 1) << @truncate(i % 8))) != 0) {
            // Shift remaining notifications
            var j: usize = i;
            while (j < 127) : (j += 1) {
                if ((notification_bitmap[(j + 1) / 8] & (@as(u8, 1) << @truncate((j + 1) % 8))) != 0) {
                    notifications[j] = notifications[j + 1];
                    notification_bitmap[j / 8] |= (@as(u8, 1) << @truncate(j % 8));
                } else {
                    notification_bitmap[j / 8] &= ~(@as(u8, 1) << @truncate(j % 8));
                    break;
                }
            }
            notification_count -= 1;
            return notifications[i];
        }
    }
    return null;
}

pub fn notificationGetPortId(notify_id: u32) ?u32 {
    var i: usize = 0;
    while (i < 128) : (i += 1) {
        if (notifications[i].notify_id == notify_id) {
            return notifications[i].port_id;
        }
    }
    return null;
}

// ============================================================================
// Debug / Info
// ============================================================================
pub fn dumpPorts() void {
    tty.print("[IPC] Port Table Dump:\n", .{});
    var i: usize = 0;
    while (i < MAX_PORTS) : (i += 1) {
        if ((port_bitmap[i / 8] & (@as(u8, 1) << @truncate(i % 8))) != 0) {
            const port = &ports[i];
            tty.print("  Port {d}: name={s}, owner={d}, count={d}, queue={d}\n", .{
                port.port_id,
                port.name[0..port.name_len],
                port.owner_pid,
                port.reference_count,
                port.queue.count,
            });
        }
    }
}
