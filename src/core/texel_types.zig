pub const RGBA8U = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,
};

pub const BGRA8U = extern struct {
    b: u8 = 0,
    g: u8 = 0,
    r: u8 = 0,
    a: u8 = 255,
};

pub const RGBA16U = extern struct {
    r: u16 = 0,
    g: u16 = 0,
    b: u16 = 0,
    a: u16 = 1.0,
};

pub const RGBA16F = extern struct {
    r: f16 = 0,
    g: f16 = 0,
    b: f16 = 0,
    a: f16 = 1.0,
};

pub const R8U = struct {
    r: u8 = 0,
};

pub const RG8U = struct {
    r: u8 = 0,
    g: u8 = 0,
};
