pub const RGBATexel = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBATexel) * width * height;
    }
};
