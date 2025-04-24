const std = @import("std");
const Allocator = std.mem.Allocator;

const conversion = @import("../core/conversion.zig");
const RawImageData = @import("../core/raw_image_data.zig").RawImageData;
const Dimensions = @import("../core/Dimensions.zig");

pub fn decodeBlock(
    allocator: Allocator,
    comptime BlockType: type,
    comptime PixelFormat: type,
    dimensions: Dimensions,
    compressed_data: []const u8,
    options: BlockType.DecodeOptions,
) !*RawImageData(PixelFormat) {
    const block_dimensions = calculateBlocksInTexture(BlockType, dimensions);

    const image_data = try RawImageData(PixelFormat).init(allocator, dimensions);

    for (0..block_dimensions.width) |bx| {
        for (0..block_dimensions.height) |by| {
            const block_offset = (by * block_dimensions.width + bx) * @sizeOf(BlockType);
            const block_ptr: *const BlockType = @ptrCast(compressed_data[block_offset..]);
            const texels = try block_ptr.decodeBlock(options);

            for (0..BlockType.texel_height) |y| {
                for (0..BlockType.texel_width) |x| {
                    const global_x = bx * BlockType.texel_width + x;
                    const global_y = by * BlockType.texel_height + y;

                    if (global_x < image_data.dimensions.width and global_y < image_data.dimensions.height) {
                        const block_texel_idx = y * BlockType.texel_width + x;
                        const texel = texels[block_texel_idx];

                        const texel_idx = global_y * image_data.dimensions.width + global_x;
                        image_data.data[texel_idx] = conversion.convertTexel(texel, PixelFormat);
                    }
                }
            }
        }
    }

    return image_data;
}

pub fn encodeBlock(
    allocator: Allocator,
    comptime BlockType: type,
    comptime PixelFormat: type,
    image_data: *RawImageData(PixelFormat),
    options: BlockType.EncodeOptions,
) ![]const u8 {
    const block_dimensions = calculateBlocksInTexture(BlockType, image_data.dimensions);

    const compressed_data = try allocator.alloc(BlockType, block_dimensions.size());

    // We keep track of the last valid texel to handle padding
    // This reduces the impact of padding on the final image
    var last_valid = PixelFormat{};

    for (0..block_dimensions.height) |by| {
        for (0..block_dimensions.width) |bx| {
            const block_index = by * block_dimensions.width + bx;
            const block_ptr = &compressed_data[block_index];

            var texels: [BlockType.texel_count]PixelFormat = undefined;
            for (0..BlockType.texel_height) |y| {
                for (0..BlockType.texel_width) |x| {
                    const global_x = bx * BlockType.texel_width + x;
                    const global_y = by * BlockType.texel_height + y;
                    const texel_idx = y * BlockType.texel_width + x;
                    if (global_x < image_data.dimensions.width and global_y < image_data.dimensions.height) {
                        last_valid = image_data.data[global_y * image_data.dimensions.width + global_x];
                    }
                    texels[texel_idx] = last_valid;
                }
            }

            block_ptr.* = try BlockType.encodeBlock(PixelFormat, texels, options);
        }
    }

    return std.mem.sliceAsBytes(compressed_data);
}

pub fn mixValue(comptime T: type, a: T, b: T, w0: u32, w1: u32) T {
    const calc_type = if (@typeInfo(T) == .int) @Type(.{
        .int = .{
            .signedness = .unsigned,
            .bits = (@typeInfo(T).int.bits * 2) + 1,
        },
    }) else T;

    const a_wide = @as(calc_type, @intCast(a));
    const b_wide = @as(calc_type, @intCast(b));
    const w0_wide = @as(calc_type, @intCast(w0));
    const w1_wide = @as(calc_type, @intCast(w1));
    const total_wide = w0_wide + w1_wide;

    const interpolated = (w0_wide * a_wide + w1_wide * b_wide) / total_wide;
    return @intCast(interpolated);
}

pub fn mixStruct(a: anytype, b: @TypeOf(a), w0: u32, w1: u32) @TypeOf(a) {
    const T = @TypeOf(a);

    var result: T = undefined;

    inline for (std.meta.fields(T)) |field| {
        const field_name = field.name;
        const FieldType = field.type;

        const a_value = @field(a, field_name);
        const b_value = @field(b, field_name);

        @field(result, field_name) = mixValue(FieldType, a_value, b_value, w0, w1);
    }

    return result;
}

/// Calculates the number of blocks in a texture based on the block type and texture dimensions.
///
/// `BlockType` is the type of block to use.
/// `dimensions` is the dimensions of the texture.
///
/// Returns a `Dimensions` struct containing the number of blocks in width and height.
/// The width and height are rounded up to the nearest multiple of the block size.
pub fn calculateBlocksInTexture(comptime BlockType: type, dimensions: Dimensions) Dimensions {
    const pw = padTo(dimensions.width, BlockType.texel_width);
    const ph = padTo(dimensions.height, BlockType.texel_height);
    const bw = std.math.divCeil(u32, pw, BlockType.texel_width) catch unreachable;
    const bh = std.math.divCeil(u32, ph, BlockType.texel_height) catch unreachable;

    return .{
        .width = bw,
        .height = bh,
    };
}

/// Pads the given value to the nearest multiple of the padding value.
///
/// For example, if the value is 5 and the padding is 4, it will return 8.
///
/// `value` is the value to pad.
/// `padding` is the value to pad to.
///
/// Returns the padded value.
pub fn padTo(value: anytype, padding: @TypeOf(value)) @TypeOf(value) {
    const type_info = @typeInfo(@TypeOf(value));
    comptime if (type_info != .int and type_info != .comptime_int) {
        @compileError("padTo only works with integer types");
    };

    const remainder = value % padding;
    if (remainder == 0) {
        return value;
    } else {
        return value + (padding - remainder);
    }
}

test padTo {
    {
        const value = 5;
        const padding = 4;
        const result = padTo(value, padding);
        try std.testing.expectEqual(8, result);
    }

    {
        const value = 5;
        const padding = 5;
        const result = padTo(value, padding);
        try std.testing.expectEqual(5, result);
    }
}
