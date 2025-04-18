pub const RGBA8Texel = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBA8Texel) * width * height;
    }
};

pub const RGBATexel = RGBA8Texel;

pub const RGBA16Texel = extern struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBA16Texel) * width * height;
    }
};
