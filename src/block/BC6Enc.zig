// Portions of this file are based on bcdec and block_compression.
// See THIRD_PARTY_LICENSES.md in this project for more information.

const std = @import("std");

const common = @import("bc67_common.zig");

const BC6Block = @import("bc6.zig").BC6Block;
const BC6Enc = @This();

pub const Settings = struct {
    slow_mode: u32,
    fast_mode: u32,
    fast_skip_threshold: u32,
    refine_iterations_1p: u32,
    refine_iterations_2p: u32,

    pub const default = very_slow;

    pub const very_slow = Settings{
        .slow_mode = 1,
        .fast_mode = 0,
        .fast_skip_threshold = 32,
        .refine_iterations_1p = 2,
        .refine_iterations_2p = 2,
    };
};

settings: Settings,
block: [64]f32,
data: [5]u32,
best_err: f32,

rgb_bounds: [6]f32,
max_span: f32,
max_span_idx: usize,

mode: usize,
epb: u32,
qbounds: [8]i32,

pub fn createEncoder(raw_texels: [BC6Block.texel_count]BC6Block.TexelFormat, options: Settings) BC6Enc {
    var encoder = BC6Enc{
        .settings = options,
        .block = undefined,
        .data = @splat(0),
        .best_err = std.math.inf(f32),
        .rgb_bounds = @splat(0.0),
        .max_span = 0.0,
        .max_span_idx = 0,
        .mode = 0,
        .epb = 0,
        .qbounds = @splat(0),
    };

    for (0..BC6Block.texel_height) |y| {
        for (0..BC6Block.texel_width) |x| {
            const texel_idx = y * BC6Block.texel_width + x;
            const texel = raw_texels[texel_idx];

            const r: u16 = @bitCast(texel.r);
            const g: u16 = @bitCast(texel.g);
            const b: u16 = @bitCast(texel.b);
            const a: u16 = @bitCast(texel.a);

            encoder.block[y * 4 + x] = @floatFromInt(r);
            encoder.block[16 + y * 4 + x] = @floatFromInt(g);
            encoder.block[32 + y * 4 + x] = @floatFromInt(b);
            encoder.block[48 + y * 4 + x] = @floatFromInt(a);
        }
    }

    return encoder;
}

pub fn setupEncoder(encoder: *BC6Enc) void {
    for (0..3) |p| {
        encoder.rgb_bounds[p] = std.math.floatMax(f32);
        encoder.rgb_bounds[p + 3] = 0.0;
    }

    // Find min/max bounds
    for (0..3) |p| {
        for (0..16) |k| {
            const value = (encoder.block[p * 16 + k] / 31.0) * 64.0;
            encoder.block[p * 16 + k] = value;
            encoder.rgb_bounds[p] = @min(encoder.rgb_bounds[p], value);
            encoder.rgb_bounds[3 + p] = @max(encoder.rgb_bounds[3 + p], value);
        }
    }

    for (0..3) |p| {
        const span = encoder.rgb_bounds[3 + p] - encoder.rgb_bounds[p];
        if (span > encoder.max_span) {
            encoder.max_span = span;
            encoder.max_span_idx = p;
        }
    }
}

pub fn getBestBlock(encoder: *BC6Enc) BC6Block {
    var best_block = BC6Block{
        .data = undefined,
    };

    for (0..4) |i| {
        const value = encoder.data[i];
        const offset = i * 4;
        best_block.data[offset] = @truncate(value);
        best_block.data[offset + 1] = @truncate(value >> 8);
        best_block.data[offset + 2] = @truncate(value >> 16);
        best_block.data[offset + 3] = @truncate(value >> 24);
    }

    return best_block;
}

