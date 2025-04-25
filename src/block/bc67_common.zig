// Portions of this file are based on bcdec and block_compression.
// See THIRD_PARTY_LICENSES.md in this project for more information.

const std = @import("std");

pub fn blockQuant(qblock: *[2]u32, block: *[64]f32, bits: u32, ep: []f32, pattern: u32, channels: u32) f32 {
    const levels = std.math.shl(i32, 1, bits);

    var total_err: f32 = 0.0;

    qblock[0] = 0;
    qblock[1] = 0;

    var pattern_shifted = pattern;
    for (0..16) |k| {
        const j = pattern_shifted & 3;
        pattern_shifted >>= 2;

        var proj: f32 = 0.0;
        var div: f32 = 0.0;

        for (0..channels) |p| {
            const ep_a = ep[8 * j + p];
            const ep_b = ep[8 * j + 4 + p];
            proj += (block[k + p * 16] - ep_a) * (ep_b - ep_a);
            div += (ep_b - ep_a) * (ep_b - ep_a);
        }

        proj /= div;

        if (std.math.isNan(proj) or std.math.isInf(proj)) {
            proj = 0.0;
        }

        const flevels: f32 = @floatFromInt(levels);
        const q1 = proj * flevels + 0.5;
        const v: i32 = @intFromFloat(q1);
        const q1_clamped = std.math.clamp(v, 1, levels - 1);

        var err0: f32 = 0.0;
        var err1: f32 = 0.0;
        const w0 = getUnquantValue(bits, q1_clamped - 1);
        const w1 = getUnquantValue(bits, q1_clamped);

        for (0..channels) |p| {
            const ep_a = ep[8 * j + p];
            const ep_b = ep[8 * j + 4 + p];

            const ep_a_i: i32 = @intFromFloat(ep_a);
            const ep_b_i: i32 = @intFromFloat(ep_b);

            const dec_v0_i: i32 = @divTrunc((64 - w0) * ep_a_i + w0 * ep_b_i + 32, 64);
            const dec_v1_i: i32 = @divTrunc((64 - w1) * ep_a_i + w1 * ep_b_i + 32, 64);

            const dec_v0: f32 = @floatFromInt(dec_v0_i);
            const dec_v1: f32 = @floatFromInt(dec_v1_i);

            err0 += (dec_v0 - block[k + p * 16]) * (dec_v0 - block[k + p * 16]);
            err1 += (dec_v1 - block[k + p * 16]) * (dec_v1 - block[k + p * 16]);
        }

        var best_err = err1;
        var best_q = q1_clamped;
        if (err0 < err1) {
            best_err = err0;
            best_q = q1_clamped - 1;
        }

        qblock[k / 8] |= @as(u32, @intCast(best_q)) << @intCast(4 * (k % 8));
        total_err += best_err;
    }

    return total_err;
}

pub fn blockSegmentCore(ep: []f32, block: *[64]f32, mask: u32, channels: u32) void {
    var axis: [4]f32 = @splat(0.0);
    var dc: [4]f32 = @splat(0.0);
    blockPcaAxis(&axis, &dc, block, mask, channels);

    var ext = [_]f32{ std.math.inf(f32), -std.math.inf(f32) };

    var mask_shifted: u32 = mask << 1;
    for (0..16) |k| {
        mask_shifted >>= 1;
        if (mask_shifted & 1 == 0) continue;

        var dot: f32 = 0.0;
        for (0..channels) |p| {
            dot += axis[p] * (block[16 * p + k] - dc[p]);
        }

        ext[0] = @min(ext[0], dot);
        ext[1] = @max(ext[1], dot);
    }

    // Create some distance if the endpoints collapse
    if (ext[1] - ext[0] < 1.0) {
        ext[0] -= 0.5;
        ext[1] += 0.5;
    }

    for (0..2) |i| {
        for (0..channels) |p| {
            const tasty = ext[i] * axis[p] + dc[p];
            ep[4 * i + p] = tasty;
        }
    }
}

pub fn blockPcaAxis(axis: *[4]f32, dc: *[4]f32, block: *[64]f32, mask: u32, channels: u32) void {
    const power_iterations: u32 = 8;

    var covar: [10]f32 = @splat(0.0);
    computeCovarDcMasked(&covar, dc, block, mask, channels);

    const inv_var: f32 = 1.0 / (256.0 * 256.0);
    for (&covar) |*item| {
        item.* *= inv_var;
    }

    const eps_var = @as(f32, @floatCast(0.001));
    const eps: f32 = eps_var * eps_var;
    covar[0] += eps;
    covar[4] += eps;
    covar[7] += eps;
    covar[9] += eps;

    computeAxis(axis, &covar, power_iterations, channels);
}

