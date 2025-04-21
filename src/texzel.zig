//! A texture encoding/decoding library for Zig.
//!
//! This library provides a set of functions to encode and decode textures in various formats.

pub const core = @import("core.zig");
pub const block = @import("block.zig");
pub const pixel_formats = @import("pixel_formats.zig");

const std = @import("std");

/// Initializes a RawImageData instance from a buffer.
///
/// `allocator` is the allocator to use for the image data.
/// `PixelFormat` is the pixel format to use.
/// `dimensions` is the dimensions of the image.
/// `buffer` is the buffer to copy the image data from.
///
/// The height and width must be correct for the image in the buffer.
///
/// Returns a pointer to the new RawImageData instance.
/// Caller is responsible for freeing the memory.
pub fn rawImageFromBuffer(
    allocator: std.mem.Allocator,
    comptime PixelFormat: type,
    dimensions: core.Dimensions,
    buffer: []const u8,
) !*core.RawImageData(PixelFormat) {
    return core.RawImageData(PixelFormat).initFromBuffer(allocator, dimensions, buffer);
}

/// Initalizes a blank RawImageData instance.
///
/// `allocator` is the allocator to use for the image data.
/// `PixelFormat` is the pixel format to use.
/// `dimensions` is the dimensions of the image.
///
/// The image data is not initialized, so the contents are undefined.
///
/// Returns a pointer to the new RawImageData instance.
/// Caller is responsible for freeing the memory.
pub fn newRawImage(
    allocator: std.mem.Allocator,
    comptime PixelFormat: type,
    dimensions: core.Dimensions,
) !*core.RawImageData(PixelFormat) {
    return core.RawImageData(PixelFormat).init(allocator, dimensions);
}

/// Encodes a raw image data into a compressed texture format.
///
/// `allocator` is the allocator to use for memory allocation.
/// `BlockType` is the type of block you want to compress to.
/// `PixelFormat` is the type of pixel you are compressing.
/// `options` are the options for encoding.
/// `image_data` is the raw image data to compress.
///
/// Returns a pointer to the compressed image data.
/// Caller is responsible for freeing the memory.
pub fn encode(
    allocator: std.mem.Allocator,
    comptime BlockType: type,
    comptime PixelFormat: type,
    options: BlockType.EncodeOptions,
    image_data: *core.RawImageData(PixelFormat),
) ![]const u8 {
    return try block.helpers.encodeBlock(allocator, BlockType, PixelFormat, image_data, options);
}

/// Decodes a compressed texture into a raw image data format.
///
/// `allocator` is the allocator to use for memory allocation.
/// `BlockType` is the type of block you are decompressing.
/// `PixelFormat` is the pixel format you are decompressing to.
/// `dimensions` are the dimensions of the image.
/// `options` are the options for decoding.
/// `compressed_data` is the compressed image data to decompress.
///
/// Returns a pointer to the decompressed image data as a `core.RawImageData`.
/// Caller is responsible for deiniting the memory.
pub fn decode(
    allocator: std.mem.Allocator,
    comptime BlockType: type,
    comptime PixelFormat: type,
    dimensions: core.Dimensions,
    options: BlockType.DecodeOptions,
    compressed_data: []const u8,
) !*core.RawImageData(PixelFormat) {
    return try block.helpers.decodeBlock(allocator, BlockType, PixelFormat, dimensions, compressed_data, options);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
