const std = @import("std");
const Allocator = std.mem.Allocator;

const RGBATexel = @import("texel_types.zig").RGBAU;

pub fn RawImageData(comptime TexelType: type) type {
    return struct {
        allocator: Allocator,
        width: u32,
        height: u32,
        data: []u8,

        pub fn init(allocator: Allocator, width: u32, height: u32) !*RawImageData(TexelType) {
            const image_data = try allocator.create(RawImageData(TexelType));
            errdefer allocator.destroy(image_data);

            image_data.* = .{
                .allocator = allocator,
                .width = width,
                .height = height,
                .data = try allocator.alloc(u8, @sizeOf(TexelType) * width * height),
            };

            return image_data;
        }

        pub fn deinit(self: *RawImageData(TexelType)) void {
            self.allocator.free(self.data);
            self.allocator.destroy(self);
        }
    };
}
