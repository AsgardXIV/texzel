const std = @import("std");

const conversion = @import("../core/conversion.zig");

const bc1 = @import("bc1.zig");
const bc4 = @import("bc4.zig");

const R8U = @import("../pixel_formats.zig").R8U;
const RGBA8U = @import("../pixel_formats.zig").RGBA8U;

pub const BC3Block = extern struct {
    pub const texel_width = 4;
    pub const texel_height = 4;
    pub const texel_count = texel_width * texel_height;

    pub const EncodeOptions = struct {};
    pub const DecodeOptions = struct {};

    bc4_block: bc4.BC4Block align(1),
    bc1_block: bc1.BC1Block align(1),

    pub fn decodeBlock(self: *const BC3Block, _: DecodeOptions) ![texel_count]RGBA8U {
        var texels = try self.bc1_block.decodeBlock(.{});
        const alpha_texels = try self.bc4_block.decodeBlock(.{});

        inline for (0..texel_count) |i| {
            texels[i].a = conversion.scaleBitWidth(alpha_texels[i].r, @FieldType(RGBA8U, "a"));
        }

        return texels;
    }

    pub fn encodeBlock(comptime PixelFormat: type, raw_texels: [texel_count]PixelFormat, _: EncodeOptions) !BC3Block {
        // Swizzle the alpha channel into the red channel for BC4 compression

        var alpha_in_red: [texel_count]R8U = undefined;
        inline for (0..texel_count) |i| {
            alpha_in_red[i] = conversion.convertTexelWithSwizzle(raw_texels[i], R8U, struct {
                r: []const u8 = "a",
            });
        }

        // Compress both blocks
        return .{
            .bc4_block = try bc4.BC4Block.encodeBlock(R8U, alpha_in_red, .{}),
            .bc1_block = try bc1.BC1Block.encodeBlock(PixelFormat, raw_texels, .{ .allow_alpha = true }),
        };
    }
};

test "bc3 decompress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.bc3", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const decompress_result = try texzel.decode(allocator, .bc3, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0xA06DA43E;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/alpha_gradient.bc3", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 960,
            .height = 480,
        };

        const decompress_result = try texzel.decode(allocator, .bc3, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0xD4543717;

        try std.testing.expectEqual(expected_hash, hash);
    }
}

test "bc3 compress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const RawImageData = @import("../core/raw_image_data.zig").RawImageData;
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.rgba", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 2 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const rgba_image = try RawImageData(RGBA8U).initFromBuffer(allocator, dimensions, read_result);
        defer rgba_image.deinit();

        const compressed = try texzel.encode(allocator, .bc3, RGBA8U, rgba_image, .{});
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0x19AF3971;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/alpha_gradient.rgba", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 2 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 960,
            .height = 480,
        };

        const rgba_image = try RawImageData(RGBA8U).initFromBuffer(allocator, dimensions, read_result);
        defer rgba_image.deinit();

        const compressed = try texzel.encode(allocator, .bc3, RGBA8U, rgba_image, .{});
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0x8211395E;

        try std.testing.expectEqual(expected_hash, hash);
    }
}
