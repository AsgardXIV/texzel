const Dimensions = @This();

width: u32,
height: u32,

pub fn size(self: Dimensions) u32 {
    return self.width * self.height;
}
