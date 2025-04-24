const std = @import("std");

const conversion = @import("../core/conversion.zig");

const bc4 = @import("bc4.zig");

const R8U = @import("../pixel_formats.zig").R8U;
const RG8U = @import("../pixel_formats.zig").RG8U;

pub const BC5Block = extern struct {
    pub const texel_width = 4;
    pub const texel_height = 4;
    pub const texel_count = texel_width * texel_height;

    pub const EncodeOptions = struct {};
    pub const DecodeOptions = struct {};

    channel_0: bc4.BC4Block align(1),
    channel_1: bc4.BC4Block align(1),

    pub fn decodeBlock(self: *const BC5Block, _: DecodeOptions) ![texel_count]RG8U {
        const channel0_texels = try self.channel_0.decodeBlock(.{});
        const channel1_texels = try self.channel_1.decodeBlock(.{});

        var texels: [texel_count]RG8U = @splat(RG8U{});

        inline for (0..texel_count) |i| {
            texels[i].r = conversion.scaleBitWidth(channel0_texels[i].r, @FieldType(RG8U, "r"));
            texels[i].g = conversion.scaleBitWidth(channel1_texels[i].r, @FieldType(RG8U, "g"));
        }

        return texels;
    }

    pub fn encodeBlock(comptime PixelFormat: type, raw_texels: [texel_count]PixelFormat, _: EncodeOptions) !BC5Block {
        // Copy and swizzle as needed
        var red_in_red: [texel_count]R8U = undefined;
        var green_in_red: [texel_count]R8U = undefined;
        inline for (0..texel_count) |i| {
            red_in_red[i] = conversion.convertTexel(raw_texels[i], R8U);

            green_in_red[i] = conversion.convertTexelWithSwizzle(raw_texels[i], R8U, struct {
                r: []const u8 = "g",
            });
        }

        // Compress both blocks
        return .{
            .channel_0 = try bc4.BC4Block.encodeBlock(R8U, red_in_red, .{}),
            .channel_1 = try bc4.BC4Block.encodeBlock(R8U, green_in_red, .{}),
        };
    }
};

test "bc5 decompress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.bc5", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const decompress_result = try texzel.decode(allocator, .bc5, RG8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0x991E7675;

        try std.testing.expectEqual(expected_hash, hash);
    }
}

test "bc5 compress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const RawImageData = @import("../core/raw_image_data.zig").RawImageData;
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.rg", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 2 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const rgba_image = try RawImageData(RG8U).initFromBuffer(allocator, dimensions, read_result);
        defer rgba_image.deinit();

        const compressed = try texzel.encode(allocator, .bc5, RG8U, rgba_image, .{});
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0x24153D17;

        try std.testing.expectEqual(expected_hash, hash);
    }
}
