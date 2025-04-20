# Texzel

Texzel is a Zig library for texture encoding/decoding. It aims to be pure Zig and depdendency free.

## Supported Formats
| Format | Decompress | Compress |
|---|---|---|
| Raw | ✅ | ✅ |
| BC1 (DXT1) | ✅ | ✅ |
| BC1a (DXT1) | ✅ | ✅ |
| BC2 (DXT3) | ✅ | ✅ |
| BC3 (DXT5) | ✅ | ✅ |
| BC4 | ✅ | ✅ |
| BC5 | ✅ | ✅ |
| BC6 | ❌ | ❌ |
| BC7 | ❌ | ❌ |

## Current State
Texzel is still very early in development and only supports a couple of formats currently.
The API is not stable, contributions are welcome.

Texzel does not currently support file formats beyond some testing, as such you must provide raw buffers to compress/decompress.
