const std = @import("std");
const Builder = std.Build;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86,
            .os_tag = .freestanding,
            .abi = .none,
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    const kernel_module = b.createModule(.{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "kernel/kmain.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const kernel = b.addExecutable(.{
        .name = "enochkernel",
        .root_module = kernel_module,
    });
    kernel.entry = .disabled;
    kernel.rdynamic = true;
    kernel.addAssemblyFile(.{ .src_path = .{ .owner = b, .sub_path = "kernel/boot.s" } });
    kernel.addAssemblyFile(.{ .src_path = .{ .owner = b, .sub_path = "kernel/gdt.s" } });
    kernel.addAssemblyFile(.{ .src_path = .{ .owner = b, .sub_path = "kernel/idt.s" } });
    kernel.addAssemblyFile(.{ .src_path = .{ .owner = b, .sub_path = "kernel/isr.s" } });
    kernel.setLinkerScript(.{ .src_path = .{ .owner = b, .sub_path = "kernel/linker.ld" } });

    const enochbrowse_module = b.createModule(.{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "apps/enochbrowse/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    const enochbrowse = b.addExecutable(.{
        .name = "enochbrowse",
        .root_module = enochbrowse_module,
    });
    enochbrowse.entry = .disabled;

    const enochfetch_module = b.createModule(.{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "apps/enochfetch/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    const enochfetch = b.addExecutable(.{
        .name = "enochfetch",
        .root_module = enochfetch_module,
    });
    enochfetch.entry = .disabled;

    const enochedit_module = b.createModule(.{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "apps/enochedit/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    const enochedit = b.addExecutable(.{
        .name = "enochedit",
        .root_module = enochedit_module,
    });
    enochedit.entry = .disabled;

    const iso_step = b.step("iso", "Build bootable ISO image");
    
    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", "iso_root/boot", "iso_root/initrd" });
    mkdir_cmd.step.dependOn(&kernel.step);

    const copy_kernel = b.addSystemCommand(&.{ "cp", "{s}", "iso_root/boot/enochkernel" });
    copy_kernel.addArtifactArg(kernel);
    copy_kernel.step.dependOn(&mkdir_cmd.step);

    const copy_browse = b.addSystemCommand(&.{ "cp", "{s}", "iso_root/initrd/enochbrowse" });
    copy_browse.addArtifactArg(enochbrowse);
    copy_browse.step.dependOn(&copy_kernel.step);

    const copy_fetch = b.addSystemCommand(&.{ "cp", "{s}", "iso_root/initrd/enochfetch" });
    copy_fetch.addArtifactArg(enochfetch);
    copy_fetch.step.dependOn(&copy_browse.step);

    const copy_edit = b.addSystemCommand(&.{ "cp", "{s}", "iso_root/initrd/enochedit" });
    copy_edit.addArtifactArg(enochedit);
    copy_edit.step.dependOn(&copy_fetch.step);

    const create_iso = b.addSystemCommand(&.{
        "mkisofs", "-J", "-R", "-b", "boot/enochkernel",
        "-c", "boot/boot.cat", "-no-emul-boot", "-boot-load-size", "4",
        "-boot-info-table", "-o", "EnochOS.iso", "iso_root",
    });
    create_iso.step.dependOn(&copy_edit.step);
    iso_step.dependOn(&create_iso.step);

    const qemu_step = b.step("run", "Run in QEMU");
    const run_qemu = b.addSystemCommand(&.{ "qemu-system-i386", "-kernel", "{s}", "-m", "256M", "-nographic" });
    run_qemu.addArtifactArg(kernel);
    run_qemu.step.dependOn(&kernel.step);
    qemu_step.dependOn(&run_qemu.step);

    b.default_step.dependOn(&kernel.step);
}
