const std = @import("std");

pub fn writeTGA(filename: []const u8, width: u32, height: u32, rgba_data: []const u8) !void {
    const TGAHeader = extern struct {
        id_length: u8,
        color_map_type: u8,
        image_type: u8,
        color_map_spec: [5]u8,
        x_origin: u16,
        y_origin: u16,
        width: u16,
        height: u16,
        pixel_depth: u8,
        image_descriptor: u8,
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
