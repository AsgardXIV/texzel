const std = @import("std");

const conversion = @import("../core/conversion.zig");
const helpers = @import("helpers.zig");
const RGBA8U = @import("../pixel_formats.zig").RGBA8U;

pub const BC1Block = extern struct {
    pub const texel_width = 4;
    pub const texel_height = 4;
    pub const texel_count = texel_width * texel_height;

    pub const EncodeOptions = struct {
        allow_alpha: bool = true,
    };

    pub const DecodeOptions = struct {};

    colors: [2]Color align(1),
    indices: u32 align(1),

    const Color = packed struct {
        r: u5,
        g: u6,
        b: u5,
    };

    const ColorWithAlphaBit = packed struct {
        r: u5,
        g: u6,
        b: u5,
        a: u1,
    };

    pub fn decodeBlock(self: *const BC1Block, _: DecodeOptions) ![texel_count]RGBA8U {
        var solved_colors: [4]RGBA8U = undefined;

        inline for (0..2) |i| {
            const color = self.colors[i];
            solved_colors[i] = conversion.convertTexel(color, RGBA8U);
        }

        const color0_bits = @as(u16, @bitCast(self.colors[0]));
        const color1_bits = @as(u16, @bitCast(self.colors[1]));

        if (color0_bits > color1_bits) {
            solved_colors[2] = helpers.mixStruct(solved_colors[0], solved_colors[1], 2, 1);
            solved_colors[3] = helpers.mixStruct(solved_colors[0], solved_colors[1], 1, 2);
        } else {
            solved_colors[2] = helpers.mixStruct(solved_colors[0], solved_colors[1], 1, 1);
            solved_colors[3] = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
        }

        var mapped: [texel_count]RGBA8U = undefined;
        var index_bits = self.indices;
        inline for (0..texel_count) |i| {
            const index = @as(u2, @truncate(index_bits & 0b11));
            mapped[i] = solved_colors[index];
            index_bits >>= 2;
        }

        return mapped;
    }

    pub fn encodeBlock(comptime PixelFormat: type, raw_texels: [texel_count]PixelFormat, options: EncodeOptions) !BC1Block {
        // Quantize the texels to 5-6-5-1 format
        var texels: [texel_count]ColorWithAlphaBit = undefined;
        inline for (raw_texels, 0..) |texel, i| {
            const color = conversion.convertTexel(texel, ColorWithAlphaBit);
            texels[i] = color;
        }

        // Compute the palette
        var palette = computePalette(texels, options.allow_alpha);

        // Determine best color for each texel
        var indices: u32 = 0;
        for (texels, 0..) |texel, i| {
            const closest_index = findClosestColorIndex(texel, palette[0..]);
            indices |= @as(u32, closest_index) << @intCast(i * 2);
        }

        return .{
            .colors = .{
                palette[0],
                palette[1],
            },
            .indices = indices,
        };
    }

    fn computePalette(texels: [texel_count]ColorWithAlphaBit, allow_alpha: bool) [4]Color {
        const first_color = conversion.convertTexel(texels[0], Color);

        var colors: [4]Color = undefined;

        var min_color = first_color;
        var max_color = first_color;

        var has_transparent = false;

        for (texels) |texel| {
            if (allow_alpha and texel.a == 0) {
                has_transparent = true;
                continue;
            }

            const color = conversion.convertTexel(texel, Color);

            if (compareColor(color, min_color) < 0) {
                min_color = color;
            }

            if (compareColor(color, max_color) > 0) {
                max_color = color;
            }
        }

        colors[0] = min_color;
        colors[1] = max_color;

        var color0_bits = @as(u16, @bitCast(colors[0]));
        var color1_bits = @as(u16, @bitCast(colors[1]));

        const should_flip =
            (!has_transparent and color0_bits <= color1_bits) or
            (has_transparent and color0_bits > color1_bits);

        if (should_flip) {
            std.mem.swap(u16, &color0_bits, &color1_bits);
        }

        if (!has_transparent and color0_bits == color1_bits) {
            if (color0_bits == std.math.maxInt(u16)) {
                color1_bits -= 1;
            } else {
                color0_bits += 1;
            }
        }

        colors[0] = @bitCast(color0_bits);
        colors[1] = @bitCast(color1_bits);

        if (color0_bits > color1_bits) {
            colors[2] = helpers.mixStruct(colors[0], colors[1], 2, 1);
            colors[3] = helpers.mixStruct(colors[0], colors[1], 1, 2);
        } else {
            colors[2] = helpers.mixStruct(colors[0], colors[1], 1, 1);
            colors[3] = .{ .r = 0, .g = 0, .b = 0 };
        }

        return colors;
    }

    fn compareColor(a: Color, b: Color) i32 {
        const a_total = @as(i32, a.r) + @as(i32, a.g) + @as(i32, a.b);
        const b_total = @as(i32, b.r) + @as(i32, b.g) + @as(i32, b.b);
        return a_total - b_total;
    }

    fn findClosestColorIndex(texel: ColorWithAlphaBit, colors: []Color) u2 {
        var closest_index: u2 = 0;
        var closest_distance: u32 = std.math.maxInt(u32);

        if (texel.a == 0) {
            return 3;
        }

        const quantized_texel = conversion.convertTexel(texel, Color);

        for (colors, 0..) |color, i| {
            const distance = colorDistance(quantized_texel, color);
            if (distance < closest_distance) {
                closest_distance = distance;
                closest_index = @as(u2, @intCast(i));
            }
        }

        return closest_index;
    }

    fn colorDistance(a: Color, b: Color) u32 {
        const dr = @as(i32, a.r) - @as(i32, b.r);
        const dg = @as(i32, a.g) - @as(i32, b.g);
        const db = @as(i32, a.b) - @as(i32, b.b);
        return @as(u32, @intCast(dr * dr + dg * dg + db * db));
    }
};

test "bc1 decompress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.bc1", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const decompress_result = try texzel.decode(allocator, .bc1, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0x8A22A5C;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/zero.bc1", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 500,
            .height = 501,
        };

        const decompress_result = try texzel.decode(allocator, .bc1, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0xC1F2088B;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.bc1a", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const decompress_result = try texzel.decode(allocator, .bc1, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0xE4CDA5D6;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.bc1n", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const decompress_result = try texzel.decode(allocator, .bc1, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0xB44C6E1E;

        try std.testing.expectEqual(expected_hash, hash);
    }
}

test "bc1 compress" {
    const texzel = @import("../texzel.zig");
    const RawImageData = @import("../core/raw_image_data.zig").RawImageData;
    const Dimensions = @import("../core/Dimensions.zig");

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

        const compressed = try texzel.encode(allocator, .bc1, RGBA8U, rgba_image, .{});
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0x5EBD455;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/zero.rgba", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 500,
            .height = 501,
        };

        const rgba_image = try RawImageData(RGBA8U).initFromBuffer(allocator, dimensions, read_result);
        defer rgba_image.deinit();

        const compressed = try texzel.encode(allocator, .bc1, RGBA8U, rgba_image, .{});
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0x250BF9E6;

        try std.testing.expectEqual(expected_hash, hash);
    }
}
