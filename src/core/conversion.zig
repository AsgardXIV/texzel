const std = @import("std");

const texels = @import("texel_types.zig");

/// A version of `convertTexel` that converts an array of texels.
///
/// `ResultTexel` is the type of the resulting texels.
/// `input` is the array of texels to be converted.
///
/// The function returns an array of converted texels of the same length as `input`.
pub fn convertTexels(
    comptime ResultTexel: type,
    input: anytype,
) [input.len]ResultTexel {
    return convertTexelsWithSwizzle(ResultTexel, input, struct {});
}

/// A version of `convertTexelWithSwizzle` that converts an array of texels.
///
/// `ResultTexel` is the type of the resulting texels.
/// `input` is the array of texels to be converted.
///
/// The function returns an array of converted texels of the same length as `input`.
pub fn convertTexelsWithSwizzle(
    comptime ResultTexel: type,
    input: anytype,
    comptime SwizzleType: type,
) [input.len]ResultTexel {
    var result: [input.len]ResultTexel = undefined;
    for (input, 0..) |texel, i| {
        result[i] = convertTexelWithSwizzle(texel, ResultTexel, SwizzleType);
    }
    return result;
}

/// Converts a texel from one format to another, applying the chosen swizzle and preserving relative magnitudes appropriately.
///
/// `source_texel` is the texel to be converted.
/// `TargetType` is the target texel type.
///
/// Both `source_texel` and `TargetType` must be structs which contain only integers and floats.
///
/// `SwizzleType` is a struct that defines the swizzle pattern.
/// It should contain fields with the same names as the target type, and the values should []const u8 with the source field names.
///
/// When the source and target types are the same, the function returns the source texel unchanged.
/// If a field is present in the target type but not in the source type, it is initialized to the default value or 0.
/// If a field is present in the source type but not in the target type, it is ignored.
/// Integer to integer conversion uses `scaleBitWidth` to scale the value.
/// Float to float conversion uses `@floatCast` to convert the value.
/// Integer to float conversion scales the integer value to the range of 0..1 in the float.
/// Float to integer conversion clamps and scales the float value to the range of 0..1 and scales it to the integer range.
pub fn convertTexel(
    source_texel: anytype,
    comptime TargetType: type,
) TargetType {
    return convertTexelWithSwizzle(source_texel, TargetType, struct {});
}

/// Converts a texel from one format to another, preserving relative magnitudes appropriately.
///
/// `source_texel` is the texel to be converted.
/// `TargetType` is the target texel type.
///
/// Both `source_texel` and `TargetType` must be structs which contain only integers and floats.
///
/// When the source and target types are the same, the function returns the source texel unchanged.
/// If a field is present in the target type but not in the source type or swizzle, it is initialized to the default value or 0.
/// If a field is present in the source type but not in the target type or swizzle, it is ignored.
/// Integer to integer conversion uses `scaleBitWidth` to scale the value.
/// Float to float conversion uses `@floatCast` to convert the value.
/// Integer to float conversion scales the integer value to the range of 0..1 in the float.
/// Float to integer conversion clamps and scales the float value to the range of 0..1 and scales it to the integer range.
pub fn convertTexelWithSwizzle(
    source_texel: anytype,
    comptime TargetType: type,
    comptime SwizzleType: type,
) TargetType {
    const SourceType = @TypeOf(source_texel);

    const swizzle = comptime SwizzleType{};

    comptime {
        if (@typeInfo(SourceType) != .@"struct" or @typeInfo(TargetType) != .@"struct") {
            @compileError("Both source and target types must be structs");
        }
    }

    var return_texel: TargetType = undefined;

    inline for (@typeInfo(TargetType).@"struct".fields) |target_field| {
        const target_name = target_field.name;

        const source_name =
            if (@hasField(SwizzleType, target_name))
                @field(swizzle, target_name)
            else
                target_name;

        if (!@hasField(SourceType, source_name)) {
            @field(return_texel, target_name) = target_field.defaultValue() orelse 0;
        }

        if (@hasField(SourceType, source_name)) {
            const source_field_value = @field(source_texel, source_name);
            const SourceFieldType = @TypeOf(source_field_value);
            const TargetFieldType = target_field.type;

            const field_value = switch (@typeInfo(TargetFieldType)) {
                .int => switch (@typeInfo(SourceFieldType)) {
                    .int => scaleBitWidth(source_field_value, TargetFieldType),
                    .float => blk: {
                        const target_max = std.math.maxInt(TargetFieldType);
                        const clamped = @min(1.0, @max(0.0, source_field_value));
                        const scaled_float = (clamped * @as(f64, @floatFromInt(target_max))) + 0.5;
                        break :blk @as(TargetFieldType, @intFromFloat(scaled_float));
                    },
                    else => @compileError("Unsupported source type for integer conversion"),
                },
                .float => switch (@typeInfo(SourceFieldType)) {
                    .float => @as(TargetFieldType, @floatCast(source_field_value)),
                    .int => blk: {
                        const source_max = std.math.maxInt(SourceFieldType);
                        const float_value = @as(f64, @floatFromInt(source_field_value)) / @as(f64, @floatFromInt(source_max));
                        break :blk @as(TargetFieldType, @floatCast(float_value));
                    },
                    else => @compileError("Unsupported source type for float conversion"),
                },
                else => @compileError("Unsupported field type for conversion"),
            };

            @field(return_texel, target_field.name) = field_value;
        }
    }

    return return_texel;
}

