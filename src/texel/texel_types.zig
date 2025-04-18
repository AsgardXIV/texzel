pub const RGBA8U = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBA8U) * width * height;
    }
};

pub const RGBA16U = extern struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBA16U) * width * height;
    }
};

pub const RGBA16F = extern struct {
    r: f16,
    g: f16,
    b: f16,
    a: f16,

    pub fn byteSizeForTexels(width: u32, height: u32) usize {
        return @sizeOf(RGBA16F) * width * height;
    }
};
