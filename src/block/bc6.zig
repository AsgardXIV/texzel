// Portions of this file are based on bcdec and block_compression.
// See THIRD_PARTY_LICENSES.md in this project for more information.

const std = @import("std");

const conversion = @import("../core/conversion.zig");

const RGBA16F = @import("../pixel_formats.zig").RGBA16F;

const BC6Enc = @import("BC6Enc.zig");

pub const BC6Block = extern struct {
    pub const TexelFormat = RGBA16F;

    pub const texel_width = 4;
    pub const texel_height = 4;
    pub const texel_count = texel_width * texel_height;

    pub const DecodeOptions = struct {
        is_signed: bool = false,
    };

    pub const EncodeOptions = BC6Enc.Settings;

    data: [16]u8,

    pub fn decodeBlock(self: *const BC6Block, options: DecodeOptions) ![texel_count]TexelFormat {
        var texels: [texel_count]TexelFormat = @splat(TexelFormat{});

        var buffer = std.io.fixedBufferStream(&self.data);
        var reader = std.io.bitReader(.little, buffer.reader().any());

        var mode: u8 = try reader.readBitsNoEof(u8, 2);
        if (mode > 1) {
            mode |= try reader.readBitsNoEof(u8, 3) << 2;
        }

        var partition: i32 = 0;

        var r: [4]i32 = @splat(0);
        var g: [4]i32 = @splat(0);
        var b: [4]i32 = @splat(0);

        switch (mode) {
            // Mode 1
            0b00 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 75 bits (10.555, 10.555, 10.555)
                g[2] |= try reader.readBitsNoEof(i32, 1) << 4; // gy[4]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 4; // by[4]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 4; // bz[4]
                r[0] |= try reader.readBitsNoEof(i32, 10); // rw[9:0]
                g[0] |= try reader.readBitsNoEof(i32, 10); // gw[9:0]
                b[0] |= try reader.readBitsNoEof(i32, 10); // bw[9:0]
                r[1] |= try reader.readBitsNoEof(i32, 5); // rx[4:0]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 4; // gz[4]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 5); // gx[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gz[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 5); // bx[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 5); // ry[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                r[3] |= try reader.readBitsNoEof(i32, 5); // rz[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 0;
            },
            // Mode 2
            0b01 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 75 bits (7666, 7666, 7666)
                g[2] |= try reader.readBitsNoEof(i32, 1) << 5; // gy[5]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 4; // gz[4]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 5; // gz[5]
                r[0] |= try reader.readBitsNoEof(i32, 7); // rw[6:0]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 4; // by[4]
                g[0] |= try reader.readBitsNoEof(i32, 7); // gw[6:0]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 5; // by[5]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 4; // gy[4]
                b[0] |= try reader.readBitsNoEof(i32, 7); // bw[6:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 5; // bz[5]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 4; // bz[4]
                r[1] |= try reader.readBitsNoEof(i32, 6); // rx[5:0]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 6); // gx[5:0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gz[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 6); // bx[5:0]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 6); // ry[5:0]
                r[3] |= try reader.readBitsNoEof(i32, 6); // rz[5:0]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 1;
            },
            // Mode 3
            0b00010 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 72 bits (11.555, 11.444, 11.444)
                r[0] |= try reader.readBitsNoEof(i32, 10); // rw[9:0]
                g[0] |= try reader.readBitsNoEof(i32, 10); // gw[9:0]
                b[0] |= try reader.readBitsNoEof(i32, 10); // bw[9:0]
                r[1] |= try reader.readBitsNoEof(i32, 5); // rx[4:0]
                r[0] |= try reader.readBitsNoEof(i32, 1) << 10; // rw[10]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 4); // gx[3:0]
                g[0] |= try reader.readBitsNoEof(i32, 1) << 10; // gw[10]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gz[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 4); // bx[3:0]
                b[0] |= try reader.readBitsNoEof(i32, 1) << 10; // bw[10]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 5); // ry[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                r[3] |= try reader.readBitsNoEof(i32, 5); // rz[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 2;
            },
            // Mode 4
            0b00110 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 72 bits (11.444, 11.555, 11.444)
                r[0] |= try reader.readBitsNoEof(i32, 10); // rw[9:0]
                g[0] |= try reader.readBitsNoEof(i32, 10); // gw[9:0]
                b[0] |= try reader.readBitsNoEof(i32, 10); // bw[9:0]
                r[1] |= try reader.readBitsNoEof(i32, 4); // rx[3:0]
                r[0] |= try reader.readBitsNoEof(i32, 1) << 10; // rw[10]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 4; // gz[4]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 5); // gx[4:0]
                g[0] |= try reader.readBitsNoEof(i32, 1) << 10; // gw[10]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gz[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 4); // bx[3:0]
                b[0] |= try reader.readBitsNoEof(i32, 1) << 10; // bw[10]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 4); // ry[3:0]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                r[3] |= try reader.readBitsNoEof(i32, 4); // rz[3:0]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 4; // gy[4]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 3;
            },
            // Mode 5
            0b01010 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 72 bits (11.444, 11.444, 11.555)
                r[0] |= try reader.readBitsNoEof(i32, 10); // rw[9:0]
                g[0] |= try reader.readBitsNoEof(i32, 10); // gw[9:0]
                b[0] |= try reader.readBitsNoEof(i32, 10); // bw[9:0]
                r[1] |= try reader.readBitsNoEof(i32, 4); // rx[3:0]
                r[0] |= try reader.readBitsNoEof(i32, 1) << 10; // rw[10]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 4; // by[4]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 4); // gx[3:0]
                g[0] |= try reader.readBitsNoEof(i32, 1) << 10; // gw[10]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gz[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 5); // bx[4:0]
                b[0] |= try reader.readBitsNoEof(i32, 1) << 10; // bw[10]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 4); // ry[3:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                r[3] |= try reader.readBitsNoEof(i32, 4); // rz[3:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 4; // bz[4]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 4;
            },
            // Mode 6
            0b01110 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 72 bits (9555, 9555, 9555)
                r[0] |= try reader.readBitsNoEof(i32, 9); // rw[8:0]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 4; // by[4]
                g[0] |= try reader.readBitsNoEof(i32, 9); // gw[8:0]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 4; // gy[4]
                b[0] |= try reader.readBitsNoEof(i32, 9); // bw[8:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 4; // bz[4]
                r[1] |= try reader.readBitsNoEof(i32, 5); // rx[4:0]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 4; // gz[4]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 5); // gx[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gx[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 5); // bx[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 5); // ry[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                r[3] |= try reader.readBitsNoEof(i32, 5); // rz[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 5;
            },
            // Mode 7
            0b10010 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 72 bits (8666, 8555, 8555)
                r[0] |= try reader.readBitsNoEof(i32, 8); // rw[7:0]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 4; // gz[4]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 4; // by[4]
                g[0] |= try reader.readBitsNoEof(i32, 8); // gw[7:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 4; // gy[4]
                b[0] |= try reader.readBitsNoEof(i32, 8); // bw[7:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 4; // bz[4]
                r[1] |= try reader.readBitsNoEof(i32, 6); // rx[5:0]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 5); // gx[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gz[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 5); // bx[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 6); // ry[5:0]
                r[3] |= try reader.readBitsNoEof(i32, 6); // rz[5:0]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 6;
            },
            // Mode 8
            0b10110 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 72 bits (8555, 8666, 8555)
                r[0] |= try reader.readBitsNoEof(i32, 8); // rw[7:0]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 4; // by[4]
                g[0] |= try reader.readBitsNoEof(i32, 8); // gw[7:0]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 5; // gy[5]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 4; // gy[4]
                b[0] |= try reader.readBitsNoEof(i32, 8); // bw[7:0]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 5; // gz[5]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 4; // bz[4]
                r[1] |= try reader.readBitsNoEof(i32, 5); // rx[4:0]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 4; // gz[4]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 6); // gx[5:0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // zx[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 5); // bx[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 5); // ry[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                r[3] |= try reader.readBitsNoEof(i32, 5); // rz[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 7;
            },
            // Mode 9
            0b11010 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 72 bits (8555, 8555, 8666)
                r[0] |= try reader.readBitsNoEof(i32, 8); // rw[7:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 4; // by[4]
                g[0] |= try reader.readBitsNoEof(i32, 8); // gw[7:0]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 5; // by[5]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 4; // gy[4]
                b[0] |= try reader.readBitsNoEof(i32, 8); // bw[7:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 5; // bz[5]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 4; // bz[4]
                r[1] |= try reader.readBitsNoEof(i32, 5); // bw[4:0]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 4; // gz[4]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 5); // gx[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gz[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 6); // bx[5:0]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 5); // ry[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                r[3] |= try reader.readBitsNoEof(i32, 5); // rz[4:0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 8;
            },
            // Mode 10
            0b11110 => {
                // Partition indices: 46 bits
                // Partition: 5 bits
                // Color Endpoints: 72 bits (6666, 6666, 6666)
                r[0] |= try reader.readBitsNoEof(i32, 6); // rw[5:0]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 4; // gz[4]
                b[3] |= try reader.readBitsNoEof(i32, 1); // bz[0]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 1; // bz[1]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 4; // by[4]
                g[0] |= try reader.readBitsNoEof(i32, 6); // gw[5:0]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 5; // gy[5]
                b[2] |= try reader.readBitsNoEof(i32, 1) << 5; // by[5]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 2; // bz[2]
                g[2] |= try reader.readBitsNoEof(i32, 1) << 4; // gy[4]
                b[0] |= try reader.readBitsNoEof(i32, 6); // bw[5:0]
                g[3] |= try reader.readBitsNoEof(i32, 1) << 5; // gz[5]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 3; // bz[3]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 5; // bz[5]
                b[3] |= try reader.readBitsNoEof(i32, 1) << 4; // bz[4]
                r[1] |= try reader.readBitsNoEof(i32, 6); // rx[5:0]
                g[2] |= try reader.readBitsNoEof(i32, 4); // gy[3:0]
                g[1] |= try reader.readBitsNoEof(i32, 6); // gx[5:0]
                g[3] |= try reader.readBitsNoEof(i32, 4); // gz[3:0]
                b[1] |= try reader.readBitsNoEof(i32, 6); // bx[5:0]
                b[2] |= try reader.readBitsNoEof(i32, 4); // by[3:0]
                r[2] |= try reader.readBitsNoEof(i32, 6); // ry[5:0]
                r[3] |= try reader.readBitsNoEof(i32, 6); // rz[5:0]
                partition = try reader.readBitsNoEof(i32, 5); // d[4:0]
                mode = 9;
            },
            // Mode 11
            0b00011 => {
                // Partition indices: 63 bits
                // Partition: 0 bits
                // Color Endpoints: 60 bits (10.10, 10.10, 10.10)
                r[0] |= try reader.readBitsNoEof(i32, 10); // rw[9:0]
                g[0] |= try reader.readBitsNoEof(i32, 10); // gw[9:0]
                b[0] |= try reader.readBitsNoEof(i32, 10); // bw[9:0]
                r[1] |= try reader.readBitsNoEof(i32, 10); // rx[9:0]
                g[1] |= try reader.readBitsNoEof(i32, 10); // gx[9:0]
                b[1] |= try reader.readBitsNoEof(i32, 10); // bx[9:0]
                mode = 10;
            },
            // Mode 12
            0b00111 => {
                // Partition indices: 63 bits
                // Partition: 0 bits
                // Color Endpoints: 60 bits (11.9, 11.9, 11.9)
                r[0] |= try reader.readBitsNoEof(i32, 10); // rw[9:0]
                g[0] |= try reader.readBitsNoEof(i32, 10); // gw[9:0]
                b[0] |= try reader.readBitsNoEof(i32, 10); // bw[9:0]
                r[1] |= try reader.readBitsNoEof(i32, 9); // rx[8:0]
                r[0] |= try reader.readBitsNoEof(i32, 1) << 10; // rw[10]
                g[1] |= try reader.readBitsNoEof(i32, 9); // gx[8:0]
                g[0] |= try reader.readBitsNoEof(i32, 1) << 10; // gw[10]
                b[1] |= try reader.readBitsNoEof(i32, 9); // bx[8:0]
                b[0] |= try reader.readBitsNoEof(i32, 1) << 10; // bw[10]
                mode = 11;
            },
            // Mode 13
            0b01011 => {
                // Partition indices: 63 bits
                // Partition: 0 bits
                // Color Endpoints: 60 bits (12.8, 12.8, 12.8)
                r[0] |= try reader.readBitsNoEof(i32, 10); // rw[9:0]
                g[0] |= try reader.readBitsNoEof(i32, 10); // gw[9:0]
                b[0] |= try reader.readBitsNoEof(i32, 10); // bw[9:0]
                r[1] |= try reader.readBitsNoEof(i32, 8); // rx[7:0]
                r[0] |= @as(i32, @bitReverse(try reader.readBitsNoEof(i2, 2))) << 10; // rx[10:11]
                g[1] |= try reader.readBitsNoEof(i32, 8); // gx[7:0]
                g[0] |= @as(i32, @bitReverse(try reader.readBitsNoEof(i2, 2))) << 10; // gx[10:11]
                b[1] |= try reader.readBitsNoEof(i32, 8); // bx[7:0]
                b[0] |= @as(i32, @bitReverse(try reader.readBitsNoEof(i2, 2))) << 10; // bx[10:11]
                mode = 12;
            },
            // Mode 14
            0b01111 => {
                // Partition indices: 63 bits
                // Partition: 0 bits
                // Color Endpoints: 60 bits (16.4, 16.4, 16.4)
                r[0] |= try reader.readBitsNoEof(i32, 10); // rw[9:0]
                g[0] |= try reader.readBitsNoEof(i32, 10); // gw[9:0]
                b[0] |= try reader.readBitsNoEof(i32, 10); // bw[9:0]
                r[1] |= try reader.readBitsNoEof(i32, 4); // rx[3:0]
                r[0] |= @as(i32, @bitReverse(try reader.readBitsNoEof(i6, 6))) << 10; // rw[10:15]
                g[1] |= try reader.readBitsNoEof(i32, 4); // gx[3:0]
                g[0] |= @as(i32, @bitReverse(try reader.readBitsNoEof(i6, 6))) << 10; // gw[10:15]
                b[1] |= try reader.readBitsNoEof(i32, 4); // bx[3:0]
                b[0] |= @as(i32, @bitReverse(try reader.readBitsNoEof(i6, 6))) << 10; // bw[10:15]
                mode = 13;
            },
            else => {
                // Modes 10011, 10111, 11011, and 11111 (not shown) are reserved.
                return texels;
            },
        }

        const num_partitions: u32 = if (mode >= 10) 0 else 1;

        const actual_bits0_mode = actual_bits_count[0][mode];

        if (options.is_signed) {
            r[0] = extend_sign(r[0], actual_bits0_mode);
            g[0] = extend_sign(g[0], actual_bits0_mode);
            b[0] = extend_sign(b[0], actual_bits0_mode);
        }

        // Mode 11 (like Mode 10) does not use delta compression,
        // and instead stores both color endpoints explicitly.
        if (mode != 9 and mode != 10 or options.is_signed) {
            for (1..(num_partitions + 1) * 2) |i| {
                r[i] = extend_sign(r[i], actual_bits_count[1][mode]);
                g[i] = extend_sign(g[i], actual_bits_count[2][mode]);
                b[i] = extend_sign(b[i], actual_bits_count[3][mode]);
            }
        }

        if (mode != 9 and mode != 10) {
            for (1..(num_partitions + 1) * 2) |i| {
                r[i] = transform_inverse(r[i], r[0], actual_bits0_mode, options.is_signed);
                g[i] = transform_inverse(g[i], g[0], actual_bits0_mode, options.is_signed);
                b[i] = transform_inverse(b[i], b[0], actual_bits0_mode, options.is_signed);
            }
        }

        for (0..(num_partitions + 1) * 2) |i| {
            r[i] = unquantize(r[i], actual_bits0_mode, options.is_signed);
            g[i] = unquantize(g[i], actual_bits0_mode, options.is_signed);
            b[i] = unquantize(b[i], actual_bits0_mode, options.is_signed);
        }

        const weights: []const i32 = if (mode >= 10) &weight4 else &weight3;

        for (0..texel_height) |i| {
            for (0..texel_width) |j| {
                var partition_set: u8 = if (mode >= 10)
                    if (i | j == 0) 128 else 0
                else
                    partition_sets[@intCast(partition)][i][j];

                var index_bits: u16 = if (mode >= 10) 4 else 3;

                if (partition_set & 0x80 != 0) {
                    index_bits -= 1;
                }

                partition_set &= 0x01;

                const index: i32 = try reader.readBitsNoEof(i32, index_bits);
                const ep_i = (partition_set * 2);

                const final_r = finish_unquantize(interpolate(r[ep_i], r[ep_i + 1], weights, index), options.is_signed);
                const final_g = finish_unquantize(interpolate(g[ep_i], g[ep_i + 1], weights, index), options.is_signed);
                const final_b = finish_unquantize(interpolate(b[ep_i], b[ep_i + 1], weights, index), options.is_signed);

                texels[i * texel_width + j] = .{
                    .r = @bitCast(final_r),
                    .g = @bitCast(final_g),
                    .b = @bitCast(final_b),
                };
            }
        }
        return texels;
    }

    pub fn encodeBlock(raw_texels: [texel_count]TexelFormat, options: EncodeOptions) !BC6Block {
        var encoder = BC6Enc.createEncoder(raw_texels, options);
        encoder.setupEncoder();
        encoder.compressBlock();
        return encoder.getBestBlock();
    }

    fn extend_sign(val: i32, bits: i32) i32 {
        // http://graphics.stanford.edu/~seander/bithacks.html#VariableSignExtend

        const shift_amount = 32 - bits;
        return std.math.shr(i32, std.math.shl(i32, val, shift_amount), shift_amount);
    }

    fn transform_inverse(val: i32, a0: i32, bits: i32, is_signed: bool) i32 {
        // If the precision of A0 is "p" bits, then the transform algorithm is:
        // B0 = (B0 + A0) & ((1 << p) - 1)

        const bit_mask = std.math.shl(i32, 1, bits) - 1;
        const transformed = (val + a0) & bit_mask;

        return if (is_signed)
            extend_sign(transformed, bits)
        else
            transformed;
    }

    fn finish_unquantize(val: i32, is_signed: bool) u16 {
        if (!is_signed) {
            // Scale the magnitude by 31 / 64
            const result = ((val * 31) >> 6);
            return @intCast(result);
        } else {
            // Scale the magnitude by 31 / 32
            const scaled = if (val < 0)
                -(((-val) * 31) >> 5)
            else
                (val * 31) >> 5;

            const sign_bit: i32 = if (scaled < 0) 0x8000 else 0;
            const magnitude = if (scaled < 0) -scaled else scaled;

            const result = sign_bit | magnitude;
            return @intCast(result);
        }
    }

    fn unquantize(val: i32, bits: i32, is_signed: bool) i32 {
        if (!is_signed) {
            if (bits >= 15) {
                return val;
            } else if (val == 0) {
                return 0;
            } else if (val == std.math.shl(i32, 1, bits) - 1) {
                return 0xFFFF;
            } else {
                return std.math.shr(i32, (val << 16) + 0x8000, bits);
            }
        } else if (bits >= 16) {
            return val;
        } else {
            const s = val < 0;
            const v = if (val < 0) -val else val;

            const unq = if (v == 0)
                0
            else if (v >= std.math.shl(i32, 1, bits - 1) - 1)
                0x7FFF
            else
                std.math.shr(i32, (v << 15) + 0x4000, bits - 1);

            return if (s) -unq else unq;
        }
    }

    fn interpolate(a: i32, b: i32, weights: []const i32, index: i32) i32 {
        const idx: usize = @intCast(index);
        const result = (a * (64 - weights[idx]) + b * weights[idx] + 32) >> 6;
        return result;
    }

    const weight3 = [_]i32{ 0, 9, 18, 27, 37, 46, 55, 64 };

    const weight4 = [_]i32{ 0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64 };

    const actual_bits_count = [4][14]u8{
        .{ 10, 7, 11, 11, 11, 9, 8, 8, 8, 6, 10, 11, 12, 16 }, // W
        .{ 5, 6, 5, 4, 4, 5, 6, 5, 5, 6, 10, 9, 8, 4 }, // dR
        .{ 5, 6, 4, 5, 4, 5, 5, 6, 5, 6, 10, 9, 8, 4 }, // dG
        .{ 5, 6, 4, 4, 5, 5, 5, 5, 6, 6, 10, 9, 8, 4 }, // dB
    };

    const partition_sets = [32][4][4]u8{
        .{ .{ 128, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 129 } }, //  0
        .{ .{ 128, 0, 0, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 129 } }, //  1
        .{ .{ 128, 1, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 0, 1, 1, 129 } }, //  2
        .{ .{ 128, 0, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 1, 1, 129 } }, //  3
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 1, 129 } }, //  4
        .{ .{ 128, 0, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, //  5
        .{ .{ 128, 0, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, //  6
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 1, 1, 129 } }, //  7
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 1, 129 } }, //  8
        .{ .{ 128, 0, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, //  9
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, // 10
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 1 }, .{ 0, 1, 1, 129 } }, // 11
        .{ .{ 128, 0, 0, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, // 12
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, // 13
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 129 } }, // 14
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 1, 1, 1, 129 } }, // 15
        .{ .{ 128, 0, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 1, 1, 1, 0 }, .{ 1, 1, 1, 129 } }, // 16
        .{ .{ 128, 1, 129, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 } }, // 17
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 129, 0, 0, 0 }, .{ 1, 1, 1, 0 } }, // 18
        .{ .{ 128, 1, 129, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 } }, // 19
        .{ .{ 128, 0, 129, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 } }, // 20
        .{ .{ 128, 0, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 129, 1, 0, 0 }, .{ 1, 1, 1, 0 } }, // 21
        .{ .{ 128, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 129, 0, 0, 0 }, .{ 1, 1, 0, 0 } }, // 22
        .{ .{ 128, 1, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 0, 0, 0, 129 } }, // 23
        .{ .{ 128, 0, 129, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 } }, // 24
        .{ .{ 128, 0, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 129, 0, 0, 0 }, .{ 1, 1, 0, 0 } }, // 25
        .{ .{ 128, 1, 129, 0 }, .{ 0, 1, 1, 0 }, .{ 0, 1, 1, 0 }, .{ 0, 1, 1, 0 } }, // 26
        .{ .{ 128, 0, 129, 1 }, .{ 0, 1, 1, 0 }, .{ 0, 1, 1, 0 }, .{ 1, 1, 0, 0 } }, // 27
        .{ .{ 128, 0, 0, 1 }, .{ 0, 1, 1, 1 }, .{ 129, 1, 1, 0 }, .{ 1, 0, 0, 0 } }, // 28
        .{ .{ 128, 0, 0, 0 }, .{ 1, 1, 1, 1 }, .{ 129, 1, 1, 1 }, .{ 0, 0, 0, 0 } }, // 29
        .{ .{ 128, 1, 129, 1 }, .{ 0, 0, 0, 1 }, .{ 1, 0, 0, 0 }, .{ 1, 1, 1, 0 } }, // 30
        .{ .{ 128, 0, 129, 1 }, .{ 1, 0, 0, 1 }, .{ 1, 0, 0, 1 }, .{ 1, 1, 0, 0 } }, // 31
    };
};

