//! A texture encoding/decoding library for Zig.
//!
//! This library provides a set of functions to encode and decode textures in various formats.
//!
//! For BCn formats, see `block`.
//! For raw texel formats, see `texel`.

pub const texel = @import("texel.zig");
pub const utils = @import("utils.zig");
pub const block = @import("block.zig");

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