pub fn compressBlock(encoder: *BC6Enc) void {
    if (encoder.settings.slow_mode != 0) {
        encoder.testMode(0, true, 0.0);
        encoder.testMode(1, true, 0.0);
        encoder.testMode(2, true, 0.0);
        encoder.testMode(3, true, 0.0);
        encoder.testMode(4, true, 0.0);
        encoder.testMode(5, true, 0.0);
        encoder.testMode(6, true, 0.0);
        encoder.testMode(7, true, 0.0);
        encoder.testMode(8, true, 0.0);
        encoder.testMode(9, true, 0.0);
        encoder.testMode(10, true, 0.0);
        encoder.testMode(11, true, 0.0);
        encoder.testMode(12, true, 0.0);
        encoder.testMode(13, true, 0.0);
    } else {
        if (encoder.settings.fast_skip_threshold > 0) {
            encoder.testMode(9, false, 0.0);

            if (encoder.settings.fast_mode != 0) {
                encoder.testMode(1, false, 1.0);
            }

            encoder.testMode(6, false, 1.0 / 1.2);
            encoder.testMode(5, false, 1.0 / 1.2);
            encoder.testMode(0, false, 1.0 / 1.2);
            encoder.testMode(2, false, 1.0);
            encoder.enc2p();

            if (encoder.settings.fast_mode == 0) {
                encoder.testMode(1, true, 0.0);
            }
        }

        encoder.testMode(10, false, 0.0);
        encoder.testMode(11, false, 1.0);
        encoder.testMode(12, false, 1.0);
        encoder.testMode(13, false, 1.0);
        encoder.enc1p();
    }
}

fn testMode(encoder: *BC6Enc, mode: usize, enc: bool, margin: f32) void {
    const mode_bits = getModeBits(mode);
    const mode_span = getModeSpan(mode);
    const max_span = encoder.max_span;
    const max_span_idx = encoder.max_span_idx;

    if (max_span * margin > mode_span) {
        return;
    }

    if (mode >= 10) {
        encoder.epb = mode_bits;
        encoder.mode = mode;
        encoder.computeQBounds(mode_span);
        if (enc) {
            encoder.enc1p();
        }
    } else if (mode <= 1 or mode == 5 or mode == 9) {
        encoder.epb = mode_bits;
        encoder.mode = mode;
        encoder.computeQBounds(mode_span);
        if (enc) {
            encoder.enc2p();
        }
    } else {
        encoder.epb = mode_bits;
        encoder.mode = mode + max_span_idx;
        encoder.computeQBounds2(mode_span, max_span_idx);
        if (enc) {
            encoder.enc2p();
        }
    }
}

fn enc1p(encoder: *BC6Enc) void {
    var ep: [24]f32 = @splat(0.0);

    common.blockSegmentCore(&ep, &encoder.block, 0xFFFFFFFF, 3);

    var qep: [24]i32 = @splat(0);
    encoder.epQuantDequantBC6(&qep, &ep, 1);

    var qblock: [2]u32 = @splat(0);
    var err = common.blockQuant(&qblock, &encoder.block, 4, &ep, 0, 3);

    const refine_iterations = encoder.settings.refine_iterations_1p;
    for (0..refine_iterations) |_| {
        common.optEndpoints(&ep, &encoder.block, 4, &qblock, 0xFFFFFFFF, 3);
        encoder.epQuantDequantBC6(&qep, &ep, 1);
        err = common.blockQuant(&qblock, &encoder.block, 4, &ep, 0, 3);
    }

    if (err < encoder.best_err) {
        encoder.best_err = err;
        encoder.encCode1p(&qep, &qblock, encoder.mode);
    }
}

fn encCode1p(encoder: *BC6Enc, qep: *[24]i32, qblock: *[2]u32, mode: usize) void {
    common.bc7CodeApplySwapMode456(qep, 4, qblock, 4);

    encoder.data = @splat(0);
    var pos: u32 = 0;

    var packed_data: [4]u32 = @splat(0);
    bc6Pack(&packed_data, qep, mode);

    // Mode
    common.putBits(&encoder.data, &pos, 5, packed_data[0]);

    // Endpoints
    common.putBits(&encoder.data, &pos, 30, packed_data[1]);
    common.putBits(&encoder.data, &pos, 30, packed_data[2]);

    // Quantized values
    common.bc7CodeQBlock(&encoder.data, &pos, qblock, 4, 0);
}

fn enc2p(encoder: *BC6Enc) void {
    var full_stats: [15]f32 = @splat(0.0);
    common.computeStatsMasked(&full_stats, &encoder.block, 0xFFFFFFFF, 3);

    var part_list: [32]i32 = @splat(0);
    for (0..32) |part| {
        const mask = common.getPatternMask(@intCast(part), 0);
        const bound12 = common.blockPcaBoundSplit(&encoder.block, mask, &full_stats, 3);
        const bound: i32 = @intFromFloat(bound12);
        part_list[part] = @as(i32, @intCast(part)) + bound * 64;
    }

    common.partialSortList(&part_list, 32, encoder.settings.fast_skip_threshold);
    encoder.enc2pList(&part_list, encoder.settings.fast_skip_threshold);
}

