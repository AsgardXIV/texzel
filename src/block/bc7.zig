// Portions of this file are based on bcdec and block_compression.
// See THIRD_PARTY_LICENSES.md in this project for more information.

const std = @import("std");

const conversion = @import("../core/conversion.zig");

const RGBA8U = @import("../pixel_formats.zig").RGBA8U;

pub const BC7Block = extern struct {
    pub const texel_width = 4;
    pub const texel_height = 4;
    pub const texel_count = texel_width * texel_height;

    pub const DecodeOptions = struct {};

    data: [16]u8,

    pub fn decodeBlock(self: *const BC7Block, _: DecodeOptions) ![texel_count]RGBA8U {
        var texels: [texel_count]RGBA8U = @splat(RGBA8U{});

        var buffer = std.io.fixedBufferStream(&self.data);
        var reader = std.io.bitReader(.little, buffer.reader().any());

        // Determine mode
        var mode: u8 = 0;
        while (true) {
            const flag = try reader.readBitsNoEof(u1, 1);
            if (flag == 0 and mode < 8) {
                mode += 1;
            } else {
                break;
            }
        }

        // Early exit for invalid modes
        if (mode >= 8) {
            return texels;
        }

        var partition: u32 = 0;
        var num_partitions: u32 = 1;
        var rotation: u32 = 0;
        var index_selection_bit: u1 = 0;

        if (mode == 0 or mode == 1 or mode == 2 or mode == 3 or mode == 7) {
            num_partitions = if (mode == 0 or mode == 2) 3 else 2;
            partition = try reader.readBitsNoEof(u32, if (mode == 0) 4 else 6);
        }

        const num_endpoints = num_partitions * 2;

        if (mode == 4 or mode == 5) {
            rotation = try reader.readBitsNoEof(u32, 2);
            if (mode == 4) {
                index_selection_bit = try reader.readBitsNoEof(u1, 1);
            }
        }

        var endpoints: [6][4]u32 = @splat(@splat(0));

        // RGB
        for (0..3) |i| {
            for (0..num_endpoints) |j| {
                const bit_count = actual_bits_count[0][mode];
                endpoints[j][i] = try reader.readBitsNoEof(u32, bit_count);
            }
        }

        // Alpha
        if (actual_bits_count[1][mode] != 0) {
            for (0..num_endpoints) |j| {
                const bit_count = actual_bits_count[1][mode];
                endpoints[j][3] = try reader.readBitsNoEof(u32, bit_count);
            }
        }

        //P-bit modes
        if (mode == 0 or mode == 1 or mode == 3 or mode == 6 or mode == 7) {
            for (endpoints[0..num_endpoints]) |*endpoint| {
                for (endpoint) |*e| {
                    e.* <<= 1;
                }
            }

            if (mode == 1) {
                const i = try reader.readBitsNoEof(u32, 1);
                const j = try reader.readBitsNoEof(u32, 1);

                // RGB component-wise insert pbits
                for (0..3) |k| {
                    endpoints[0][k] |= i;
                    endpoints[1][k] |= i;
                    endpoints[2][k] |= j;
                    endpoints[3][k] |= j;
                }
            } else if (mode_has_p_bits & (@as(u8, 1) << @intCast(mode)) != 0) {
                // Unique P-bit per endpoint
                for (endpoints[0..num_endpoints]) |*endpoint| {
                    const j = try reader.readBitsNoEof(u32, 1);
                    for (endpoint) |*e| {
                        e.* |= j;
                    }
                }
            }
        }

        // Component-wise precision adjustment
        for (0..num_endpoints) |i| {
            // Get color components precision including pbit
            const j = actual_bits_count[0][mode] + ((mode_has_p_bits >> @intCast(mode)) & 1);

            // RGB components
            for (0..3) |k| {
                endpoints[i][k] <<= @intCast(8 - j);
                endpoints[i][k] |= endpoints[i][k] >> @intCast(j);
            }

            // Get alpha component precision including pbit
            const l = actual_bits_count[1][mode] + ((mode_has_p_bits >> @intCast(mode)) & 1);
            endpoints[i][3] <<= @intCast(8 - l);
            endpoints[i][3] |= endpoints[i][3] >> @intCast(l);
        }

        // If this mode does not explicitly define the alpha component, set alpha to 255 (1.0)
        if (actual_bits_count[1][mode] == 0) {
            for (endpoints[0..num_endpoints]) |*endpoint| {
                endpoint[3] = 255;
            }
        }

        // Determine weights tables
        const index_bits: u16 = switch (mode) {
            0, 1 => 3,
            6 => 4,
            else => 2,
        };

        const index_bits2: u16 = switch (mode) {
            4 => 3,
            5 => 2,
            else => 0,
        };

        const weights: []const u32 = switch (index_bits) {
            2 => &weight2,
            3 => &weight3,
            else => &weight4,
        };

        const weights2: []const u32 = switch (index_bits2) {
            2 => &weight2,
            else => &weight3,
        };

        // Collect indices in two passes
        var indices: [texel_width][texel_height]u32 = @splat(@splat(0));

        // Pass #1: collecting color indices
        for (0..texel_height) |i| {
            for (0..texel_width) |j| {
                const partition_set: u8 = if (num_partitions == 1)
                    if (i | j == 0) 128 else 0
                else
                    partition_sets[num_partitions - 2][partition][i][j];

                var idx_bits = index_bits;

                // Fix-up index is specified with one less bit
                // The fix-up index for subset 0 is always index 0
                if (partition_set & 0x80 != 0) {
                    idx_bits -= 1;
                }

                indices[i][j] = try reader.readBitsNoEof(u32, idx_bits);
            }
        }

        // Pass #2: reading alpha indices (if any) and interpolating & rotating
        for (0..texel_height) |i| {
            for (0..texel_width) |j| {
                const partition_set: u8 = if (num_partitions == 1)
                    if (i | j == 0) 128 else 0
                else
                    partition_sets[num_partitions - 2][partition][i][j];

                const partition_idx: usize = partition_set & 0x03;

                const index = indices[i][j];

                var resolved: RGBA8U = undefined;

                if (index_bits2 == 0) {
                    resolved.r = interpolate(endpoints[partition_idx * 2][0], endpoints[partition_idx * 2 + 1][0], weights, index);
                    resolved.g = interpolate(endpoints[partition_idx * 2][1], endpoints[partition_idx * 2 + 1][1], weights, index);
                    resolved.b = interpolate(endpoints[partition_idx * 2][2], endpoints[partition_idx * 2 + 1][2], weights, index);
                    resolved.a = interpolate(endpoints[partition_idx * 2][3], endpoints[partition_idx * 2 + 1][3], weights, index);
                } else {
                    const index2 = try reader.readBitsNoEof(u32, if (i | j == 0) index_bits2 - 1 else index_bits2);

                    if (index_selection_bit == 0) {
                        resolved.r = interpolate(endpoints[partition_idx * 2][0], endpoints[partition_idx * 2 + 1][0], weights, index);
                        resolved.g = interpolate(endpoints[partition_idx * 2][1], endpoints[partition_idx * 2 + 1][1], weights, index);
                        resolved.b = interpolate(endpoints[partition_idx * 2][2], endpoints[partition_idx * 2 + 1][2], weights, index);
                        resolved.a = interpolate(endpoints[partition_idx * 2][3], endpoints[partition_idx * 2 + 1][3], weights2, index2);
                    } else {
                        resolved.r = interpolate(endpoints[partition_idx * 2][0], endpoints[partition_idx * 2 + 1][0], weights2, index2);
                        resolved.g = interpolate(endpoints[partition_idx * 2][1], endpoints[partition_idx * 2 + 1][1], weights2, index2);
                        resolved.b = interpolate(endpoints[partition_idx * 2][2], endpoints[partition_idx * 2 + 1][2], weights2, index2);
                        resolved.a = interpolate(endpoints[partition_idx * 2][3], endpoints[partition_idx * 2 + 1][3], weights, index);
                    }
                }

                // Handle rotation
                switch (rotation) {
                    1 => std.mem.swap(u8, &resolved.a, &resolved.r), // 01 – Block format is Scalar(R) Vector(AGB) - swap A and R
                    2 => std.mem.swap(u8, &resolved.a, &resolved.g), // 10 – Block format is Scalar(G) Vector(RAB) - swap A and G
                    3 => std.mem.swap(u8, &resolved.a, &resolved.b), // 11 - Block format is Scalar(B) Vector(RGA) - swap A and B
                    else => {},
                }

                // Write out texel
                texels[i * texel_width + j] = resolved;
            }
        }

        return texels;
    }

    fn interpolate(a: u32, b: u32, weights: []const u32, index: u32) u8 {
        const idx: usize = @intCast(index);
        const result = (a * (64 - weights[idx]) + b * weights[idx] + 32) >> 6;
        return @intCast(result);
    }
};

