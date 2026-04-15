const std = @import("std");
const tty = @import("tty.zig");

const Process = struct {
    pid: u32,
    state: State,
    entry: *const fn () void,
    stack: [*]u8,
    stack_top: usize,
    
    const State = enum {
        running,
        ready,
        blocked,
        terminated,
    };
};

const MAX_PROCESSES = 32;
var processes: [MAX_PROCESSES]?Process = undefined;
var process_count: u32 = 0;
var current_process: ?u32 = null;
var next_pid: u32 = 1;

var scheduler_ready: bool = false;

pub fn initialize() void {
    var i: usize = 0;
    while (i < MAX_PROCESSES) : (i += 1) {
        processes[i] = null;
    }
    scheduler_ready = true;
}

pub fn createProcess(entry: *const fn () void) u32 {
    if (process_count >= MAX_PROCESSES) {
        return 0;
    }

    const pid = next_pid;
    next_pid += 1;
    process_count += 1;

    var i: usize = 0;
    while (i < MAX_PROCESSES) : (i += 1) {
        if (processes[i] == null) {
            const stack: [*]u8 = @as([*]u8, @ptrFromInt(0x00200000 + i * 4096));
            processes[i] = Process{
                .pid = pid,
                .state = .ready,
                .entry = entry,
                .stack = stack,
                .stack_top = 4096,
            };
            if (current_process == null) {
                current_process = pid;
            }
            return pid;
        }
    }

    return 0;
}

pub fn switchProcess() void {
    if (!scheduler_ready) return;
    
    if (current_process) |cp| {
        var found: ?u32 = null;
        var i: usize = 0;
        while (i < MAX_PROCESSES and found == null) : (i += 1) {
            if (processes[i]) |p| {
                if (p.pid != cp and p.state == .ready) {
                    found = p.pid;
                }
            }
        }
        
        if (found) |np| {
            current_process = np;
        }
    }
}

pub fn run() noreturn {
    scheduler_ready = true;
    
    while (true) {
        asm volatile ("hlt");
        switchProcess();
    }
}

pub fn yield() void {
    switchProcess();
}

pub fn exitProcess(pid: u32) noreturn {
    var i: usize = 0;
    while (i < MAX_PROCESSES) : (i += 1) {
        if (processes[i]) |p| {
            if (p.pid == pid) {
                processes[i] = null;
                process_count -= 1;
                if (current_process == pid) {
                    current_process = null;
                }
                break;
            }
        }
    }
    run();
    unreachable;
}