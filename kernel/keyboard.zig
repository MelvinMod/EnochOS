const std = @import("std");
const tty = @import("tty.zig");
const x86 = @import("x86.zig");
const idt = @import("idt.zig");

const KEYBOARD_BUFFER_SIZE = 256;

const ScanCode = enum(u8) {
    KEY_A = 0x1E,
    KEY_B = 0x30,
    KEY_C = 0x2E,
    KEY_D = 0x20,
    KEY_E = 0x12,
    KEY_F = 0x21,
    KEY_G = 0x22,
    KEY_H = 0x23,
    KEY_I = 0x17,
    KEY_J = 0x24,
    KEY_K = 0x25,
    KEY_L = 0x26,
    KEY_M = 0x32,
    KEY_N = 0x31,
    KEY_O = 0x18,
    KEY_P = 0x19,
    KEY_Q = 0x10,
    KEY_R = 0x13,
    KEY_S = 0x1F,
    KEY_T = 0x14,
    KEY_U = 0x16,
    KEY_V = 0x2F,
    KEY_W = 0x11,
    KEY_X = 0x2D,
    KEY_Y = 0x15,
    KEY_Z = 0x2C,
    KEY_0 = 0x0B,
    KEY_1 = 0x02,
    KEY_2 = 0x03,
    KEY_3 = 0x04,
    KEY_4 = 0x05,
    KEY_5 = 0x06,
    KEY_6 = 0x07,
    KEY_7 = 0x08,
    KEY_8 = 0x09,
    KEY_9 = 0x0A,
    KEY_ENTER = 0x1C,
    KEY_ESC = 0x01,
    KEY_BACKSPACE = 0x0E,
    KEY_TAB = 0x0F,
    KEY_SPACE = 0x39,
    KEY_MINUS = 0x0C,
    KEY_EQUALS = 0x0D,
    KEY_BRACKET_LEFT = 0x1A,
    KEY_BRACKET_RIGHT = 0x1B,
    KEY_BACKSLASH = 0x2B,
    KEY_SEMICOLON = 0x27,
    KEY_APOSTROPHE = 0x28,
    KEY_GRAVE = 0x29,
    KEY_COMMA = 0x33,
    KEY_PERIOD = 0x34,
    KEY_SLASH = 0x35,
    KEY_CAPS_LOCK = 0x3A,
    KEY_F1 = 0x3B,
    KEY_F2 = 0x3C,
    KEY_F3 = 0x3D,
    KEY_F4 = 0x3E,
    KEY_F5 = 0x3F,
    KEY_F6 = 0x40,
    KEY_F7 = 0x41,
    KEY_F8 = 0x42,
    KEY_F9 = 0x43,
    KEY_F10 = 0x44,
    KEY_UP = 0x48,
    KEY_DOWN = 0x50,
    KEY_LEFT = 0x4B,
    KEY_RIGHT = 0x4D,
    KEY_INSERT = 0x52,
    KEY_DELETE = 0x53,
    KEY_HOME = 0x47,
    KEY_END = 0x4F,
    KEY_PAGE_UP = 0x49,
    KEY_PAGE_DOWN = 0x51,
};

const ShiftState = enum {
    none,
    shift,
    ctrl,
    alt,
};

var buffer: [KEYBOARD_BUFFER_SIZE]u8 = undefined;
var buffer_head: usize = 0;
var buffer_tail: usize = 0;
var shift_state: ShiftState = .none;
var caps_lock: bool = false;
var num_lock: bool = true;
var initialized: bool = false;

const LowercaseLetters = "abcdefghijklmnopqrstuvwxyz";
const UppercaseLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const Numbers = "`1234567890-=";
const SymbolsShifted = "~!@#$%^&()_+";

fn getCharFromScanCode(code: u8) ?u8 {
    if (code >= 0x80) return null;

    const idx: usize = code;
    if (idx >= 0x02 and idx <= 0x0B) {
        const num_idx: usize = idx - 2;
        if (shift_state == .shift) {
            return SymbolsShifted[num_idx];
        }
        return Numbers[num_idx];
    }

    if (idx >= 0x10 and idx <= 0x2C) {
        const letter_idx: usize = idx - 0x10;
        if (shift_state == .shift or caps_lock) {
            return UppercaseLetters[letter_idx];
        }
        return LowercaseLetters[letter_idx];
    }

    switch (@as(ScanCode, @enumFromInt(code))) {
        .KEY_SPACE => return ' ',
        .KEY_ENTER => return '\n',
        .KEY_TAB => return '\t',
        .KEY_BACKSPACE => return 0x08,
        .KEY_MINUS => return if (shift_state == .shift) '_' else '-',
        .KEY_EQUALS => return if (shift_state == .shift) '+' else '=',
        .KEY_BRACKET_LEFT => return if (shift_state == .shift) '{' else '[',
        .KEY_BRACKET_RIGHT => return if (shift_state == .shift) '}' else ']',
        .KEY_BACKSLASH => return if (shift_state == .shift) '|' else '\\',
        .KEY_SEMICOLON => return if (shift_state == .shift) ':' else ';',
        .KEY_APOSTROPHE => return if (shift_state == .shift) '"' else '\'',
        .KEY_GRAVE => return if (shift_state == .shift) '~' else '`',
        .KEY_COMMA => return if (shift_state == .shift) '<' else ',',
        .KEY_PERIOD => return if (shift_state == .shift) '>' else '.',
        .KEY_SLASH => return if (shift_state == .shift) '?' else '/',
        .KEY_CAPS_LOCK => {
            caps_lock = !caps_lock;
            return null;
        },
        .KEY_UP => return 0x01,
        .KEY_DOWN => return 0x02,
        .KEY_LEFT => return 0x03,
        .KEY_RIGHT => return 0x04,
        else => return null,
    }
}

pub fn initialize() void {
    idt.set_handler(33, keyboard_handler);
    initialized = true;
}

fn keyboard_handler(frame: *idt.InterruptFrame) void {
    _ = frame;
    const scancode: u8 = x86.inb(0x60);

    if (scancode & 0x80 != 0) {
        const key_up = scancode & 0x7F;
        switch (@as(ScanCode, @enumFromInt(key_up))) {
            .KEY_UP => shift_state = .none,
            else => {},
        }
        return;
    }

    switch (@as(ScanCode, @enumFromInt(scancode))) {
        .KEY_UP, .KEY_DOWN => shift_state = .shift,
        else => {
            if (getCharFromScanCode(scancode)) |c| {
                if (buffer_head != (buffer_tail + 1) % KEYBOARD_BUFFER_SIZE) {
                    buffer[buffer_head] = c;
                    buffer_head = (buffer_head + 1) % KEYBOARD_BUFFER_SIZE;
                }
            }
        },
    }
}

pub fn readChar() ?u8 {
    if (buffer_head == buffer_tail) return null;
    const c = buffer[buffer_tail];
    buffer_tail = (buffer_tail + 1) % KEYBOARD_BUFFER_SIZE;
    return c;
}

pub fn getBytesAvailable() usize {
    if (buffer_head >= buffer_tail) {
        return buffer_head - buffer_tail;
    }
    return KEYBOARD_BUFFER_SIZE - buffer_tail + buffer_head;
}