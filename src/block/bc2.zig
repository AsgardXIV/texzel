const std = @import("std");

const conversion = @import("../core/conversion.zig");

const bc1 = @import("bc1.zig");

const RGBA8U = @import("../pixel_formats.zig").RGBA8U;

pub const BC2Block = extern struct {
    pub const texel_width = 4;
    pub const texel_height = 4;
    pub const texel_count = texel_width * texel_height;

    pub const EncodeOptions = struct {};
    pub const DecodeOptions = struct {};

    alpha: u64 align(1),
    bc1_block: bc1.BC1Block align(1),

    pub fn decodeBlock(self: *const BC2Block, _: DecodeOptions) ![texel_count]RGBA8U {
        var texels = try self.bc1_block.decodeBlock(.{});

        var alpha_bits = self.alpha;
        inline for (0..texel_count) |i| {
            const alpha = @as(u4, @truncate(alpha_bits & 0b1111));
            texels[i].a = conversion.scaleBitWidth(alpha, @FieldType(RGBA8U, "a"));
            alpha_bits >>= 4;
        }

        return texels;
    }

    pub fn encodeBlock(comptime PixelFormat: type, raw_texels: [texel_count]PixelFormat, _: EncodeOptions) !BC2Block {
        var alpha_bits: u64 = 0;
        inline for (0..texel_count) |i| {
            const alpha4 = conversion.scaleBitWidth(raw_texels[i].a, u4);
            alpha_bits |= (@as(u64, alpha4) << (i * 4));
        }

        return .{
            .alpha = alpha_bits,
            .bc1_block = try bc1.BC1Block.encodeBlock(PixelFormat, raw_texels, .{ .allow_alpha = false }),
        };
    }
};

test "bc2 decompress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.bc2", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const decompress_result = try texzel.decode(allocator, .bc2, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0xA06DA43E;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/alpha_gradient.bc2", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 960,
            .height = 480,
        };

        const decompress_result = try texzel.decode(allocator, .bc2, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0x2C5BF7B8;

        try std.testing.expectEqual(expected_hash, hash);
    }
}

test "bc2 compress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const RawImageData = @import("../core/raw_image_data.zig").RawImageData;
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.rgba", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const rgba_image = try RawImageData(RGBA8U).initFromBuffer(allocator, dimensions, read_result);
        defer rgba_image.deinit();

        const compressed = try texzel.encode(allocator, .bc2, RGBA8U, rgba_image, .{});
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0x4643A07C;

        try std.testing.expectEqual(expected_hash, hash);
    }
}