fn enc2pList(encoder: *BC6Enc, part_list: *[32]i32, part_count: u32) void {
    if (part_count == 0) {
        return;
    }

    const bits: u32 = 3;
    const pairs: u32 = 2;
    const channels: u32 = 3;

    var best_qep: [24]i32 = @splat(0);
    var best_qblock: [2]u32 = @splat(0);
    var best_part_id: i32 = -1;
    var best_err: f32 = std.math.inf(f32);

    for (0..part_count) |part| {
        const part_id: i32 = part_list[part] & 31;

        var qep: [24]i32 = @splat(0);
        var qblock: [2]u32 = @splat(0);

        const err = encoder.enc2pPartFast(&qep, &qblock, part_id);

        if (err < best_err) {
            @memcpy(best_qep[0..(8 * pairs)], qep[0..(8 * pairs)]);
            @memcpy(&best_qblock, &qblock);
            best_part_id = part_id;
            best_err = err;
        }
    }

    for (0..encoder.settings.refine_iterations_2p) |_| {
        var ep: [24]f32 = @splat(0.0);

        for (0..pairs) |j| {
            const mask = common.getPatternMask(best_part_id, @intCast(j));

            common.optEndpoints(ep[j * 8 ..], &encoder.block, bits, &best_qblock, mask, channels);

            var qep: [24]i32 = @splat(0);
            var qblock: [2]u32 = @splat(0);

            encoder.epQuantDequantBC6(&qep, &ep, pairs);

            const pattern = common.getPattern(best_part_id);
            const err = common.blockQuant(&qblock, &encoder.block, bits, &ep, pattern, channels);

            if (err < best_err) {
                @memcpy(best_qep[0..(8 * pairs)], qep[0..(8 * pairs)]);
                @memcpy(&best_qblock, &qblock);
                best_err = err;
            }
        }
    }

    if (best_err < encoder.best_err) {
        encoder.best_err = best_err;
        encoder.encCode2p(&best_qep, &best_qblock, best_part_id, encoder.mode);
    }
}

fn encCode2p(encoder: *BC6Enc, qep: *[24]i32, qblock: *[2]u32, part_id: i32, mode: usize) void {
    const bits: u32 = 3;

    const flips = common.bc7CodeApplySwapMode01237(qep, qblock, 1, part_id);

    encoder.data = @splat(0);
    var pos: u32 = 0;

    var packed_data: [4]u32 = @splat(0);
    bc6Pack(&packed_data, qep, mode);

    // Mode
    common.putBits(&encoder.data, &pos, 5, packed_data[0]);

    // Endpoints
    common.putBits(&encoder.data, &pos, 30, packed_data[1]);
    common.putBits(&encoder.data, &pos, 30, packed_data[2]);
    common.putBits(&encoder.data, &pos, 12, packed_data[3]);

    // Partition
    common.putBits(&encoder.data, &pos, 5, @intCast(part_id));

    // Quantized values
    common.bc7CodeQBlock(&encoder.data, &pos, qblock, bits, flips);
    common.bc7CodeAdjustSkipMode01237(&encoder.data, 1, part_id);
}

fn enc2pPartFast(encoder: *BC6Enc, qep: *[24]i32, qblock: *[2]u32, part_id: i32) f32 {
    const pattern = common.getPattern(part_id);

    const bits: u32 = 3;
    const pairs: u32 = 2;
    const channels: u32 = 3;

    var ep: [24]f32 = @splat(0.0);
    for (0..pairs) |j| {
        const mask = common.getPatternMask(part_id, @intCast(j));
        common.blockSegmentCore(ep[j * 8 ..], &encoder.block, mask, channels);
    }

    encoder.epQuantDequantBC6(qep, &ep, pairs);

    return common.blockQuant(qblock, &encoder.block, bits, &ep, pattern, channels);
}

fn computeQBounds(encoder: *BC6Enc, span: f32) void {
    encoder.computeQBoundsCore(@splat(span));
}

fn computeQBounds2(encoder: *BC6Enc, span: f32, max_span_idx: usize) void {
    var rgb_span: [3]f32 = @splat(span);
    if (max_span_idx < 3) {
        rgb_span[max_span_idx] *= 2.0;
    }

    encoder.computeQBoundsCore(rgb_span);
}