pub fn computeStatsMasked(stats: *[15]f32, block: *[64]f32, mask: u32, channels: u32) void {
    var mask_shifted = mask << 1;
    for (0..16) |k| {
        mask_shifted >>= 1;
        const flag: f32 = @floatFromInt(mask_shifted & 1);

        var rgba: [4]f32 = @splat(0.0);
        for (0..channels) |p| {
            rgba[p] = block[k + p * 16] * flag;
        }

        stats[14] += flag;

        stats[10] += rgba[0];
        stats[11] += rgba[1];
        stats[12] += rgba[2];

        stats[0] += rgba[0] * rgba[0];
        stats[1] += rgba[0] * rgba[1];
        stats[2] += rgba[0] * rgba[2];

        stats[4] += rgba[1] * rgba[1];
        stats[5] += rgba[1] * rgba[2];

        stats[7] += rgba[2] * rgba[2];

        if (channels == 4) {
            stats[13] += rgba[3];
            stats[3] += rgba[0] * rgba[3];
            stats[6] += rgba[1] * rgba[3];
            stats[8] += rgba[2] * rgba[3];
            stats[9] += rgba[3] * rgba[3];
        }
    }
}

pub fn covarFromStats(covar: *[10]f32, stats: *[15]f32, channels: u32) void {
    covar[0] = stats[0] - stats[10] * stats[10] / stats[14];
    covar[1] = stats[1] - stats[10] * stats[11] / stats[14];
    covar[2] = stats[2] - stats[10] * stats[12] / stats[14];

    covar[4] = stats[4] - stats[11] * stats[11] / stats[14];
    covar[5] = stats[5] - stats[11] * stats[12] / stats[14];

    covar[7] = stats[7] - stats[12] * stats[12] / stats[14];

    if (channels == 4) {
        covar[3] = stats[3] - stats[10] * stats[13] / stats[14];
        covar[6] = stats[6] - stats[11] * stats[13] / stats[14];
        covar[8] = stats[8] - stats[12] * stats[13] / stats[14];
        covar[9] = stats[9] - stats[13] * stats[13] / stats[14];
    }
}

fn computeCovarDcMasked(covar: *[10]f32, dc: *[4]f32, block: *[64]f32, mask: u32, channels: u32) void {
    var stats: [15]f32 = @splat(0.0);
    computeStatsMasked(&stats, block, mask, channels);

    for (0..channels) |p| {
        dc[p] = stats[10 + p] / stats[14];
    }

    covarFromStats(covar, &stats, channels);
}

pub fn blockPcaBoundSplit(block: *[64]f32, mask: u32, full_stats: *[15]f32, channels: u32) f32 {
    var stats: [15]f32 = @splat(0.0);
    computeStatsMasked(&stats, block, mask, channels);

    var covar1: [10]f32 = @splat(0.0);
    covarFromStats(&covar1, &stats, channels);

    for (0..15) |i| {
        stats[i] = full_stats[i] - stats[i];
    }

    var covar2: [10]f32 = @splat(0.0);
    covarFromStats(&covar2, &stats, channels);

    var bound: f32 = 0.0;
    bound += getPcaBound(&covar1, channels);
    bound += getPcaBound(&covar2, channels);

    return @sqrt(bound) * 256.0;
}

// Principal Component Analysis (PCA) bound
pub fn getPcaBound(covar: *[10]f32, channels: u32) f32 {
    const power_iterations: u32 = 4; // Quite approximative, but enough for bounding

    var covar_scaled: [10]f32 = undefined;
    @memcpy(&covar_scaled, covar);

    const inv_var: f32 = 1.0 / (256.0 * 256.0);

    for (&covar_scaled) |*scaled| {
        scaled.* *= inv_var;
    }

    const eps_var = @as(f32, @floatCast(0.001));
    const eps: f32 = eps_var * eps_var;
    covar_scaled[0] += eps;
    covar_scaled[4] += eps;
    covar_scaled[7] += eps;
    covar_scaled[9] += eps;

    var axis: [4]f32 = @splat(0.0);
    computeAxis(&axis, &covar_scaled, power_iterations, channels);

    var a_vec: [4]f32 = @splat(0.0);

    if (channels == 3) {
        ssymv3(&a_vec, &covar_scaled, &axis);
    } else {
        ssymv4(&a_vec, &covar_scaled, &axis);
    }

    var sq_sum: f32 = 0.0;
    for (a_vec[0..channels]) |*item| {
        sq_sum += item.* * item.*;
    }
    const lambda: f32 = @sqrt(sq_sum);

    var bound: f32 = covar_scaled[0] + covar_scaled[4] + covar_scaled[7];
    if (channels == 4) {
        bound += covar_scaled[9];
    }
    bound -= lambda;

    return @max(bound, 0.0);
}

