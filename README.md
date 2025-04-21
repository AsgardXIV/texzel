# Texzel

Texzel is a Zig library for texture encoding/decoding. It aims to be pure Zig and depdendency free.

## Supported Formats
| Format | Decode | Encode | Notes |
|---|---|---|---|
| Raw | ✅ | ✅ |  |
| BC1 (DXT1) | ✅ | ✅ | BC1a is supported, any texel with alpha < 255 will be treated as fully transparent |
| BC2 (DXT3) | ✅ | ✅ | |
| BC3 (DXT5) | ✅ | ✅ | |
| BC4 | ✅ | ✅ | |
| BC5 | ✅ | ✅ | | 
| BC6h | ✅ | ❌ | Decoding only at this time. Encoding is planned. | 
| BC7 | ✅ | ❌ | Decoding only at this time. Encoding is planned. |

## Current State
Texzel is still very early in development and the API is not stable, contributions are welcome.

Texzel does not currently support file formats beyond some testing, as such you must provide raw buffers to compress/decompress.

## Adding to your project
1. Add texzel to your build.zig.zon
```
zig fetch --save git+https://github.com/AsgardXIV/texzel
```

2. Add the dependency to your project, for example:
```zig
const texzel_dependency = b.dependency("texzel", .{
  .target = target,
  .optimize = optimize,
});

exe_mod.addImport("texzel", texzel_dependency.module("texzel"));
```

## Usage Example
```zig
const allocator = ...;

// Import Texzel
const texzel = @import("texzel");

// Load a raw rgba image
const file = try std.fs.cwd().openFile("resources/ziggy.rgba", .{ .mode = .read_only });
defer file.close();
const raw_buffer = try file.readToEndAlloc(std.testing.allocator, 2 << 20);
defer allocator.free(raw_buffer);

// Image dimensions
const dimensions = texzel.core.Dimensions{
    .width = 512,
    .height = 512,
};

// Create a raw image data instance from the buffer
const raw_image = try texzel.rawImageFromBuffer(
    allocator,
    texzel.pixel_formats.RGBA8U,
    dimensions,
    raw_buffer,
); 
defer raw_image.deinit();

// Compress to BC1
const compressed_buffer = try texzel.encode(
    allocator,
    texzel.block.bc1.BC1Block,
    texzel.pixel_formats.RGBA8U,
    .{},
    raw_image,
); 
defer allocator.free(compressed_buffer);

// Decompress to RawImage but in BGRA8U this time
const new_raw_image = try texzel.decode(
    allocator,
    texzel.block.bc1.BC1Block,
    texzel.pixel_formats.BGRA8U,
    dimensions,
    .{},
    compressed_buffer,
);
defer new_raw_image.deinit();

// Access the new raw buffer
const new_raw_buffer = new_raw_image.asBuffer();
_ = new_raw_buffer; // Do something
```

## License
Texzel is licensed under the [MIT License](LICENSE).

Licenses for third-party software and assets can be found [here](THIRD_PARTY_LICENSES.md).
