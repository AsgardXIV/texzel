const std = @import("std");
const Allocator = std.mem.Allocator;

const conversion = @import("conversion.zig");

const Dimensions = @import("../core/Dimensions.zig");

/// A raw image data structure with the given PixelFormat.
///
/// `PixelFormat` is the type of texel to use.
pub fn RawImageData(comptime InPixelFormat: type) type {
    return struct {
        pub const PixelFormat = InPixelFormat;
        const Self = @This();

        allocator: Allocator,
        dimensions: Dimensions,
        data: []PixelFormat,

        /// Initializes a blank RawImageData instance with the given allocator, width, and height.
        ///
        /// `allocator` is the allocator to use for the image data.
        /// `dimensions` is the dimensions of the image.
        ///
        /// The image data is not initialized, so the contents are undefined.
        ///
        /// Returns a pointer to the new RawImageData instance.
        /// Caller is responsible for freeing the memory.
        pub fn init(allocator: Allocator, dimensions: Dimensions) !*Self {
            const image_data = try allocator.create(Self);
            errdefer allocator.destroy(image_data);

            image_data.* = .{
                .allocator = allocator,
                .dimensions = dimensions,
                .data = try allocator.alloc(PixelFormat, dimensions.size()),
            };

            return image_data;
        }

        /// Initializes a RawImageData instance from a buffer.
        ///
        /// `allocator` is the allocator to use for the image data.
        /// `dimensions` is the dimensions of the image.
        /// `buffer` is the buffer to copy the image data from.
        ///
        /// The height and width must be correct for the image in the buffer.
        pub fn initFromBuffer(allocator: Allocator, dimensions: Dimensions, buffer: []const u8) !*Self {
            const pixel_count = dimensions.size();
            const bytes_needed = pixel_count * @sizeOf(PixelFormat);

            if (buffer.len < bytes_needed) {
                @branchHint(.unlikely);
                return error.SourceTooSmall;
            }

            const image_data = try allocator.create(Self);
            errdefer allocator.destroy(image_data);

            const pixels = try allocator.alloc(PixelFormat, pixel_count);
            errdefer allocator.free(pixels);

            const slice = std.mem.sliceAsBytes(pixels);

            if (slice.len < bytes_needed) {
                @branchHint(.unlikely);
                return error.TargetTooSmall;
            }

            @memcpy(slice, buffer[0..bytes_needed]);

            image_data.* = .{
                .allocator = allocator,
                .dimensions = dimensions,
                .data = pixels,
            };

            return image_data;
        }

        pub fn deinit(image_data: *Self) void {
            image_data.allocator.free(image_data.data);
            image_data.allocator.destroy(image_data);
        }

        /// Returns the raw image data as a slice of bytes.
        /// To index texel data, use `image_data.data[i]`.
        pub fn asBuffer(image_data: *Self) []const u8 {
            return std.mem.sliceAsBytes(image_data.data);
        }

        // Convert the image data to a different texel type.
        //
        // `allocator` is the allocator to use for the new image data.
        // `NewPixelFormat` is the type of texel to convert to.
        //
        // Returns a pointer to the new image data.
        // Caller is responsible for freeing the memory.
        pub fn convertTo(image_data: *Self, allocator: Allocator, comptime NewPixelFormat: type) !*RawImageData(NewPixelFormat) {
            return image_data.convertToWithSwizzle(allocator, NewPixelFormat, struct {});
        }

        // Convert the image data to a different texel type with swizzle.
        //
        // Uses `conversion.convertTexels` to convert texels.
        //
        // `allocator` is the allocator to use for the new image data.
        // `NewPixelFormat` is the type of texel to convert to.
        // `SwizzleType` is the type of swizzle to use.
        //
        // Returns a pointer to the new image data.
        // Caller is responsible for freeing the memory.
        pub fn convertToWithSwizzle(image_data: *Self, allocator: Allocator, comptime NewPixelFormat: type, comptime SwizzleType: type) !*RawImageData(NewPixelFormat) {
            if (PixelFormat == NewPixelFormat) {
                return Self.initFromBuffer(allocator, image_data.dimensions, image_data.asBuffer());
            }

            const new_image_data = try RawImageData(NewPixelFormat).init(allocator, image_data.dimensions);
            errdefer allocator.destroy(new_image_data);

            try conversion.convertTexelsDynamicWithSwizzle(NewPixelFormat, image_data.data, new_image_data.data, SwizzleType);

            return new_image_data;
        }
    };
}

test RawImageData {
    const RGBA8U = @import("../pixel_formats.zig").RGBA8U;
    const BGRA8U = @import("../pixel_formats.zig").BGRA8U;

    const allocator = std.testing.allocator;

    // RGBA8U to BGRA8U conversion test
    {
        const file = try std.fs.cwd().openFile("resources/ziggy.rgba", .{ .mode = .read_only });
        defer file.close();

        const data = try file.readToEndAlloc(allocator, 2 << 20);
        defer allocator.free(data);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const image_data = try RawImageData(RGBA8U).initFromBuffer(allocator, dimensions, data);
        defer image_data.deinit();

        const converted = try image_data.convertTo(allocator, BGRA8U);
        defer converted.deinit();

        const expected_file = try std.fs.cwd().openFile("resources/ziggy.bgra", .{ .mode = .read_only });
        defer expected_file.close();

        const expected_data = try expected_file.readToEndAlloc(allocator, 2 << 20);
        defer allocator.free(expected_data);

        try std.testing.expectEqualSlices(u8, expected_data, converted.asBuffer());
    }

    // RGBA8U to RGBA8U (no-op)
    {
        const file = try std.fs.cwd().openFile("resources/ziggy.rgba", .{ .mode = .read_only });
        defer file.close();

        const data = try file.readToEndAlloc(allocator, 2 << 20);
        defer allocator.free(data);

        const dimensions = Dimensions{
            .width = 512,
            .height = 512,
        };

        const image_data = try RawImageData(RGBA8U).initFromBuffer(allocator, dimensions, data);
        defer image_data.deinit();

        const converted = try image_data.convertTo(allocator, RGBA8U);
        defer converted.deinit();

        try std.testing.expectEqualSlices(u8, data, converted.asBuffer());
    }
}