fn computeQBoundsCore(encoder: *BC6Enc, rgb_span: [3]f32) void {
    var bounds: [8]f32 = @splat(0.0);

    for (0..3) |p| {
        const middle = (encoder.rgb_bounds[p] + encoder.rgb_bounds[3 + p]) / 2.0;
        bounds[p] = middle - rgb_span[p] / 2.0;
        bounds[4 + p] = middle + rgb_span[p] / 2.0;
    }

    encoder.epQuantBC6H8(&bounds, encoder.epb, 1);
}

fn epQuantBC6(qep: *[24]i32, ep: *[24]f32, bits: u32, pairs: u32) void {
    const safe_bits: u5 = @intCast(bits);
    const levels = @as(i32, 1) << safe_bits;

    const flevels = @as(f32, @floatFromInt(levels - 1));

    for (0..8 * pairs) |i| {
        const vf = ep[i] / (256.0 * 256.0 - 1.0) * flevels + 0.5;
        const vi: i32 = @intFromFloat(vf);
        qep[i] = std.math.clamp(vi, 0, levels - 1);
    }
}

fn epDequantBC6(ep: *[24]f32, qep: *[24]i32, bits: u32, pairs: u32) void {
    for (0..8 * pairs) |i| {
        ep[i] = @floatFromInt(unpackToUF16(@intCast(qep[i]), bits));
    }
}

fn epQuantDequantBC6(encoder: *BC6Enc, qep: *[24]i32, ep: *[24]f32, pairs: u32) void {
    const bits = encoder.epb;

    epQuantBC6(qep, ep, bits, pairs);

    for (0..2 * pairs) |i| {
        for (0..3) |p| {
            qep[i * 4 + p] = std.math.clamp(qep[i * 4 + p], encoder.qbounds[p], encoder.qbounds[4 + p]);
        }
    }

    epDequantBC6(ep, qep, bits, pairs);
}

fn epQuantBC6H8(encoder: *BC6Enc, ep: *[8]f32, bits: u32, pairs: u32) void {
    const safe_bits: u5 = @intCast(bits);
    const levels = @as(i32, 1) << safe_bits;

    const flevels = @as(f32, @floatFromInt(levels - 1));

    for (0..8 * pairs) |i| {
        const vf = ep[i] / (256.0 * 256.0 - 1.0) * flevels + 0.5;
        const vi: i32 = @intFromFloat(vf);
        encoder.qbounds[i] = std.math.clamp(vi, 0, levels - 1);
    }
}

