const std = @import("std");

const microzig = @import("microzig/src/main.zig");

pub fn build(b: *std.build.Builder) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = try microzig.addEmbeddedExecutable(
        b,
        "zigthesizer.elf",
        "src/main.zig",
        .{ .board = microzig.boards.stm32f4discovery },
        .{},
    );

    exe.setBuildMode(mode);
    exe.install();

    const bin = b.addInstallRaw(exe, "zigthesizer.bin", .{});
    b.getInstallStep().dependOn(&bin.step);

    const flash_cmd = b.addSystemCommand(&[_][]const u8{
        "st-flash",
        "write",
        b.getInstallPath(bin.dest_dir, bin.dest_filename),
        "0x8000000",
    });
    flash_cmd.step.dependOn(&bin.step);
    const flash_step = b.step("flash", "Flash and run the app on your STM32F4Discovery");
    flash_step.dependOn(&flash_cmd.step);
}