pub fn computeAxis(axis: *[4]f32, covar: *[10]f32, power_iterations: u32, channels: u32) void {
    var a_vec: [4]f32 = @splat(1.0);

    for (0..power_iterations) |i| {
        if (channels == 3) {
            ssymv3(axis, covar, &a_vec);
        } else {
            ssymv4(axis, covar, &a_vec);
        }

        @memcpy(a_vec[0..channels], axis[0..channels]);

        if (i % 2 == 1) {
            var norm_sq: f32 = 0.0;
            for (0..channels) |p| {
                norm_sq += axis[p] * axis[p];
            }

            const rnorm = 1.0 / @sqrt(norm_sq);
            for (a_vec[0..channels]) |*item| {
                item.* *= rnorm;
            }
        }
    }

    @memcpy(axis[0..channels], a_vec[0..channels]);
}

pub fn optEndpoints(ep: []f32, block: *[64]f32, bits: u32, qblock: *[2]u32, mask: u32, channels: u32) void {
    const levels = std.math.shl(i32, 1, bits);
    const alevels = @as(f32, @floatFromInt(levels - 1));

    var atb1: [4]f32 = @splat(0.0);
    var sum_q: f32 = 0.0;
    var sum_qq: f32 = 0.0;
    var sum: [5]f32 = @splat(0.0);

    var mask_shifted: u32 = mask << 1;

    for (0..2) |k1| {
        var qbits_shifted = qblock[k1];
        for (0..8) |k2| {
            const k = k1 * 8 + k2;
            const q = @as(f32, @floatFromInt(qbits_shifted & 15));
            qbits_shifted >>= 4;

            mask_shifted >>= 1;
            if (mask_shifted & 1 == 0) continue;

            const x = alevels - q;

            sum_q += q;
            sum_qq += q * q;

            sum[4] += 1.0;
            for (0..channels) |p| {
                sum[p] += block[k + p * 16];
                atb1[p] += x * block[k + p * 16];
            }
        }
    }

    var atb2: [4]f32 = @splat(0.0);
    for (0..channels) |p| {
        atb2[p] = alevels * sum[p] - atb1[p];
    }

    const cxx = sum[4] * (alevels * alevels) - 2.0 * alevels * sum_q + sum_qq;
    const cyy = sum_qq;
    const cxy = alevels * sum_q - sum_qq;
    const scale = alevels / (cxx * cyy - cxy * cxy);

    for (0..channels) |p| {
        ep[p] = (atb1[p] * cyy - atb2[p] * cxy) * scale;
        ep[4 + p] = (atb2[p] * cxx - atb1[p] * cxy) * scale;
    }

    if (@abs(cxx * cyy - cxy * cxy) < 0.001) {
        for (0..channels) |p| {
            ep[p] = sum[p] / sum[4];
            ep[4 + p] = ep[p];
        }
    }
}

pub fn ssymv3(a: *[4]f32, covar: *[10]f32, b: *[4]f32) void {
    a[0] = covar[0] * b[0] + covar[1] * b[1] + covar[2] * b[2];
    a[1] = covar[1] * b[0] + covar[4] * b[1] + covar[5] * b[2];
    a[2] = covar[2] * b[0] + covar[5] * b[1] + covar[7] * b[2];
}

pub fn ssymv4(a: *[4]f32, covar: *[10]f32, b: *[4]f32) void {
    a[0] = covar[0] * b[0] + covar[1] * b[1] + covar[2] * b[2] + covar[3] * b[3];
    a[1] = covar[1] * b[0] + covar[4] * b[1] + covar[5] * b[2] + covar[6] * b[3];
    a[2] = covar[2] * b[0] + covar[5] * b[1] + covar[7] * b[2] + covar[8] * b[3];
    a[3] = covar[3] * b[0] + covar[6] * b[1] + covar[8] * b[2] + covar[9] * b[3];
}

