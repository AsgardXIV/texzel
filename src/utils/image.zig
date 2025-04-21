/// This whole file is just for testing for now
const std = @import("std");

pub fn writeTGA(filename: []const u8, width: u32, height: u32, rgba_data: []const u8) !void {
    const TGAHeader = extern struct {
        id_length: u8 align(1),
        color_map_type: u8 align(1),
        image_type: u8 align(1),
        color_map_spec: [5]u8 align(1),
        x_origin: u16 align(1),
        y_origin: u16 align(1),
        width: u16 align(1),
        height: u16 align(1),
        pixel_depth: u8 align(1),
        image_descriptor: u8 align(1),
    };

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const header = TGAHeader{
        .id_length = 0,
        .color_map_type = 0,
        .image_type = 2,
        .color_map_spec = [5]u8{ 0, 0, 0, 0, 0 },
        .x_origin = 0,
        .y_origin = 0,
        .width = @intCast(width),
        .height = @intCast(height),
        .pixel_depth = 32,
        .image_descriptor = 0x28,
    };

    try file.writer().writeStruct(header);
    try file.writeAll(rgba_data);
}

pub fn writeDDS(filename: []const u8, width: u32, height: u32, four_cc: []const u8, raw_data: []const u8) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const DDS_MAGIC = "DDS ";

    const DDS_HEADER_SIZE = 124;
    const DDS_PIXELFORMAT_SIZE = 32;
    const DDSD_CAPS = 0x1;
    const DDSD_HEIGHT = 0x2;
    const DDSD_WIDTH = 0x4;
    const DDSD_PIXELFORMAT = 0x1000;
    const DDSD_LINEARSIZE = 0x80000;

    const DDPF_FOURCC = 0x4;

    const DDSCAPS_TEXTURE = 0x1000;

    const DDSHeader = extern struct {
        size: u32 align(1) = DDS_HEADER_SIZE,
        flags: u32 align(1) = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_LINEARSIZE,
        height: u32 align(1),
        width: u32 align(1),
        pitchOrLinearSize: u32 align(1),
        depth: u32 align(1) = 0,
        mipMapCount: u32 align(1) = 0,
        reserved1: [11]u32 align(1) = @splat(0),

        // pixel format (DDS_PIXELFORMAT)
        pf_size: u32 align(1) = DDS_PIXELFORMAT_SIZE,
        pf_flags: u32 align(1) = DDPF_FOURCC,
        pf_fourcc: u32 align(1) = 0,
        pf_rgb_bitcount: u32 align(1) = 0,
        pf_r_bitmask: u32 align(1) = 0,
        pf_g_bitmask: u32 align(1) = 0,
        pf_b_bitmask: u32 align(1) = 0,
        pf_a_bitmask: u32 align(1) = 0,

        caps: u32 align(1) = DDSCAPS_TEXTURE,
        caps2: u32 align(1) = 0,
        caps3: u32 align(1) = 0,
        caps4: u32 align(1) = 0,
        reserved2: u32 align(1) = 0,
    };

    const DDSHeaderDXT10 = extern struct {
        dxgi_format: u32 align(1) = 0,
        resource_dimension: u32 align(1) = 0,
        misc_flag: u32 align(1) = 0,
        array_size: u32 align(1) = 0,
        misc_flags2: u32 align(1) = 0,
    };

    var header = DDSHeader{
        .height = height,
        .width = width,
        .pitchOrLinearSize = @intCast(raw_data.len),
        .pf_fourcc = @bitCast(@as([4]u8, four_cc[0..4].*)),
    };

    var dx10header: ?DDSHeaderDXT10 = null;

    if (std.mem.eql(u8, "BC4 ", four_cc)) {
        header.pf_fourcc = @bitCast(@as([4]u8, "DX10"[0..4].*));
        dx10header = DDSHeaderDXT10{
            .dxgi_format = 80,
            .resource_dimension = 3,
            .misc_flag = 0,
            .array_size = 1,
            .misc_flags2 = 0,
        };
    }

    if (std.mem.eql(u8, "RG  ", four_cc)) {
        header.pf_fourcc = 0;
        header.pf_rgb_bitcount = 16;
        header.pf_r_bitmask = 0xFF00;
        header.pf_g_bitmask = 0xFF;
        header.pf_b_bitmask = 0x0;
        header.pf_a_bitmask = 0x0;
        header.pf_flags = 0x40;
    }

    if (std.mem.eql(u8, "F16 ", four_cc)) {
        header.pf_fourcc = @bitCast(@as([4]u8, "DX10"[0..4].*));
        dx10header = DDSHeaderDXT10{
            .dxgi_format = 10,
            .resource_dimension = 3,
            .misc_flag = 0,
            .array_size = 1,
            .misc_flags2 = 0,
        };
    }

    const writer = file.writer();
    try writer.writeAll(DDS_MAGIC);
    try writer.writeStruct(header);

    if (dx10header) |dx10|
        try writer.writeStruct(dx10);

    try writer.writeAll(raw_data);
}