test "bc6 decompress" {
    const Dimensions = @import("../core/Dimensions.zig");
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/night.bc6u", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 1024,
            .height = 512,
        };

        const decompress_result = try texzel.decode(allocator, .bc6, RGBA16F, dimensions, read_result, .{ .is_signed = false });
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0x24F7A19D;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/night.bc6s", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 1024,
            .height = 512,
        };

        const decompress_result = try texzel.decode(allocator, .bc6, RGBA16F, dimensions, read_result, .{ .is_signed = true });
        defer decompress_result.deinit();

        const hash = std.hash.Crc32.hash(decompress_result.asBuffer());

        const expected_hash = 0xB52DE479;

        try std.testing.expectEqual(expected_hash, hash);
    }
}

test "bc6 compress" {
    const RawImageData = @import("../core/raw_image_data.zig").RawImageData;
    const Dimensions = @import("../core/Dimensions.zig");
    const texzel = @import("../texzel.zig");

    const allocator = std.testing.allocator;

    {
        const file = try std.fs.cwd().openFile("resources/night.rgba16f", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 10 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 1024,
            .height = 512,
        };

        const rgba_image = try RawImageData(RGBA16F).initFromBuffer(allocator, dimensions, read_result);
        defer rgba_image.deinit();

        const compressed = try texzel.encode(allocator, .bc6, RGBA16F, rgba_image, .default);
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0xBFA36F5D;

        try std.testing.expectEqual(expected_hash, hash);
    }

    {
        const file = try std.fs.cwd().openFile("resources/night.rgba16f", .{ .mode = .read_only });
        defer file.close();

        const read_result = try file.readToEndAlloc(allocator, 10 << 20);
        defer allocator.free(read_result);

        const dimensions = Dimensions{
            .width = 1024,
            .height = 512,
        };

        const rgba_image = try RawImageData(RGBA16F).initFromBuffer(allocator, dimensions, read_result);
        defer rgba_image.deinit();

        const compressed = try texzel.encode(allocator, .bc6, RGBA16F, rgba_image, .slow);
        defer allocator.free(compressed);

        const hash = std.hash.Crc32.hash(compressed);

        const expected_hash = 0x530BF497;

        try std.testing.expectEqual(expected_hash, hash);
    }
}