pub fn getPattern(part_id: i32) u32 {
    const pattern_table = [_]u32{
        0x50505050, 0x40404040, 0x54545454, 0x54505040, 0x50404000, 0x55545450, 0x55545040,
        0x54504000, 0x50400000, 0x55555450, 0x55544000, 0x54400000, 0x55555440, 0x55550000,
        0x55555500, 0x55000000, 0x55150100, 0x00004054, 0x15010000, 0x00405054, 0x00004050,
        0x15050100, 0x05010000, 0x40505054, 0x00404050, 0x05010100, 0x14141414, 0x05141450,
        0x01155440, 0x00555500, 0x15014054, 0x05414150, 0x44444444, 0x55005500, 0x11441144,
        0x05055050, 0x05500550, 0x11114444, 0x41144114, 0x44111144, 0x15055054, 0x01055040,
        0x05041050, 0x05455150, 0x14414114, 0x50050550, 0x41411414, 0x00141400, 0x00041504,
        0x00105410, 0x10541000, 0x04150400, 0x50410514, 0x41051450, 0x05415014, 0x14054150,
        0x41050514, 0x41505014, 0x40011554, 0x54150140, 0x50505500, 0x00555050, 0x15151010,
        0x54540404, 0xAA685050, 0x6A5A5040, 0x5A5A4200, 0x5450A0A8, 0xA5A50000, 0xA0A05050,
        0x5555A0A0, 0x5A5A5050, 0xAA550000, 0xAA555500, 0xAAAA5500, 0x90909090, 0x94949494,
        0xA4A4A4A4, 0xA9A59450, 0x2A0A4250, 0xA5945040, 0x0A425054, 0xA5A5A500, 0x55A0A0A0,
        0xA8A85454, 0x6A6A4040, 0xA4A45000, 0x1A1A0500, 0x0050A4A4, 0xAAA59090, 0x14696914,
        0x69691400, 0xA08585A0, 0xAA821414, 0x50A4A450, 0x6A5A0200, 0xA9A58000, 0x5090A0A8,
        0xA8A09050, 0x24242424, 0x00AA5500, 0x24924924, 0x24499224, 0x50A50A50, 0x500AA550,
        0xAAAA4444, 0x66660000, 0xA5A0A5A0, 0x50A050A0, 0x69286928, 0x44AAAA44, 0x66666600,
        0xAA444444, 0x54A854A8, 0x95809580, 0x96969600, 0xA85454A8, 0x80959580, 0xAA141414,
        0x96960000, 0xAAAA1414, 0xA05050A0, 0xA0A5A5A0, 0x96000000, 0x40804080, 0xA9A8A9A8,
        0xAAAAAA44, 0x2A4A5254,
    };

    return pattern_table[@intCast(part_id)];
}

