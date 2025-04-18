pub const RGBA8U = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBA8U) * width * height;
    }
};

pub const RGBA16U = extern struct {
    r: u16 = 0,
    g: u16 = 0,
    b: u16 = 0,
    a: u16 = 1.0,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBA16U) * width * height;
    }
};

pub const RGBA16F = extern struct {
    r: f16 = 0,
    g: f16 = 0,
    b: f16 = 0,
    a: f16 = 1.0,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBA16F) * width * height;
    }
};