fn bc6Pack(packed_data: *[4]u32, qep: *[24]i32, mode: usize) void {
    if (mode == 0) {
        var spred_qep: [16]i32 = @splat(0);
        for (0..3) |p| {
            spred_qep[p] = qep[p];
            spred_qep[4 + p] = (qep[4 + p] - qep[p]) & 31;
            spred_qep[8 + p] = (qep[8 + p] - qep[p]) & 31;
            spred_qep[12 + p] = (qep[12 + p] - qep[p]) & 31;
        }

        const pred_qep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(spred_qep[0..]));

        var pqep: [10]u32 = @splat(0);
        pqep[4] = pred_qep[4] + (pred_qep[8 + 1] & 15) * 64;
        pqep[5] = pred_qep[5] + (pred_qep[12 + 1] & 15) * 64;
        pqep[6] = pred_qep[6] + (pred_qep[8 + 2] & 15) * 64;

        pqep[4] += bitAt(pred_qep[12 + 1], 4) << 5;
        pqep[5] += bitAt(pred_qep[12 + 2], 0) << 5;
        pqep[6] += bitAt(pred_qep[12 + 2], 1) << 5;

        pqep[8] = pred_qep[8] + bitAt(pred_qep[12 + 2], 2) * 32;
        pqep[9] = pred_qep[12] + bitAt(pred_qep[12 + 2], 3) * 32;

        packed_data[0] = getModePrefix(0);
        packed_data[0] += bitAt(pred_qep[8 + 1], 4) << 2;
        packed_data[0] += bitAt(pred_qep[8 + 2], 4) << 3;
        packed_data[0] += bitAt(pred_qep[12 + 2], 4) << 4;

        packed_data[1] =
            ((pred_qep[2]) << 20) + ((pred_qep[1]) << 10) + pred_qep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
        packed_data[3] = (pqep[9] << 6) + pqep[8];
    } else if (mode == 1) {
        var spred_qep: [16]i32 = @splat(0);
        for (0..3) |p| {
            spred_qep[p] = qep[p];
            spred_qep[4 + p] = (qep[4 + p] - qep[p]) & 63;
            spred_qep[8 + p] = (qep[8 + p] - qep[p]) & 63;
            spred_qep[12 + p] = (qep[12 + p] - qep[p]) & 63;
        }

        const pred_qep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(spred_qep[0..]));
        var pqep: [10]u32 = @splat(0);

        pqep[0] = pred_qep[0];
        pqep[0] += bitAt(pred_qep[12 + 2], 0) << 7;
        pqep[0] += bitAt(pred_qep[12 + 2], 1) << 8;
        pqep[0] += bitAt(pred_qep[8 + 2], 4) << 9;

        pqep[1] = pred_qep[1];
        pqep[1] += bitAt(pred_qep[8 + 2], 5) << 7;
        pqep[1] += bitAt(pred_qep[12 + 2], 2) << 8;
        pqep[1] += bitAt(pred_qep[8 + 1], 4) << 9;

        pqep[2] = pred_qep[2];
        pqep[2] += bitAt(pred_qep[12 + 2], 3) << 7;
        pqep[2] += bitAt(pred_qep[12 + 2], 5) << 8;
        pqep[2] += bitAt(pred_qep[12 + 2], 4) << 9;

        pqep[4] = pred_qep[4] + ((pred_qep[8 + 1] & 15) * 64);
        pqep[5] = pred_qep[5] + ((pred_qep[12 + 1] & 15) * 64);
        pqep[6] = pred_qep[6] + ((pred_qep[8 + 2] & 15) * 64);

        packed_data[0] = getModePrefix(1);
        packed_data[0] += bitAt(pred_qep[8 + 1], 5) << 2;
        packed_data[0] += bitAt(pred_qep[12 + 1], 4) << 3;
        packed_data[0] += bitAt(pred_qep[12 + 1], 5) << 4;

        packed_data[1] = (pqep[2] << 20) + (pqep[1] << 10) + pqep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
        packed_data[3] = ((pred_qep[12]) << 6) + pred_qep[8];
    } else if (mode == 2 or mode == 3 or mode == 4) {
        var sdqep: [16]i32 = @splat(0);
        for (0..3) |p| {
            const mask: i32 = if (p == mode - 2) 31 else 15;
            sdqep[p] = qep[p];
            sdqep[4 + p] = (qep[4 + p] - qep[p]) & mask;
            sdqep[8 + p] = (qep[8 + p] - qep[p]) & mask;
            sdqep[12 + p] = (qep[12 + p] - qep[p]) & mask;
        }

        const dqep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(sdqep[0..]));

        var pqep: [10]u32 = @splat(0);

        pqep[0] = (dqep[0] & 1023);
        pqep[1] = (dqep[1] & 1023);
        pqep[2] = (dqep[2] & 1023);

        pqep[4] = dqep[4] + ((dqep[8 + 1] & 15) * 64);
        pqep[5] = dqep[5] + ((dqep[12 + 1] & 15) * 64);
        pqep[6] = dqep[6] + ((dqep[8 + 2] & 15) * 64);

        pqep[8] = dqep[8];
        pqep[9] = dqep[12];

        if (mode == 2) {
            packed_data[0] = getModePrefix(2);
            pqep[5] += bitAt(dqep[1], 10) << 4;
            pqep[6] += bitAt(dqep[2], 10) << 4;

            pqep[4] += bitAt(dqep[0], 10) << 5;
            pqep[5] += bitAt(dqep[12 + 2], 0) << 5;
            pqep[6] += bitAt(dqep[12 + 2], 1) << 5;
            pqep[8] += bitAt(dqep[12 + 2], 2) << 5;
            pqep[9] += bitAt(dqep[12 + 2], 3) << 5;
        } else if (mode == 3) {
            packed_data[0] = getModePrefix(3);

            pqep[4] += bitAt(dqep[0], 10) << 4;
            pqep[6] += bitAt(dqep[2], 10) << 4;
            pqep[8] += bitAt(dqep[12 + 2], 0) << 4;
            pqep[9] += bitAt(dqep[8 + 1], 4) << 4;

            pqep[4] += bitAt(dqep[12 + 1], 4) << 5;
            pqep[5] += bitAt(dqep[1], 10) << 5;
            pqep[6] += bitAt(dqep[12 + 2], 1) << 5;
            pqep[8] += bitAt(dqep[12 + 2], 2) << 5;
            pqep[9] += bitAt(dqep[12 + 2], 3) << 5;
        } else if (mode == 4) {
            packed_data[0] = getModePrefix(4);

            pqep[4] += bitAt(dqep[0], 10) << 4;
            pqep[5] += bitAt(dqep[1], 10) << 4;
            pqep[8] += bitAt(dqep[12 + 2], 1) << 4;
            pqep[9] += bitAt(dqep[12 + 2], 4) << 4;

            pqep[4] += bitAt(dqep[8 + 2], 4) << 5;
            pqep[5] += bitAt(dqep[12 + 2], 0) << 5;
            pqep[6] += bitAt(dqep[2], 10) << 5;
            pqep[8] += bitAt(dqep[12 + 2], 2) << 5;
            pqep[9] += bitAt(dqep[12 + 2], 3) << 5;
        }

        packed_data[1] = (pqep[2] << 20) + (pqep[1] << 10) + pqep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
        packed_data[3] = (pqep[9] << 6) + pqep[8];
    } else if (mode == 5) {
        var sdqep: [16]i32 = @splat(0);
        for (0..3) |p| {
            sdqep[p] = qep[p];
            sdqep[4 + p] = (qep[4 + p] - qep[p]) & 31;
            sdqep[8 + p] = (qep[8 + p] - qep[p]) & 31;
            sdqep[12 + p] = (qep[12 + p] - qep[p]) & 31;
        }

        const dqep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(sdqep[0..]));

        var pqep: [10]u32 = @splat(0);

        pqep[0] = dqep[0];
        pqep[1] = dqep[1];
        pqep[2] = dqep[2];
        pqep[4] = dqep[4] + (dqep[8 + 1] & 15) * 64;
        pqep[5] = dqep[5] + (dqep[12 + 1] & 15) * 64;
        pqep[6] = dqep[6] + (dqep[8 + 2] & 15) * 64;
        pqep[8] = dqep[8];
        pqep[9] = dqep[12];

        pqep[0] += bitAt(dqep[8 + 2], 4) << 9;
        pqep[1] += bitAt(dqep[8 + 1], 4) << 9;
        pqep[2] += bitAt(dqep[12 + 2], 4) << 9;

        pqep[4] += bitAt(dqep[12 + 1], 4) << 5;
        pqep[5] += bitAt(dqep[12 + 2], 0) << 5;
        pqep[6] += bitAt(dqep[12 + 2], 1) << 5;

        pqep[8] += bitAt(dqep[12 + 2], 2) << 5;
        pqep[9] += bitAt(dqep[12 + 2], 3) << 5;

        packed_data[0] = getModePrefix(5);

        packed_data[1] = (pqep[2] << 20) + (pqep[1] << 10) + pqep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
        packed_data[3] = (pqep[9] << 6) + pqep[8];
    } else if (mode == 6 or mode == 7 or mode == 8) {
        var sdqep: [16]i32 = @splat(0);
        for (0..3) |p| {
            const mask: i32 = if (p == mode - 6) 63 else 31;
            sdqep[p] = qep[p];
            sdqep[4 + p] = (qep[4 + p] - qep[p]) & mask;
            sdqep[8 + p] = (qep[8 + p] - qep[p]) & mask;
            sdqep[12 + p] = (qep[12 + p] - qep[p]) & mask;
        }

        const dqep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(sdqep[0..]));

        var pqep: [10]u32 = @splat(0);

        pqep[0] = dqep[0];
        pqep[0] += bitAt(dqep[8 + 2], 4) << 9;

        pqep[1] = dqep[1];
        pqep[1] += bitAt(dqep[8 + 1], 4) << 9;

        pqep[2] = dqep[2];
        pqep[2] += bitAt(dqep[12 + 2], 4) << 9;

        pqep[4] = dqep[4] + (dqep[8 + 1] & 15) * 64;
        pqep[5] = dqep[5] + (dqep[12 + 1] & 15) * 64;
        pqep[6] = dqep[6] + (dqep[8 + 2] & 15) * 64;

        pqep[8] = dqep[8];
        pqep[9] = dqep[12];

        if (mode == 6) {
            packed_data[0] = getModePrefix(6);

            pqep[0] += bitAt(dqep[12 + 1], 4) << 8;
            pqep[1] += bitAt(dqep[12 + 2], 2) << 8;
            pqep[2] += bitAt(dqep[12 + 2], 3) << 8;
            pqep[5] += bitAt(dqep[12 + 2], 0) << 5;
            pqep[6] += bitAt(dqep[12 + 2], 1) << 5;
        } else if (mode == 7) {
            packed_data[0] = getModePrefix(7);

            pqep[0] += bitAt(dqep[12 + 2], 0) << 8;
            pqep[1] += bitAt(dqep[8 + 1], 5) << 8;
            pqep[2] += bitAt(dqep[12 + 1], 5) << 8;
            pqep[4] += bitAt(dqep[12 + 1], 4) << 5;
            pqep[6] += bitAt(dqep[12 + 2], 1) << 5;
            pqep[8] += bitAt(dqep[12 + 2], 2) << 5;
            pqep[9] += bitAt(dqep[12 + 2], 3) << 5;
        } else if (mode == 8) {
            packed_data[0] = getModePrefix(8);

            pqep[0] += bitAt(dqep[12 + 2], 1) << 8;
            pqep[1] += bitAt(dqep[8 + 2], 5) << 8;
            pqep[2] += bitAt(dqep[12 + 2], 5) << 8;
            pqep[4] += bitAt(dqep[12 + 1], 4) << 5;
            pqep[5] += bitAt(dqep[12 + 2], 0) << 5;
            pqep[8] += bitAt(dqep[12 + 2], 2) << 5;
            pqep[9] += bitAt(dqep[12 + 2], 3) << 5;
        }

        packed_data[1] = (pqep[2] << 20) + (pqep[1] << 10) + pqep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
        packed_data[3] = (pqep[9] << 6) + pqep[8];
    } else if (mode == 9) {
        const uqep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(qep[0..]));

        var pqep: [10]u32 = @splat(0);

        pqep[0] = uqep[0];
        pqep[0] += bitAt(uqep[12 + 1], 4) << 6;
        pqep[0] += bitAt(uqep[12 + 2], 0) << 7;
        pqep[0] += bitAt(uqep[12 + 2], 1) << 8;
        pqep[0] += bitAt(uqep[8 + 2], 4) << 9;

        pqep[1] = uqep[1];
        pqep[1] += bitAt(uqep[8 + 1], 5) << 6;
        pqep[1] += bitAt(uqep[8 + 2], 5) << 7;
        pqep[1] += bitAt(uqep[12 + 2], 2) << 8;
        pqep[1] += bitAt(uqep[8 + 1], 4) << 9;

        pqep[2] = uqep[2];
        pqep[2] += bitAt(uqep[12 + 1], 5) << 6;
        pqep[2] += bitAt(uqep[12 + 2], 3) << 7;
        pqep[2] += bitAt(uqep[12 + 2], 5) << 8;
        pqep[2] += bitAt(uqep[12 + 2], 4) << 9;

        pqep[4] = uqep[4] + (uqep[8 + 1] & 15) * 64;
        pqep[5] = uqep[5] + (uqep[12 + 1] & 15) * 64;
        pqep[6] = uqep[6] + (uqep[8 + 2] & 15) * 64;

        packed_data[0] = getModePrefix(9);
        packed_data[1] = (pqep[2] << 20) + (pqep[1] << 10) + pqep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
        packed_data[3] = (uqep[12] << 6) + uqep[8];
    } else if (mode == 10) {
        const uqep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(qep[0..]));
        packed_data[0] = getModePrefix(10);
        packed_data[1] = (uqep[2] << 20) + (uqep[1] << 10) + uqep[0];
        packed_data[2] = (uqep[6] << 20) + (uqep[5] << 10) + uqep[4];
    } else if (mode == 11) {
        var sdqep: [16]i32 = @splat(0);
        for (0..3) |p| {
            sdqep[p] = qep[p];
            sdqep[4 + p] = (qep[4 + p] - qep[p]) & 511;
        }

        const dqep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(sdqep[0..]));

        var pqep: [10]u32 = @splat(0);

        pqep[0] = (dqep[0] & 1023);
        pqep[1] = (dqep[1] & 1023);
        pqep[2] = (dqep[2] & 1023);

        pqep[4] = dqep[4] + (dqep[0] >> 10) * 512;
        pqep[5] = dqep[5] + (dqep[1] >> 10) * 512;
        pqep[6] = dqep[6] + (dqep[2] >> 10) * 512;

        packed_data[0] = getModePrefix(11);
        packed_data[1] = (pqep[2] << 20) + (pqep[1] << 10) + pqep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
    } else if (mode == 12) {
        var sdqep: [16]i32 = @splat(0);
        for (0..3) |p| {
            sdqep[p] = qep[p];
            sdqep[4 + p] = (qep[4 + p] - qep[p]) & 255;
        }

        const dqep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(sdqep[0..]));

        var pqep: [10]u32 = @splat(0);

        pqep[0] = (dqep[0] & 1023);
        pqep[1] = (dqep[1] & 1023);
        pqep[2] = (dqep[2] & 1023);

        pqep[4] = dqep[4] + reverseBits((dqep[0] >> 10), 2) * 256;
        pqep[5] = dqep[5] + reverseBits((dqep[1] >> 10), 2) * 256;
        pqep[6] = dqep[6] + reverseBits((dqep[2] >> 10), 2) * 256;

        packed_data[0] = getModePrefix(12);
        packed_data[1] = (pqep[2] << 20) + (pqep[1] << 10) + pqep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
    } else if (mode == 13) {
        var sdqep: [16]i32 = @splat(0);
        for (0..3) |p| {
            sdqep[p] = qep[p];
            sdqep[4 + p] = (qep[4 + p] - qep[p]) & 15;
        }

        const dqep = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(sdqep[0..]));

        var pqep: [10]u32 = @splat(0);

        pqep[0] = (dqep[0] & 1023);
        pqep[1] = (dqep[1] & 1023);
        pqep[2] = (dqep[2] & 1023);

        pqep[4] = dqep[4] + reverseBits((dqep[0] >> 10), 6) * 16;
        pqep[5] = dqep[5] + reverseBits((dqep[1] >> 10), 6) * 16;
        pqep[6] = dqep[6] + reverseBits((dqep[2] >> 10), 6) * 16;
        packed_data[0] = getModePrefix(13);
        packed_data[1] = (pqep[2] << 20) + (pqep[1] << 10) + pqep[0];
        packed_data[2] = (pqep[6] << 20) + (pqep[5] << 10) + pqep[4];
    }
}

