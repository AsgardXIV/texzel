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
| BC6 | ❌ | ❌ | | 
| BC7 | ✅ | ❌ | Decoding only at this time |

## Current State
Texzel is still very early in development and the API is not stable, contributions are welcome.

Texzel does not currently support file formats beyond some testing, as such you must provide raw buffers to compress/decompress.

## Acknowledgements
* BC7 support is mostly ported from https://github.com/hasenbanck/block_compression/
