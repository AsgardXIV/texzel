const std = @import("std");
const Allocator = std.mem.Allocator;

const conversion = @import("../core/conversion.zig");

const bc1 = @import("bc1.zig");

pub const BC3Block = extern struct {
    pub const texel_width = 4;
    pub const texel_height = 4;
    pub const texel_count = texel_width * texel_height;

    pub const Options = struct {};

    alpha: u64 align(1),
    bc1_block: bc1.BC1Block align(1),

    pub fn decompressTexels(self: *const BC3Block, comptime ResultTexels: type) [texel_count]ResultTexels {
        var texels = self.bc1_block.decompressTexels(ResultTexels);

        return texels;
    }
};