const actual_bits_count: [2][8]u8 = .{
    .{ 4, 6, 5, 7, 5, 7, 7, 5 }, // RGBA
    .{ 0, 0, 0, 0, 6, 8, 7, 5 }, // Alpha
};

const mode_has_p_bits: u8 = 0b11001011;

const weight2 = [_]u32{ 0, 21, 43, 64 };
const weight3 = [_]u32{ 0, 9, 18, 27, 37, 46, 55, 64 };
const weight4 = [_]u32{ 0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64 };

const partition_sets = [2][64][4][4]u8{
    // Partition table for 2-subset BPTC
    .{
        .{ .{ 128, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 129 } }, //  0
        .{ .{ 128, 0, 0, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 129 } }, //  1
        .{ .{ 128, 1, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 0, 1, 1, 129 } }, //  2
        .{ .{ 128, 0, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 1, 1, 129 } }, //  3
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 1, 129 } }, //  4
        .{ .{ 128, 0, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, //  5
        .{ .{ 128, 0, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, //  6
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 1, 1, 129 } }, //  7
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 1, 129 } }, //  8
        .{ .{ 128, 0, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, //  9
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, // 10
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 1, 1, 129 } }, // 11
        .{ .{ 128, 0, 0, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, // 12
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, // 13
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, // 14
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 1, 1, 1, 129 } }, // 15
        .{ .{ 128, 0, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 1, 1, 1, 0 }, .{ 1, 1, 1, 129 } }, // 16
        .{ .{ 128, 1, 129, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 } }, // 17
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 129, 0, 0, 0 }, .{ 1, 1, 1, 0 } }, // 18
        .{ .{ 128, 1, 129, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 } }, // 19
        .{ .{ 128, 0, 129, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 } }, // 20
        .{ .{ 128, 0, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 129, 1, 0, 0 }, .{ 1, 1, 1, 0 } }, // 21
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 129, 0, 0, 0 }, .{ 1, 1, 0, 0 } }, // 22
        .{ .{ 128, 1, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 0, 129 } }, // 23
        .{ .{ 128, 0, 129, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 } }, // 24
        .{ .{ 128, 0, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 129, 0, 0, 0 }, .{ 1, 1, 0, 0 } }, // 25
        .{ .{ 128, 1, 129, 0 }, .{ 0, 1, 1, 0 }, .{ 0, 1, 1, 0 }, .{ 0, 1, 1, 0 } }, // 26
        .{ .{ 128, 0, 129, 1 }, .{ 0, 1, 1, 0 }, .{ 0, 1, 1, 0 }, .{ 1, 1, 0, 0 } }, // 27
        .{ .{ 128, 0, 0, 1 }, .{ 0, 1, 1, 1 }, .{ 129, 1, 1, 0 }, .{ 1, 0, 0, 0 } }, // 28
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 129, 1, 1, 1 }, .{ 0, 0, 0, 0 } }, // 29
        .{ .{ 128, 1, 129, 1 }, .{ 0, 0, 0, 1 }, .{ 1, 0, 0, 0 }, .{ 1, 1, 1, 0 } }, // 30
        .{ .{ 128, 0, 129, 1 }, .{ 1, 0, 0, 1 }, .{ 1, 0, 0, 1 }, .{ 1, 1, 0, 0 } }, // 31
        .{ .{ 128, 1, 0, 1 }, .{ 0, 1, 0, 1 }, .{ 0, 1, 0, 1 }, .{ 0, 1, 0, 129 } }, // 32
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 0, 0, 0, 0 }, .{ 1, 1, 1, 129 } }, // 33
        .{ .{ 128, 1, 0, 1 }, .{ 1, 0, 129, 0 }, .{ 0, 1, 0, 1 }, .{ 1, 0, 1, 0 } }, // 34
        .{ .{ 128, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 129, 1, 0, 0 }, .{ 1, 1, 0, 0 } }, // 35
        .{ .{ 128, 0, 129, 1 }, .{ 1, 1, 0, 0 }, .{ 0, 0, 1, 1 }, .{ 1, 1, 0, 0 } }, // 36
        .{ .{ 128, 1, 0, 1 }, .{ 0, 1, 0, 1 }, .{ 129, 0, 1, 0 }, .{ 1, 0, 1, 0 } }, // 37
        .{ .{ 128, 1, 1, 0 }, .{ 1, 0, 0, 1 }, .{ 0, 1, 1, 0 }, .{ 1, 0, 0, 129 } }, // 38
        .{ .{ 128, 1, 0, 1 }, .{ 1, 0, 1, 0 }, .{ 1, 0, 1, 0 }, .{ 0, 1, 0, 129 } }, // 39
        .{ .{ 128, 1, 129, 1 }, .{ 0, 0, 1, 1 }, .{ 1, 1, 0, 0 }, .{ 1, 1, 1, 0 } }, // 40
        .{ .{ 128, 0, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 129, 1, 0, 0 }, .{ 1, 0, 0, 0 } }, // 41
        .{ .{ 128, 0, 129, 1 }, .{ 0, 0, 1, 0 }, .{ 0, 1, 0, 0 }, .{ 1, 1, 0, 0 } }, // 42
        .{ .{ 128, 0, 129, 1 }, .{ 1, 0, 1, 1 }, .{ 1, 1, 0, 1 }, .{ 1, 1, 0, 0 } }, // 43
        .{ .{ 128, 1, 129, 0 }, .{ 1, 0, 0, 1 }, .{ 1, 0, 0, 1 }, .{ 0, 1, 1, 0 } }, // 44
        .{ .{ 128, 0, 1, 1 }, .{ 1, 1, 0, 0 }, .{ 1, 1, 0, 0 }, .{ 0, 0, 1, 129 } }, // 45
        .{ .{ 128, 1, 1, 0 }, .{ 0, 1, 1, 0 }, .{ 1, 0, 0, 1 }, .{ 1, 0, 0, 129 } }, // 46
        .{ .{ 128, 0, 0, 0 }, .{ 0, 1, 129, 0 }, .{ 0, 1, 1, 0 }, .{ 0, 0, 0, 0 } }, // 47
        .{ .{ 128, 1, 0, 0 }, .{ 1, 1, 129, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 0, 0, 0 } }, // 48
        .{ .{ 128, 0, 129, 0 }, .{ 0, 1, 1, 1 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 0 } }, // 49
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 129, 0 }, .{ 0, 1, 1, 1 }, .{ 0, 0, 1, 0 } }, // 50
        .{ .{ 128, 0, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 129, 1, 1, 0 }, .{ 0, 1, 0, 0 } }, // 51
        .{ .{ 128, 1, 1, 0 }, .{ 1, 1, 0, 0 }, .{ 1, 0, 0, 1 }, .{ 0, 0, 1, 129 } }, // 52
        .{ .{ 128, 0, 1, 1 }, .{ 0, 1, 1, 0 }, .{ 1, 1, 0, 0 }, .{ 1, 0, 0, 129 } }, // 53
        .{ .{ 128, 1, 129, 0 }, .{ 0, 0, 1, 1 }, .{ 1, 0, 0, 1 }, .{ 1, 1, 0, 0 } }, // 54
        .{ .{ 128, 0, 129, 1 }, .{ 1, 0, 0, 1 }, .{ 1, 1, 0, 0 }, .{ 0, 1, 1, 0 } }, // 55
        .{ .{ 128, 1, 1, 0 }, .{ 1, 1, 0, 0 }, .{ 1, 1, 0, 0 }, .{ 1, 0, 0, 129 } }, // 56
        .{ .{ 128, 1, 1, 0 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 1, 0, 0, 129 } }, // 57
        .{ .{ 128, 1, 1, 1 }, .{ 1, 1, 1, 0 }, .{ 1, 0, 0, 0 }, .{ 0, 0, 0, 129 } }, // 58
        .{ .{ 128, 0, 0, 1 }, .{ 1, 0, 0, 0 }, .{ 1, 1, 1, 0 }, .{ 0, 1, 1, 129 } }, // 59
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 129 } }, // 60
        .{ .{ 128, 0, 129, 1 }, .{ 0, 0, 1, 1 }, .{ 1, 1, 1, 1 }, .{ 0, 0, 0, 0 } }, // 61
        .{ .{ 128, 0, 129, 0 }, .{ 0, 0, 1, 0 }, .{ 1, 1, 1, 0 }, .{ 1, 1, 1, 0 } }, // 62
        .{ .{ 128, 1, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 1, 1, 1 }, .{ 0, 1, 1, 129 } }, // 63
    },
    // Partition table for 3-subset BPTC
    .{
        .{ .{ 128, 0, 1, 129 }, .{ 0, 0, 1, 1 }, .{ 0, 2, 2, 1 }, .{ 2, 2, 2, 130 } }, //  0
        .{ .{ 128, 0, 0, 129 }, .{ 0, 0, 1, 1 }, .{ 130, 2, 1, 1 }, .{ 2, 2, 2, 1 } }, //  1
        .{ .{ 128, 0, 0, 0 }, .{ 2, 0, 0, 1 }, .{ 130, 2, 1, 1 }, .{ 2, 2, 1, 129 } }, //  2
        .{ .{ 128, 2, 2, 130 }, .{ 0, 0, 2, 2 }, .{ 0, 0, 1, 1 }, .{ 0, 1, 1, 129 } }, //  3
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 129, 1, 2, 2 }, .{ 1, 1, 2, 130 } }, //  4
        .{ .{ 128, 0, 1, 129 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 2, 2 }, .{ 0, 0, 2, 130 } }, //  5
        .{ .{ 128, 0, 2, 130 }, .{ 0, 0, 2, 2 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, //  6
        .{ .{ 128, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 130, 2, 1, 1 }, .{ 2, 2, 1, 129 } }, //  7
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 129, 1, 1, 1 }, .{ 2, 2, 2, 130 } }, //  8
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 129, 1, 1, 1 }, .{ 2, 2, 2, 130 } }, //  9
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 129, 1 }, .{ 2, 2, 2, 2 }, .{ 2, 2, 2, 130 } }, // 10
        .{ .{ 128, 0, 1, 2 }, .{ 0, 0, 129, 2 }, .{ 0, 0, 1, 2 }, .{ 0, 0, 1, 130 } }, // 11
        .{ .{ 128, 1, 1, 2 }, .{ 0, 1, 129, 2 }, .{ 0, 1, 1, 2 }, .{ 0, 1, 1, 130 } }, // 12
        .{ .{ 128, 1, 2, 2 }, .{ 0, 129, 2, 2 }, .{ 0, 1, 2, 2 }, .{ 0, 1, 2, 130 } }, // 13
        .{ .{ 128, 0, 1, 129 }, .{ 0, 1, 1, 2 }, .{ 1, 1, 2, 2 }, .{ 1, 2, 2, 130 } }, // 14
        .{ .{ 128, 0, 1, 129 }, .{ 2, 0, 0, 1 }, .{ 130, 2, 0, 0 }, .{ 2, 2, 2, 0 } }, // 15
        .{ .{ 128, 0, 0, 129 }, .{ 0, 0, 1, 1 }, .{ 0, 1, 1, 2 }, .{ 1, 1, 2, 130 } }, // 16
        .{ .{ 128, 1, 1, 129 }, .{ 0, 0, 1, 1 }, .{ 130, 0, 0, 1 }, .{ 2, 2, 0, 0 } }, // 17
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 2, 2 }, .{ 129, 1, 2, 2 }, .{ 1, 1, 2, 130 } }, // 18
        .{ .{ 128, 0, 2, 130 }, .{ 0, 0, 2, 2 }, .{ 0, 0, 2, 2 }, .{ 1, 1, 1, 129 } }, // 19
        .{ .{ 128, 1, 1, 129 }, .{ 0, 1, 1, 1 }, .{ 0, 2, 2, 2 }, .{ 0, 2, 2, 130 } }, // 20
        .{ .{ 128, 0, 0, 129 }, .{ 0, 0, 0, 1 }, .{ 130, 2, 2, 1 }, .{ 2, 2, 2, 1 } }, // 21
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 129, 1 }, .{ 0, 1, 2, 2 }, .{ 0, 1, 2, 130 } }, // 22
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 0, 0 }, .{ 130, 2, 129, 0 }, .{ 2, 2, 1, 0 } }, // 23
        .{ .{ 128, 1, 2, 130 }, .{ 0, 129, 2, 2 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 0, 0 } }, // 24
        .{ .{ 128, 0, 1, 2 }, .{ 0, 0, 1, 2 }, .{ 129, 1, 2, 2 }, .{ 2, 2, 2, 130 } }, // 25
        .{ .{ 128, 1, 1, 0 }, .{ 1, 2, 130, 1 }, .{ 129, 2, 2, 1 }, .{ 0, 1, 1, 0 } }, // 26
        .{ .{ 128, 0, 0, 0 }, .{ 0, 1, 129, 0 }, .{ 1, 2, 130, 1 }, .{ 1, 2, 2, 1 } }, // 27
        .{ .{ 128, 0, 2, 2 }, .{ 1, 1, 0, 2 }, .{ 129, 1, 0, 2 }, .{ 0, 0, 2, 130 } }, // 28
        .{ .{ 128, 1, 1, 0 }, .{ 0, 129, 1, 0 }, .{ 2, 0, 0, 2 }, .{ 2, 2, 2, 130 } }, // 29
        .{ .{ 128, 0, 1, 1 }, .{ 0, 1, 2, 2 }, .{ 0, 1, 130, 2 }, .{ 0, 0, 1, 129 } }, // 30
        .{ .{ 128, 0, 0, 0 }, .{ 2, 0, 0, 0 }, .{ 130, 2, 1, 1 }, .{ 2, 2, 2, 129 } }, // 31
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 2 }, .{ 129, 1, 2, 2 }, .{ 1, 2, 2, 130 } }, // 32
        .{ .{ 128, 2, 2, 130 }, .{ 0, 0, 2, 2 }, .{ 0, 0, 1, 2 }, .{ 0, 0, 1, 129 } }, // 33
        .{ .{ 128, 0, 1, 129 }, .{ 0, 0, 1, 2 }, .{ 0, 0, 2, 2 }, .{ 0, 2, 2, 130 } }, // 34
        .{ .{ 128, 1, 2, 0 }, .{ 0, 129, 2, 0 }, .{ 0, 1, 130, 0 }, .{ 0, 1, 2, 0 } }, // 35
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 129, 1 }, .{ 2, 2, 130, 2 }, .{ 0, 0, 0, 0 } }, // 36
        .{ .{ 128, 1, 2, 0 }, .{ 1, 2, 0, 1 }, .{ 130, 0, 129, 2 }, .{ 0, 1, 2, 0 } }, // 37
        .{ .{ 128, 1, 2, 0 }, .{ 2, 0, 1, 2 }, .{ 129, 130, 0, 1 }, .{ 0, 1, 2, 0 } }, // 38
        .{ .{ 128, 0, 1, 1 }, .{ 2, 2, 0, 0 }, .{ 1, 1, 130, 2 }, .{ 0, 0, 1, 129 } }, // 39
        .{ .{ 128, 0, 1, 1 }, .{ 1, 1, 130, 2 }, .{ 2, 2, 0, 0 }, .{ 0, 0, 1, 129 } }, // 40
        .{ .{ 128, 1, 0, 129 }, .{ 0, 1, 0, 1 }, .{ 2, 2, 2, 2 }, .{ 2, 2, 2, 130 } }, // 41
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 130, 1, 2, 1 }, .{ 2, 1, 2, 129 } }, // 42
        .{ .{ 128, 0, 2, 2 }, .{ 1, 129, 2, 2 }, .{ 0, 0, 2, 2 }, .{ 1, 1, 2, 130 } }, // 43
        .{ .{ 128, 0, 2, 130 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 2, 2 }, .{ 0, 0, 1, 129 } }, // 44
        .{ .{ 128, 2, 2, 0 }, .{ 1, 2, 130, 1 }, .{ 0, 2, 2, 0 }, .{ 1, 2, 2, 129 } }, // 45
        .{ .{ 128, 1, 0, 1 }, .{ 2, 2, 130, 2 }, .{ 2, 2, 2, 2 }, .{ 0, 1, 0, 129 } }, // 46
        .{ .{ 128, 0, 0, 0 }, .{ 2, 1, 2, 1 }, .{ 130, 1, 2, 1 }, .{ 2, 1, 2, 129 } }, // 47
        .{ .{ 128, 1, 0, 129 }, .{ 0, 1, 0, 1 }, .{ 0, 1, 0, 1 }, .{ 2, 2, 2, 130 } }, // 48
        .{ .{ 128, 2, 2, 130 }, .{ 0, 1, 1, 1 }, .{ 0, 2, 2, 2 }, .{ 0, 1, 1, 129 } }, // 49
        .{ .{ 128, 0, 0, 2 }, .{ 1, 129, 1, 2 }, .{ 0, 0, 0, 2 }, .{ 1, 1, 1, 130 } }, // 50
        .{ .{ 128, 0, 0, 0 }, .{ 2, 129, 1, 2 }, .{ 2, 1, 1, 2 }, .{ 2, 1, 1, 130 } }, // 51
        .{ .{ 128, 2, 2, 2 }, .{ 0, 129, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 0, 2, 2, 130 } }, // 52
        .{ .{ 128, 0, 0, 2 }, .{ 1, 1, 1, 2 }, .{ 129, 1, 1, 2 }, .{ 0, 0, 0, 130 } }, // 53
        .{ .{ 128, 1, 1, 0 }, .{ 0, 129, 1, 0 }, .{ 0, 1, 1, 0 }, .{ 2, 2, 2, 130 } }, // 54
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 2, 1, 129, 2 }, .{ 2, 1, 1, 130 } }, // 55
        .{ .{ 128, 1, 1, 0 }, .{ 0, 129, 1, 0 }, .{ 2, 2, 2, 2 }, .{ 2, 2, 2, 130 } }, // 56
        .{ .{ 128, 0, 2, 2 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 129, 1 }, .{ 0, 0, 2, 130 } }, // 57
        .{ .{ 128, 0, 2, 2 }, .{ 1, 1, 2, 2 }, .{ 129, 1, 2, 2 }, .{ 0, 0, 2, 130 } }, // 58
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 2, 129, 1, 130 } }, // 59
        .{ .{ 128, 0, 0, 130 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 2 }, .{ 0, 0, 0, 129 } }, // 60
        .{ .{ 128, 2, 2, 2 }, .{ 1, 2, 2, 2 }, .{ 0, 2, 2, 2 }, .{ 129, 2, 2, 130 } }, // 61
        .{ .{ 128, 1, 0, 129 }, .{ 2, 2, 2, 2 }, .{ 2, 2, 2, 2 }, .{ 2, 2, 2, 130 } }, // 62
        .{ .{ 128, 1, 1, 129 }, .{ 2, 0, 1, 1 }, .{ 130, 2, 0, 1 }, .{ 2, 2, 2, 0 } }, // 63
    },
};

test "bc7 decompress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const helpers = @import("helpers.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/ziggy.bc7", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const decompress_result = try helpers.decodeBlock(allocator, BC7Block, RGBA8U, dimensions, read_result, .{});
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0x5584F64F;

        try std.testing.expectEqual(expected_hash, hash);
    }
}
