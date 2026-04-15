const std = @import("std");
const tty = @import("tty.zig");
const pmem = @import("pmem.zig");

const MAX_PORTS = 256;
const MAX_MESSAGES = 1024;
const MAX_MESSAGE_SIZE = 256;

pub const Port = struct {
    port_id: u32,
    name: []const u8,
    queue: MessageQueue,
    owner_pid: u32,
    rights: Rights,

    pub const Rights = packed struct {
        send: bool = false,
        receive: bool = false,
        send_once: bool = false,
        reserved: u5 = 0,
    };

    pub const MessageQueue = struct {
        messages: [32]Message,
        head: usize,
        tail: usize,
        count: usize,

        pub fn init() MessageQueue {
            return MessageQueue{
                .messages = undefined,
                .head = 0,
                .tail = 0,
                .count = 0,
            };
        }

        pub fn enqueue(self: *MessageQueue, msg: Message) bool {
            if (self.count >= 32) return false;
            self.messages[self.tail] = msg;
            self.tail = (self.tail + 1) % 32;
            self.count += 1;
            return true;
        }

        pub fn dequeue(self: *MessageQueue) ?Message {
            if (self.count == 0) return null;
            const msg = self.messages[self.head];
            self.head = (self.head + 1) % 32;
            self.count -= 1;
            return msg;
        }

        pub fn isEmpty(self: *const MessageQueue) bool {
            return self.count == 0;
        }
    };

    pub const Message = struct {
        header: MessageHeader,
        data: [MAX_MESSAGE_SIZE]u8,
        data_size: usize,

        pub const MessageHeader = packed struct {
            msg_id: u32,
            msg_size: u32,
            msg_type: u32,
            sender_port: u32,
            sender_pid: u32,
            reserved: u32 = 0,
        };
    };

    pub fn create(name: []const u8, owner: u32, rights: Rights) ?*Port {
        if (port_count >= MAX_PORTS) return null;

        const port: *Port = @ptrFromInt(pmem.kmalloc(@sizeOf(Port)).?);
        port.* = Port{
            .port_id = next_port_id,
            .name = name,
            .queue = MessageQueue.init(),
            .owner_pid = owner,
            .rights = rights,
        };
        next_port_id += 1;
        port_count += 1;
        ports[port.port_id] = port;

        tty.print("[IPC] Created port {s} (id={d})\n", .{ name, port.port_id });
        return port;
    }

    pub fn destroy(self: *Port) void {
        ports[self.port_id] = null;
        port_count -= 1;
        tty.print("[IPC] Destroyed port {s}\n", .{self.name});
    }
};

var ports: [MAX_PORTS]?*Port = undefined;
var port_count: usize = 0;
var next_port_id: u32 = 1;
var message_pool: [MAX_MESSAGES]Port.Message = undefined;
var message_pool_bitmap: [(MAX_MESSAGES + 7) / 8]u8 = undefined;

pub fn initialize() void {
    var i: usize = 0;
    while (i < MAX_PORTS) : (i += 1) {
        ports[i] = null;
    }
    while (i < MAX_MESSAGES) : (i += 1) {
        message_pool_bitmap[i / 8] = 0;
    }
    port_count = 0;
    next_port_id = 1;
    tty.print("[IPC] Mach IPC subsystem initialized\n", .{});
}

pub fn portCreate(name: []const u8, owner: u32, rights: Port.Rights) ?u32 {
    if (Port.create(name, owner, rights)) |port| {
        return port.port_id;
    }
    return null;
}

pub fn portDestroy(port_id: u32) void {
    if (port_id < MAX_PORTS and ports[port_id]) |port| {
        port.destroy();
    }
}

pub fn portSend(port_id: u32, msg_type: u32, data: []const u8) !void {
    if (port_id >= MAX_PORTS or ports[port_id] == null) {
        return error.InvalidPort;
    }

    const port = ports[port_id].?;
    if (!port.rights.send) {
        return error.NoSendRight;
    }

    const msg: Port.Message = Port.Message{
        .header = Port.Message.MessageHeader{
            .msg_id = next_port_id,
            .msg_size = @intCast(@min(data.len, MAX_MESSAGE_SIZE)),
            .msg_type = msg_type,
            .sender_port = 0,
            .sender_pid = 0,
        },
        .data = undefined,
        .data_size = @min(data.len, MAX_MESSAGE_SIZE),
    };
    @memcpy(msg.data[0..msg.data_size], data);

    if (!port.queue.enqueue(msg)) {
        return error.QueueFull;
    }
}

pub fn portReceive(port_id: u32) ?Port.Message {
    if (port_id >= MAX_PORTS or ports[port_id] == null) {
        return null;
    }

    const port = ports[port_id].?;
    if (!port.rights.receive) {
        return null;
    }

    return port.queue.dequeue();
}

pub fn portPeek(port_id: u32) ?Port.Message {
    if (port_id >= MAX_PORTS or ports[port_id] == null) {
        return null;
    }

    const port = ports[port_id].?;
    if (port.queue.count > 0) {
        return port.queue.messages[port.queue.head];
    }
    return null;
}

pub fn portQueueEmpty(port_id: u32) bool {
    if (port_id >= MAX_PORTS or ports[port_id] == null) {
        return true;
    }
    return ports[port_id].?.queue.isEmpty();
}

pub fn portLookup(name: []const u8) ?u32 {
    var i: usize = 0;
    while (i < MAX_PORTS) : (i += 1) {
        if (ports[i]) |port| {
            if (std.mem.eql(u8, port.name, name)) {
                return port.port_id;
            }
        }
    }
    return null;
}

pub fn allocateMessage() ?*Port.Message {
    var i: usize = 0;
    while (i < MAX_MESSAGES) : (i += 1) {
        if ((message_pool_bitmap[i / 8] & (@as(u8, 1) << (i % 8))) == 0) {
            message_pool_bitmap[i / 8] |= (@as(u8, 1) << (i % 8));
            return &message_pool[i];
        }
    }
    return null;
}

pub fn freeMessage(msg: *Port.Message) void {
    const index = @intFromPtr(msg) - @intFromPtr(&message_pool[0]);
    if (index < MAX_MESSAGES) {
        const mask = ~(@as(u8, 1) << @truncate(index % 8));
        message_pool_bitmap[index / 8] &= mask;
    }
}

pub const Notification = struct {
    port_id: u32,
    event_type: u32,
    data: u32,

    pub const EVENTS = struct {
        pub const DATA_AVAILABLE: u32 = 1;
        pub const PORT_DESTROYED: u32 = 2;
        pub const MESSAGE_RECEIVED: u32 = 3;
    };
};

var notifications: [128]Notification = undefined;
var notification_count: usize = 0;

pub fn registerNotification(port_id: u32, event_type: u32, data: u32) bool {
    if (notification_count >= 128) return false;
    notifications[notification_count] = Notification{
        .port_id = port_id,
        .event_type = event_type,
        .data = data,
    };
    notification_count += 1;
    return true;
}

pub fn checkNotifications() ?Notification {
    if (notification_count > 0) {
        const notif = notifications[0];
        var i: usize = 0;
        while (i < notification_count - 1) : (i += 1) {
            notifications[i] = notifications[i + 1];
        }
        notification_count -= 1;
        return notif;
    }
    return null;
}