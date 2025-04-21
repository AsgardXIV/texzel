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

## License
Texzel is licensed under the [MIT License](LICENSE).

Licenses for third-party software and assets can be found [here](THIRD_PARTY_LICENSES.md).