/// Scales an integer from one bit width to another, preserving relative magnitude.
///
/// `source_value` is the value to be scaled.
/// `TargetType` is the target integer type.
///
/// This function is useful for converting color values between different bit depths.
pub fn scaleBitWidth(source_value: anytype, comptime TargetType: type) TargetType {
    const SourceType = @TypeOf(source_value);

    comptime {
        if (@typeInfo(SourceType) != .int or @typeInfo(TargetType) != .int) {
            @compileError("Both source and target types must be integers");
        }
    }

    const source_max = std.math.maxInt(SourceType);
    const target_max = std.math.maxInt(TargetType);

    if (SourceType == TargetType) {
        return source_value;
    } else if (source_value == 0) {
        return 0;
    } else if (source_value == source_max) {
        return target_max;
    }

    const required_bits = @bitSizeOf(SourceType) + @bitSizeOf(TargetType) + 1;

    const WideType = @Type(.{
        .int = .{
            .signedness = .unsigned,
            .bits = required_bits,
        },
    });

    const scaled_value = (@as(WideType, source_value) * @as(WideType, target_max + 1)) / @as(WideType, source_max + 1);

    return @intCast(scaled_value);
}

test convertTexel {
    {
        const input = texels.RGBA8U{
            .r = 255,
            .g = 128,
            .b = 64,
            .a = 0,
        };

        const output = convertTexel(input, texels.RGBA16U);

        const expected = texels.RGBA16U{
            .r = 65535,
            .g = 32768,
            .b = 16384,
            .a = 0,
        };

        try std.testing.expectEqual(expected, output);
    }

    {
        const input = texels.RGBA8U{
            .r = 255,
            .g = 128,
            .b = 64,
            .a = 0,
        };

        const output = convertTexel(input, texels.RGBA16F);

        const expected = texels.RGBA16F{
            .r = 1.0,
            .g = 0.5,
            .b = 0.25,
            .a = 0.0,
        };

        try std.testing.expectApproxEqRel(expected.r, output.r, 0.01);
        try std.testing.expectApproxEqRel(expected.g, output.g, 0.01);
        try std.testing.expectApproxEqRel(expected.b, output.b, 0.01);
        try std.testing.expectApproxEqRel(expected.a, output.a, 0.01);
    }

    {
        const input = texels.RGBA16F{
            .r = 1.0,
            .g = 0.5,
            .b = 0.25,
            .a = 0.0,
        };

        const output = convertTexel(input, texels.RGBA8U);

        const expected = texels.RGBA8U{
            .r = 255,
            .g = 128,
            .b = 64,
            .a = 0,
        };

        try std.testing.expectEqual(expected, output);
    }

    {
        const input = texels.RGBA8U{
            .r = 255,
            .g = 128,
            .b = 64,
            .a = 255,
        };

        const MiniTexel = struct {
            r: u5,
            g: u6,
            b: u5,
            a: u1,
        };

        const mini = convertTexel(input, MiniTexel);

        const expected = MiniTexel{
            .r = 31,
            .g = 32,
            .b = 8,
            .a = 1,
        };

        try std.testing.expectEqual(expected, mini);
    }
}

test convertTexelWithSwizzle {
    const input = texels.RGBA8U{
        .r = 255,
        .g = 128,
        .b = 64,
        .a = 0,
    };

    const output = convertTexelWithSwizzle(
        input,
        texels.RGBA8U,
        struct {
            r: []const u8 = "b",
        },
    );

    const expected = texels.RGBA8U{
        .r = 64,
        .g = 128,
        .b = 64,
        .a = 0,
    };

    try std.testing.expectEqual(expected, output);
}

test scaleBitWidth {
    {
        const input: u8 = 255;
        const output = scaleBitWidth(input, u16);
        try std.testing.expectEqual(65535, output);
    }

    {
        const input: u8 = 128;
        const output = scaleBitWidth(input, u16);
        try std.testing.expectEqual(32768, output);
    }
}
