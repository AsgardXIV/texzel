const std = @import("std");
const Allocator = std.mem.Allocator;

const Dimensions = @import("core/Dimensions.zig");
const RawImageData = @import("core/raw_image_data.zig").RawImageData;

pub const bc1 = @import("block/bc1.zig");
pub const bc2 = @import("block/bc2.zig");
pub const bc3 = @import("block/bc3.zig");
pub const bc4 = @import("block/bc4.zig");
pub const bc5 = @import("block/bc5.zig");
pub const bc6h = @import("block/bc6h.zig");
pub const bc7 = @import("block/bc7.zig");

pub const helpers = @import("block/helpers.zig");

/// Decodes a compressed texture into a raw image data format.
///
/// `allocator` is the allocator to use for memory allocation.
/// `BlockType` is the type of block you are decompressing.
/// `TexelType` is the type of texel you are decompressing to.
/// `dimensions` is the dimensions of the image.
/// `options` are the options for decoding.
/// `compressed_data` is the compressed image data to decompress.
///
/// Returns a pointer to the decompressed image data as a `RawImageData`.
/// Caller is responsible for deiniting the memory.
pub fn decode(allocator: Allocator, comptime BlockType: type, comptime TexelType: type, dimensions: Dimensions, options: BlockType.DecodeOptions, compressed_data: []const u8) !*RawImageData(TexelType) {
    return try helpers.decodeBlock(allocator, BlockType, TexelType, dimensions, compressed_data, options);
}

/// Encodes a raw image data into a compressed texture format.
///
/// `allocator` is the allocator to use for memory allocation.
/// `BlockType` is the type of block you want to compress to.
/// `TexelType` is the type of texel you are compressing.
/// `options` are the options for encoding.
/// `image_data` is the raw image data to compress.
///
/// Returns a pointer to the compressed image data.
/// Caller is responsible for freeing the memory.
pub fn encode(allocator: Allocator, comptime BlockType: type, comptime TexelType: type, options: BlockType.EncodeOptions, image_data: *RawImageData(TexelType)) ![]const u8 {
    return try helpers.encodeBlock(allocator, BlockType, TexelType, image_data, options);
}
