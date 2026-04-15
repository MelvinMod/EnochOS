const x86 = @import("x86.zig");

const GDT_ENTRY_CODE = 0x00;
const GDT_ENTRY_DATA = 0x01;
const GDT_ENTRY_TSS = 0x02;

const GDT_FLAGS_PRESENT = 0x80;
const GDT_FLAGS_DPL_USER = 0x60;
const GDT_FLAGS_DPL_KERNEL = 0x00;
const GDT_FLAGS_TYPE_CODE = 0x10;
const GDT_FLAGS_TYPE_DATA = 0x10;
const GDT_FLAGS_TYPE_TSS = 0x09;
const GDT_FLAGS_DB = 0x40;
const GDT_FLAGS_GRANULARITY = 0x80;

const GDT_FLAGS_CODE = GDT_FLAGS_PRESENT | GDT_FLAGS_DPL_KERNEL | GDT_FLAGS_TYPE_CODE | GDT_FLAGS_DB | GDT_FLAGS_GRANULARITY;
const GDT_FLAGS_DATA = GDT_FLAGS_PRESENT | GDT_FLAGS_DPL_KERNEL | GDT_FLAGS_TYPE_DATA | GDT_FLAGS_DB | GDT_FLAGS_GRANULARITY;

const GDTEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    type: u8,
    limit_high: u4,
    flags: u4,
    base_high: u8,
};

const GDTPointer = packed struct {
    limit: u16,
    base: u32,
};

const GDT_SIZE = 6;
var gdt: [GDT_SIZE]GDTEntry = undefined;
var gdt_ptr: GDTPointer = undefined;

extern fn lgdt(*const GDTPointer) void;
extern fn far_jump() void;
extern fn load_data_segments() void;

pub fn initialize() void {
    gdt[0] = GDTEntry{
        .limit_low = 0,
        .base_low = 0,
        .base_mid = 0,
        .type = 0,
        .limit_high = 0,
        .flags = 0,
        .base_high = 0,
    };

    gdt[GDT_ENTRY_CODE] = GDTEntry{
        .limit_low = 0xFFFF,
        .base_low = 0,
        .base_mid = 0,
        .type = GDT_FLAGS_CODE & 0x0F,
        .limit_high = (@as(u4, @truncate(GDT_FLAGS_CODE >> 4))) & 0x0F,
        .flags = (@as(u4, @truncate(GDT_FLAGS_CODE >> 4))) & 0x0F,
        .base_high = 0,
    };

    gdt[GDT_ENTRY_DATA] = GDTEntry{
        .limit_low = 0xFFFF,
        .base_low = 0,
        .base_mid = 0,
        .type = GDT_FLAGS_DATA & 0x0F,
        .limit_high = (@as(u4, @truncate(GDT_FLAGS_DATA >> 4))) & 0x0F,
        .flags = (@as(u4, @truncate(GDT_FLAGS_DATA >> 4))) & 0x0F,
        .base_high = 0,
    };

    gdt_ptr = GDTPointer{
        .limit = @as(u16, @truncate(@sizeOf(@TypeOf(gdt)))) - 1,
        .base = @intFromPtr(&gdt),
    };

    lgdt(&gdt_ptr);
    far_jump();
    load_data_segments();
}
