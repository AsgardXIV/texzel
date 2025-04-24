const block = @import("block.zig");

/// The available texture codecs.
pub const Codecs = enum {
    bc1,
    bc2,
    bc3,
    bc4,
    bc5,
    bc6,
    bc7,

    pub fn blockType(comptime codec: Codecs) type {
        return switch (codec) {
            .bc1 => block.bc1.BC1Block,
            .bc2 => block.bc2.BC2Block,
            .bc3 => block.bc3.BC3Block,
            .bc4 => block.bc4.BC4Block,
            .bc5 => block.bc5.BC5Block,
            .bc6 => block.bc6.BC6Block,
            .bc7 => block.bc7.BC7Block,
        };
    }
};