fn unpackToUF16(v: u32, bits: u32) u32 {
    if (bits >= 15) {
        return v;
    }

    const safe_bits: u5 = @intCast(bits);

    if (v == 0) {
        return 0;
    }

    if (v == (@as(u32, 1) << safe_bits) - 1) {
        return 0xFFFF;
    }

    return (v * 2 + 1) << (15 - safe_bits);
}

fn getModeBits(mode: usize) u32 {
    const mode_bits_table = [_]u32{
        10, 7, 11, 0xFFFFFFFF, 0xFFFFFFFF, 9, 8, 0xFFFFFFFF, 0xFFFFFFFF, 6, 10, 11, 12, 16,
    };

    return mode_bits_table[mode];
}

fn getModeSpan(mode: usize) f32 {
    const mode_span_table = [_]f32{
        0.9 * 65535.0 / 64.0, // (0) 4 / 10
        0.9 * 65535.0 / 4.0, // (1) 5 / 7
        0.8 * 65535.0 / 256.0, // (2) 3 / 11
        -1.0,
        -1.0,
        0.9 * 65535.0 / 32.0, // (5) 4 / 9
        0.9 * 65535.0 / 16.0, // (6) 4 / 8
        -1.0,
        -1.0,
        65535.0, // (9) absolute
        65535.0, // (10) absolute
        0.95 * 65535.0 / 8.0, // (11) 8 / 11
        0.95 * 65535.0 / 32.0, // (12) 7 / 12
        6.0,
    };

    return mode_span_table[mode];
}

fn getModePrefix(mode: usize) u32 {
    const mode_prefix_table = [_]u32{ 0, 1, 2, 6, 10, 14, 18, 22, 26, 30, 3, 7, 11, 15 };
    return mode_prefix_table[mode];
}

fn bitAt(data: u32, index: u32) u32 {
    const safe_index: u5 = @intCast(index);
    return (data >> safe_index) & 1;
}

fn reverseBits(v: u32, bits: u32) u32 {
    if (bits == 2) {
        return (v >> 1) + (v & 1) * 2;
    }

    if (bits == 6) {
        const vv = (v & 0x5555) * 2 + ((v >> 1) & 0x5555);
        return (vv >> 4) + ((vv >> 2) & 3) * 4 + (vv & 3) * 16;
    }

    @panic("Unsupported bit count");
}