pub fn getPatternMask(part_id: i32, j: u32) u32 {
    const pattern_mask = [_]u32{
        0xCCCC3333, 0x88887777, 0xEEEE1111, 0xECC81337, 0xC880377F, 0xFEEC0113, 0xFEC80137,
        0xEC80137F, 0xC80037FF, 0xFFEC0013, 0xFE80017F, 0xE80017FF, 0xFFE80017, 0xFF0000FF,
        0xFFF0000F, 0xF0000FFF, 0xF71008EF, 0x008EFF71, 0x71008EFF, 0x08CEF731, 0x008CFF73,
        0x73108CEF, 0x3100CEFF, 0x8CCE7331, 0x088CF773, 0x3110CEEF, 0x66669999, 0x366CC993,
        0x17E8E817, 0x0FF0F00F, 0x718E8E71, 0x399CC663, 0xAAAA5555, 0xF0F00F0F, 0x5A5AA5A5,
        0x33CCCC33, 0x3C3CC3C3, 0x55AAAA55, 0x96966969, 0xA55A5AA5, 0x73CE8C31, 0x13C8EC37,
        0x324CCDB3, 0x3BDCC423, 0x69969669, 0xC33C3CC3, 0x99666699, 0x0660F99F, 0x0272FD8D,
        0x04E4FB1B, 0x4E40B1BF, 0x2720D8DF, 0xC93636C9, 0x936C6C93, 0x39C6C639, 0x639C9C63,
        0x93366CC9, 0x9CC66339, 0x817E7E81, 0xE71818E7, 0xCCF0330F, 0x0FCCF033, 0x774488BB,
        0xEE2211DD, 0x08CC0133, 0x8CC80037, 0xCC80006F, 0xEC001331, 0x330000FF, 0x00CC3333,
        0xFF000033, 0xCCCC0033, 0x0F0000FF, 0x0FF0000F, 0x00F0000F, 0x44443333, 0x66661111,
        0x22221111, 0x136C0013, 0x008C8C63, 0x36C80137, 0x08CEC631, 0x3330000F, 0xF0000333,
        0x00EE1111, 0x88880077, 0x22C0113F, 0x443088CF, 0x0C22F311, 0x03440033, 0x69969009,
        0x9960009F, 0x03303443, 0x00660699, 0xC22C3113, 0x8C0000EF, 0x1300007F, 0xC4003331,
        0x004C1333, 0x22229999, 0x00F0F00F, 0x24929249, 0x29429429, 0xC30C30C3, 0xC03C3C03,
        0x00AA0055, 0xAA0000FF, 0x30300303, 0xC0C03333, 0x90900909, 0xA00A5005, 0xAAA0000F,
        0x0AAA0555, 0xE0E01111, 0x70700707, 0x6660000F, 0x0EE01111, 0x07707007, 0x06660999,
        0x660000FF, 0x00660099, 0x0CC03333, 0x03303003, 0x60000FFF, 0x80807777, 0x10100101,
        0x000A0005, 0x08CE8421,
    };

    const mask_packed = pattern_mask[@intCast(part_id)];
    const mask0 = mask_packed & 0xFFFF;
    const mask1 = mask_packed >> 16;

    return if (j == 2)
        ~mask0 & ~mask1
    else if (j == 0)
        mask0
    else
        mask1;
}

pub fn bc7CodeApplySwapMode456(qep: []i32, channels: u32, qblock: *[2]u32, bits: u32) void {
    const levels = std.math.shl(u32, 1, bits);

    if (qblock[0] & 15 >= @divTrunc(levels, 2)) {
        for (0..channels) |p| {
            std.mem.swap(i32, &qep[p], &qep[channels + p]);
        }

        for (qblock) |*value| {
            value.* = @subWithOverflow(0x11111111 * (levels - 1), value.*)[0];
        }
    }
}

pub fn bc7CodeApplySwapMode01237(qep: *[24]i32, qblock: *[2]u32, mode: usize, part_id: i32) u32 {
    const bits: u32 = if (mode == 0 or mode == 1) 3 else 2;
    const pairs: usize = if (mode == 0 or mode == 2) 3 else 2;

    var flips: u32 = 0;

    const levels = std.math.shl(i32, 1, bits);

    const skips = getSkips(part_id);

    for (0..pairs) |j| {
        const k0 = skips[j];

        // Extract 4 bits from qblock at position k0
        const safe_qpart: u5 = @intCast((28 - (k0 & 7) * 4));
        const q = (qblock[k0 >> 3] << safe_qpart) >> 28;

        if (q >= @divTrunc(levels, 2)) {
            for (0..4) |p| {
                std.mem.swap(i32, &qep[8 * j + p], &qep[8 * j + 4 + p]);
            }

            const pmask = getPatternMask(part_id, @intCast(j));
            flips |= pmask;
        }
    }

    return flips;
}

pub fn bc7CodeQBlock(data: *[5]u32, pos: *u32, qblock: *[2]u32, bits: u32, flips: u32) void {
    const levels = std.math.shl(u32, 1, bits);

    var flips_shifted = flips;

    for (0..2) |k1| {
        var qbits_shifted = qblock[k1];
        for (0..8) |k2| {
            var q = qbits_shifted & 15;
            if (flips_shifted & 1 > 0) {
                q = (levels - 1) - q;
            }

            if (k1 == 0 and k2 == 0) {
                putBits(data, pos, bits - 1, q);
            } else {
                putBits(data, pos, bits, q);
            }

            qbits_shifted >>= 4;
            flips_shifted >>= 1;
        }
    }
}

pub fn bc7CodeAdjustSkipMode01237(data: *[5]u32, mode: usize, part_id: i32) void {
    const bits: u32 = if (mode == 0 or mode == 1) 3 else 2;
    const pairs: usize = if (mode == 0 or mode == 2) 3 else 2;

    var skips = getSkips(part_id);

    if (pairs > 2 and skips[1] < skips[2]) {
        std.mem.swap(u32, &skips[1], &skips[2]);
    }

    for (skips[1..pairs]) |k| {
        dataShl1BitFrom(data, 128 + (pairs - 1) - (15 - k) * bits);
    }
}

