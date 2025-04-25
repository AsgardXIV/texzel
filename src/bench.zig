const std = @import("std");
const texzel = @import("texzel");

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    try benchDecode(
        allocator,
        1000,
        "resources/ziggy.bc1",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc1,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        1000,
        "resources/zero.bc1",
        texzel.core.Dimensions{ .width = 500, .height = 501 },
        texzel.pixel_formats.RGBA8U,
        .bc1,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        1000,
        "resources/ziggy.bc1a",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc1,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        1000,
        "resources/ziggy.bc2",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc2,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        1000,
        "resources/alpha_gradient.bc2",
        texzel.core.Dimensions{ .width = 960, .height = 480 },
        texzel.pixel_formats.RGBA8U,
        .bc2,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        1000,
        "resources/ziggy.bc3",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc3,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        1000,
        "resources/alpha_gradient.bc3",
        texzel.core.Dimensions{ .width = 960, .height = 480 },
        texzel.pixel_formats.RGBA8U,
        .bc3,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        1000,
        "resources/ziggy.bc4",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.R8U,
        .bc4,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        1000,
        "resources/ziggy.bc5",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RG8U,
        .bc5,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        100,
        "resources/night.bc6u",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA16F,
        .bc6,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        100,
        "resources/night.bc6s",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA16F,
        .bc6,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        100,
        "resources/ziggy.bc7",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .{},
        "",
    );

    try benchDecode(
        allocator,
        100,
        "resources/alpha_gradient.bc7",
        texzel.core.Dimensions{ .width = 960, .height = 480 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        1000,
        "resources/ziggy.rgba",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc1,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        100,
        "resources/night.rgba",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc1,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        1000,
        "resources/ziggy.rgba",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc2,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        100,
        "resources/alpha_gradient.rgba",
        texzel.core.Dimensions{ .width = 960, .height = 480 },
        texzel.pixel_formats.RGBA8U,
        .bc2,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        100,
        "resources/night.rgba",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc2,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        1000,
        "resources/ziggy.rgba",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc3,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        100,
        "resources/alpha_gradient.rgba",
        texzel.core.Dimensions{ .width = 960, .height = 480 },
        texzel.pixel_formats.RGBA8U,
        .bc3,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        100,
        "resources/night.rgba",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc3,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        1000,
        "resources/ziggy.r",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.R8U,
        .bc4,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        1000,
        "resources/ziggy.rg",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RG8U,
        .bc5,
        .{},
        "",
    );

    try benchEncode(
        allocator,
        1,
        "resources/night.rgba16f",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA16F,
        .bc6,
        .fast,
        "Fast",
    );

    try benchEncode(
        allocator,
        1,
        "resources/night.rgba16f",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA16F,
        .bc6,
        .basic,
        "Basic",
    );

    try benchEncode(
        allocator,
        1,
        "resources/night.rgba16f",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA16F,
        .bc6,
        .slow,
        "Slow",
    );

    try benchEncode(
        allocator,
        1,
        "resources/night.rgba",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .opaque_fast,
        "Fast Opaque",
    );

    try benchEncode(
        allocator,
        1,
        "resources/night.rgba",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .opaque_fast,
        "Basic Opaque",
    );

    try benchEncode(
        allocator,
        1,
        "resources/night.rgba",
        texzel.core.Dimensions{ .width = 1024, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .opaque_fast,
        "Slow Opaque",
    );

    try benchEncode(
        allocator,
        1,
        "resources/ziggy.rgba",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .alpha_fast,
        "Fast Alpha",
    );

    try benchEncode(
        allocator,
        1,
        "resources/ziggy.rgba",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .alpha_basic,
        "Basic Alpha",
    );

    try benchEncode(
        allocator,
        1,
        "resources/ziggy.rgba",
        texzel.core.Dimensions{ .width = 512, .height = 512 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .alpha_slow,
        "Slow Alpha",
    );

    try benchEncode(
        allocator,
        1,
        "resources/alpha_gradient.rgba",
        texzel.core.Dimensions{ .width = 960, .height = 480 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .alpha_fast,
        "Fast Alpha",
    );

    try benchEncode(
        allocator,
        1,
        "resources/alpha_gradient.rgba",
        texzel.core.Dimensions{ .width = 960, .height = 480 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .alpha_basic,
        "Basic Alpha",
    );

    try benchEncode(
        allocator,
        1,
        "resources/alpha_gradient.rgba",
        texzel.core.Dimensions{ .width = 960, .height = 480 },
        texzel.pixel_formats.RGBA8U,
        .bc7,
        .alpha_slow,
        "Slow Alpha",
    );
}

fn benchDecode(
    allocator: std.mem.Allocator,
    repeat: usize,
    path: []const u8,
    dimensions: texzel.core.Dimensions,
    comptime PixelFormat: anytype,
    comptime codec: texzel.Codecs,
    options: codec.blockType().DecodeOptions,
    comptime notes: []const u8,
) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const read_result = try file.readToEndAlloc(allocator, 5 << 20);
    defer allocator.free(read_result);

    const start_time = std.time.milliTimestamp();

    for (0..repeat) |_| {
        const decompress_result = try texzel.decode(allocator, codec, PixelFormat, dimensions, read_result, options);
        defer decompress_result.deinit();
    }

    const end_time = std.time.milliTimestamp();
    std.log.info("Ran {s}{s} decode x {d} on {s} in {d}ms", .{ @tagName(codec), if (notes.len > 0) " (" ++ notes ++ ")" else "", repeat, path, end_time - start_time });
}

fn benchEncode(
    allocator: std.mem.Allocator,
    repeat: usize,
    path: []const u8,
    dimensions: texzel.core.Dimensions,
    comptime PixelFormat: anytype,
    comptime codec: texzel.Codecs,
    options: codec.blockType().EncodeOptions,
    comptime notes: []const u8,
) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const read_result = try file.readToEndAlloc(allocator, 5 << 20);
    defer allocator.free(read_result);

    const rgba_image = try texzel.rawImageFromBuffer(allocator, PixelFormat, dimensions, read_result);
    defer rgba_image.deinit();

    const start_time = std.time.milliTimestamp();

    for (0..repeat) |_| {
        const compressed = try texzel.encode(allocator, codec, PixelFormat, rgba_image, options);
        defer allocator.free(compressed);
    }

    const end_time = std.time.milliTimestamp();
    std.log.info("Ran {s}{s} encode x {d} on {s} in {d}ms", .{ @tagName(codec), if (notes.len > 0) " (" ++ notes ++ ")" else "", repeat, path, end_time - start_time });
}
