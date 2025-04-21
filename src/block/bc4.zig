const std = @import("std");

const conversion = @import("../core/conversion.zig");
const helpers = @import("helpers.zig");

const R8U = @import("../core/texel_types.zig").R8U;

pub const BC4Block = extern struct {
    pub const texel_width = 4;
    pub const texel_height = 4;
    pub const texel_count = texel_width * texel_height;

    pub const EncodeOptions = struct {};
    pub const DecodeOptions = struct {};

    endpoint0: u8 align(1),
    endpoint1: u8 align(1),
    indices: [6]u8 align(1),

    pub fn decodeBlock(self: *const BC4Block, _: DecodeOptions) ![texel_count]R8U {
        var texels: [texel_count]R8U = @splat(R8U{});

        inline for (0..texel_count) |i| {
            const index = self.getIndex(i);
            const value = calculateValue(self.endpoint0, self.endpoint1, index);
            const real = conversion.scaleBitWidth(value, u8);
            texels[i] = .{
                .r = real,
            };
        }

        return texels;
    }

    pub fn encodeBlock(comptime TexelType: type, raw_texels: [texel_count]TexelType, _: EncodeOptions) !BC4Block {
        return computeBlock(TexelType, raw_texels);
    }

    fn computeBlock(comptime TexelType: type, raw_texels: [texel_count]TexelType) BC4Block {
        var min_endpoint: u8 = 255;
        var max_endpoint: u8 = 0;
        var texel_values: [texel_count]u8 = undefined;

        for (raw_texels, 0..) |texel, i| {
            const r = conversion.scaleBitWidth(texel.r, u8);
            texel_values[i] = r;
            if (r < min_endpoint) min_endpoint = r;
            if (r > max_endpoint) max_endpoint = r;
        }

        var candidate_blocks: [2]BC4Block = undefined;
        var best_error: u32 = std.math.maxInt(u32);
        var best_mode: usize = 5;

        for (0..2) |mode| {
            var block = &candidate_blocks[mode];

            const e0: u8 = if (mode == 0) max_endpoint else min_endpoint;
            const e1: u8 = if (mode == 0) min_endpoint else max_endpoint;

            var palette: [8]u8 = undefined;

            inline for (0..8) |i| {
                palette[i] = calculateValue(e0, e1, @intCast(i));
            }

            var total_error: u32 = 0;
            var indices: [texel_count]u3 = undefined;

            for (texel_values, 0..) |texel_value, i| {
                var best_index: u3 = 0;
                var best_index_error: u32 = std.math.maxInt(u32);

                inline for (0..8) |j| {
                    const err = @as(u32, @intCast(@abs(@as(i16, texel_value) - @as(i16, palette[j]))));
                    if (err < best_index_error) {
                        best_index_error = err;
                        best_index = @intCast(j);
                    }
                }

                indices[i] = best_index;
                total_error += best_index_error;
            }

            if (total_error < best_error) {
                best_error = total_error;
                block.endpoint0 = e0;
                block.endpoint1 = e1;
                best_mode = mode;

                var packed_indexes: u48 = 0;
                for (0..texel_count) |i| {
                    const best_index: u3 = indices[i];
                    const shifted: u48 = @as(u48, @intCast(best_index)) << @intCast(i * 3);
                    packed_indexes |= shifted;
                }
                block.indices = @bitCast(packed_indexes);
            }
        }

        return candidate_blocks[best_mode];
    }

    fn getIndex(self: *const BC4Block, texel_index: usize) u3 {
        const value: u48 = @bitCast(self.indices);
        const shift_amount: u6 = @intCast(3 * texel_index);
        const result = (value >> shift_amount) & 0b111;
        return @intCast(result);
    }

    pub fn calculateValue(endpoint0: u8, endpoint1: u8, selector: u8) u8 {
        if (selector == 0) return endpoint0;
        if (selector == 1) return endpoint1;

        if (endpoint0 > endpoint1) {
            return switch (selector) {
                2 => helpers.mixValue(u8, endpoint0, endpoint1, 6, 1),
                3 => helpers.mixValue(u8, endpoint0, endpoint1, 5, 2),
                4 => helpers.mixValue(u8, endpoint0, endpoint1, 4, 3),
                5 => helpers.mixValue(u8, endpoint0, endpoint1, 3, 4),
                6 => helpers.mixValue(u8, endpoint0, endpoint1, 2, 5),
                7 => helpers.mixValue(u8, endpoint0, endpoint1, 1, 6),
                else => unreachable,
            };
        } else {
            return switch (selector) {
                2 => helpers.mixValue(u8, endpoint0, endpoint1, 4, 1),
                3 => helpers.mixValue(u8, endpoint0, endpoint1, 3, 2),
                4 => helpers.mixValue(u8, endpoint0, endpoint1, 2, 3),
                5 => helpers.mixValue(u8, endpoint0, endpoint1, 1, 4),
                6 => return 0,
                7 => return 255,
                else => unreachable,
            };
        }
    }
};

test "bc4 decompress" {
    const Dimensions = @import("../core/Dimensions.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.bc4", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const decompress_result = try helpers.decodeBlock(allocator, BC4Block, R8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0x1886221C;

        try std.testing.expectEqual(expected_hash, hash);
    }
}

test "bc4 compress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const RawImageData = @import("../core/raw_image_data.zig").RawImageData;

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.r", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 2 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const rgba_image = try RawImageData(R8U).initFromBuffer(allocator, dimensions, read_result);
        defer rgba_image.deinit();

        const compressed = try helpers.encodeBlock(allocator, BC4Block, R8U, rgba_image, .{});
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0xE732B20B;

        try std.testing.expectEqual(expected_hash, hash);
    }
}