pub fn dataShl1BitFrom(data: *[5]u32, from_bits: usize) void {
    if (from_bits < 96) {
        const shifted = (data[2] >> 1) | (data[3] << 31);
        const safe: u5 = @intCast(from_bits - 64);
        const mask = ((@as(u32, 1) << (safe)) - 1) >> 1;
        data[2] = (mask & data[2]) | (~mask & shifted);
        data[3] = (data[3] >> 1) | (data[4] << 31);
        data[4] >>= 1;
    } else if (from_bits < 128) {
        const shifted = (data[3] >> 1) | (data[4] << 31);
        const safe: u5 = @intCast(from_bits - 96);
        const mask = ((@as(u32, 1) << (safe)) - 1) >> 1;
        data[3] = (mask & data[3]) | (~mask & shifted);
        data[4] >>= 1;
    }
}

pub fn getSkips(part_id: i32) [3]u32 {
    const skip_table = [_]u32{
        0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0,
        0xF0, 0xF0, 0x20, 0x80, 0x20, 0x20, 0x80, 0x80, 0xF0, 0x20, 0x80, 0x20, 0x20, 0x80, 0x80,
        0x20, 0x20, 0xF0, 0xF0, 0x60, 0x80, 0x20, 0x80, 0xF0, 0xF0, 0x20, 0x80, 0x20, 0x20, 0x20,
        0xF0, 0xF0, 0x60, 0x60, 0x20, 0x60, 0x80, 0xF0, 0xF0, 0x20, 0x20, 0xF0, 0xF0, 0xF0, 0xF0,
        0xF0, 0x20, 0x20, 0xF0, 0x3F, 0x38, 0xF8, 0xF3, 0x8F, 0x3F, 0xF3, 0xF8, 0x8F, 0x8F, 0x6F,
        0x6F, 0x6F, 0x5F, 0x3F, 0x38, 0x3F, 0x38, 0x8F, 0xF3, 0x3F, 0x38, 0x6F, 0xA8, 0x53, 0x8F,
        0x86, 0x6A, 0x8F, 0x5F, 0xFA, 0xF8, 0x8F, 0xF3, 0x3F, 0x5A, 0x6A, 0xA8, 0x89, 0xFA, 0xF6,
        0x3F, 0xF8, 0x5F, 0xF3, 0xF6, 0xF6, 0xF8, 0x3F, 0xF3, 0x5F, 0x5F, 0x5F, 0x8F, 0x5F, 0xAF,
        0x5F, 0xAF, 0x8F, 0xDF, 0xF3, 0xCF, 0x3F, 0x38,
    };

    const skip_packed = skip_table[@intCast(part_id)];

    return .{ 0, skip_packed >> 4, skip_packed & 15 };
}

pub fn getUnquantValue(bits: u32, index: i32) i32 {
    switch (bits) {
        2 => {
            const table = [_]i32{ 0, 21, 43, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
            return table[@intCast(index)];
        },
        3 => {
            const table = [_]i32{ 0, 9, 18, 27, 37, 46, 55, 64, 0, 0, 0, 0, 0, 0, 0, 0 };
            return table[@intCast(index)];
        },
        else => {
            const table = [_]i32{ 0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64 };
            return table[@intCast(index)];
        },
    }
}

pub fn partialSortList(list: []i32, length: usize, partial_count: u32) void {
    for (0..partial_count) |k| {
        var best_idx: usize = k;
        var best_value: i32 = list[k];
        for (k + 1..length) |i| {
            if (best_value > list[i]) {
                best_value = list[i];
                best_idx = i;
            }
        }

        std.mem.swap(i32, &list[k], &list[best_idx]);
    }
}

pub fn putBits(data: *[5]u32, pos: *u32, bits: u32, v: u32) void {
    const shift_safe: u5 = @intCast(pos.* % 32);
    data[@intCast(pos.* / 32)] |= v << shift_safe;
    if (pos.* % 32 + bits > 32) {
        const shift_safe_2: u5 = @intCast(32 - pos.* % 32);
        data[(@intCast(pos.* / 32 + 1))] |= v >> shift_safe_2;
    }
    pos.* += bits;
}
