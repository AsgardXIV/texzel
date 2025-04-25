// Portions of this file are based on bcdec and block_compression.
// See THIRD_PARTY_LICENSES.md in this project for more information.

const std = @import("std");

const common = @import("bc67_common.zig");

const BC7Block = @import("bc7.zig").BC7Block;
const BC7Enc = @This();

pub const Settings = struct {
    refine_iterations: [8]u32,
    mode_selection: [4]u32,
    skip_mode2: u32,
    fast_skip_threshold_mode1: u32,
    fast_skip_threshold_mode3: u32,
    fast_skip_threshold_mode7: u32,
    mode45_channel0: u32,
    refine_iterations_channel: u32,
    channels: u32,

    pub const default = alpha_basic;

    pub const opaque_fast = Settings{
        .channels = 3,
        .mode_selection = .{ 0, 1, 0, 1 },
        .skip_mode2 = 1,
        .fast_skip_threshold_mode1 = 12,
        .fast_skip_threshold_mode3 = 4,
        .fast_skip_threshold_mode7 = 0,
        .mode45_channel0 = 0,
        .refine_iterations_channel = 0,
        .refine_iterations = .{ 2, 2, 2, 1, 2, 2, 2, 0 },
    };

    pub const opaque_basic = Settings{
        .channels = 3,
        .mode_selection = .{ 1, 1, 1, 1 },
        .skip_mode2 = 1,
        .fast_skip_threshold_mode1 = 12,
        .fast_skip_threshold_mode3 = 8,
        .fast_skip_threshold_mode7 = 0,
        .mode45_channel0 = 0,
        .refine_iterations_channel = 2,
        .refine_iterations = .{ 2, 2, 2, 2, 2, 2, 2, 0 },
    };

    pub const opaque_slow = Settings{
        .channels = 3,
        .mode_selection = .{ 1, 1, 1, 1 },
        .skip_mode2 = 0,
        .fast_skip_threshold_mode1 = 64,
        .fast_skip_threshold_mode3 = 64,
        .fast_skip_threshold_mode7 = 0,
        .mode45_channel0 = 0,
        .refine_iterations_channel = 4,
        .refine_iterations = .{ 4, 4, 4, 4, 4, 4, 4, 0 },
    };

    pub const alpha_fast = Settings{
        .channels = 4,
        .mode_selection = .{ 0, 1, 1, 1 },
        .skip_mode2 = 1,
        .fast_skip_threshold_mode1 = 4,
        .fast_skip_threshold_mode3 = 4,
        .fast_skip_threshold_mode7 = 8,
        .mode45_channel0 = 3,
        .refine_iterations_channel = 2,
        .refine_iterations = .{ 2, 1, 2, 1, 2, 2, 2, 2 },
    };

    pub const alpha_basic = Settings{
        .channels = 4,
        .mode_selection = .{ 1, 1, 1, 1 },
        .skip_mode2 = 1,
        .fast_skip_threshold_mode1 = 18,
        .fast_skip_threshold_mode3 = 8,
        .fast_skip_threshold_mode7 = 8,
        .mode45_channel0 = 0,
        .refine_iterations_channel = 2,
        .refine_iterations = .{ 2, 2, 2, 2, 2, 2, 2, 2 },
    };

    pub const alpha_slow = Settings{
        .channels = 4,
        .mode_selection = .{ 1, 1, 1, 1 },
        .skip_mode2 = 0,
        .fast_skip_threshold_mode1 = 64,
        .fast_skip_threshold_mode3 = 64,
        .fast_skip_threshold_mode7 = 64,
        .mode45_channel0 = 0,
        .refine_iterations_channel = 4,
        .refine_iterations = .{ 4, 4, 4, 4, 4, 4, 4, 4 },
    };
};

settings: Settings,
block: [64]f32,
data: [5]u32,
opaque_err: f32,
best_err: f32,

pub fn createEncoder(raw_texels: [BC7Block.texel_count]BC7Block.TexelFormat, options: Settings) BC7Enc {
    var encoder = BC7Enc{
        .settings = options,
        .block = undefined,
        .opaque_err = 0.0,
        .best_err = std.math.inf(f32),
        .data = @splat(0),
    };

    for (0..BC7Block.texel_height) |y| {
        for (0..BC7Block.texel_width) |x| {
            const texel_idx = y * BC7Block.texel_width + x;
            const texel = raw_texels[texel_idx];
            encoder.block[y * 4 + x] = @floatFromInt(texel.r);
            encoder.block[16 + y * 4 + x] = @floatFromInt(texel.g);
            encoder.block[32 + y * 4 + x] = @floatFromInt(texel.b);
            encoder.block[48 + y * 4 + x] = @floatFromInt(texel.a);
        }
    }

    return encoder;
}

pub fn computeOpaqueError(encoder: *BC7Enc) void {
    if (encoder.settings.channels == 3) {
        encoder.opaque_err = 0.0;
    } else {
        var err: f32 = 0.0;
        for (0..16) |k| {
            const val = encoder.block[48 + k] - 255.0;
            err += val * val;
        }
        encoder.opaque_err = err;
    }
}

pub fn getBestBlock(encoder: *BC7Enc) BC7Block {
    var best_block = BC7Block{
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

pub fn compressBlock(encoder: *BC7Enc) void {
    if (encoder.settings.mode_selection[0] != 0) {
        encoder.encMode02();
    }

    if (encoder.settings.mode_selection[1] != 0) {
        encoder.encMode13();
        encoder.encMode7();
    }

    if (encoder.settings.mode_selection[2] != 0) {
        encoder.encMode45();
    }

    if (encoder.settings.mode_selection[3] != 0) {
        encoder.encMode6();
    }
}

fn encMode6(encoder: *BC7Enc) void {
    const mode: usize = 6;
    const bits: u32 = 4;

    var ep: [8]f32 = @splat(0.0);
    blockSegment(&ep, &encoder.block, 0xFFFFFFFF, encoder.settings.channels);

    if (encoder.settings.channels == 3) {
        ep[3] = 255.0;
        ep[7] = 255.0;
    }

    var qep: [8]i32 = @splat(0);
    eqQuantDequant(&qep, &ep, mode, encoder.settings.channels);

    var qblock: [2]u32 = @splat(0);
    var err = common.blockQuant(&qblock, &encoder.block, bits, &ep, 0, encoder.settings.channels);

    const refine_iterations = encoder.settings.refine_iterations[mode];
    for (0..refine_iterations) |_| {
        common.optEndpoints(&ep, &encoder.block, bits, &qblock, 0xFFFFFFFF, encoder.settings.channels);
        eqQuantDequant(&qep, &ep, mode, encoder.settings.channels);
        err = common.blockQuant(&qblock, &encoder.block, bits, &ep, 0, encoder.settings.channels);
    }

    if (err < encoder.best_err) {
        encoder.best_err = err;
        encoder.encCodeMode6(&qep, &qblock);
    }
}

fn encCodeMode6(encoder: *BC7Enc, qep: *[8]i32, qblock: *[2]u32) void {
    common.bc7CodeApplySwapMode456(qep, 4, qblock, 4);

    encoder.data = @splat(0);
    var pos: u32 = 0;

    // Mode 6
    common.putBits(&encoder.data, &pos, 7, 64);

    // Endpoints
    for (0..4) |p| {
        common.putBits(&encoder.data, &pos, 7, @intCast(qep[p] >> 1));
        common.putBits(&encoder.data, &pos, 7, @intCast(qep[4 + p] >> 1));
    }

    // P bits
    common.putBits(&encoder.data, &pos, 1, @intCast(qep[0] & 1));
    common.putBits(&encoder.data, &pos, 1, @intCast(qep[4] & 1));

    // Quantized values
    common.bc7CodeQBlock(&encoder.data, &pos, qblock, 4, 0);
}

fn encMode45(encoder: *BC7Enc) void {
    var best_candidate: Mode45Parameters = .{};
    var best_err = encoder.best_err;

    const channel0 = encoder.settings.mode45_channel0;

    // Mode 4
    for (channel0..encoder.settings.channels) |p| {
        const rot: u32 = @intCast(p);
        encoder.encMode45Candidate(&best_candidate, &best_err, 4, rot, 0);
        encoder.encMode45Candidate(&best_candidate, &best_err, 4, rot, 1);
    }

    if (best_err < encoder.best_err) {
        encoder.best_err = best_err;
        encoder.encCodeMode45(&best_candidate, 4);
    }

    // Mode 5
    for (channel0..encoder.settings.channels) |p| {
        encoder.encMode45Candidate(&best_candidate, &best_err, 5, @intCast(p), 0);
    }

    if (best_err < encoder.best_err) {
        encoder.best_err = best_err;
        encoder.encCodeMode45(&best_candidate, 5);
    }
}

fn encMode45Candidate(encoder: *BC7Enc, best_candidate: *Mode45Parameters, best_err: *f32, mode: usize, rotation: u32, swap: u32) void {
    // Mode 5 defaults
    var bits: u32 = 2;
    var abits: u32 = 2;
    var aepbits: u32 = 8;

    // Mode 4 overrides
    if (mode == 4) {
        aepbits = 6;

        if (swap == 1) {
            bits = 3;
            abits = 2;
        } else {
            abits = 3;
        }
    } else {
        std.debug.assert(swap == 0);
    }

    var candidate_block: [64]f32 = @splat(0.0);

    for (0..16) |k| {
        for (0..3) |p| {
            candidate_block[k + p * 16] = encoder.block[k + p * 16];
        }

        if (rotation < 3) {
            // Apply channel rotation
            if (encoder.settings.channels == 4) {
                candidate_block[k + rotation * 16] = encoder.block[k + 3 * 16];
            }

            if (encoder.settings.channels == 3) {
                candidate_block[k + rotation * 16] = 255.0;
            }
        }
    }

    var ep: [8]f32 = @splat(0.0);
    blockSegment(&ep, &candidate_block, 0xFFFFFFFF, 3);

    var qep: [8]i32 = @splat(0);
    eqQuantDequant(&qep, &ep, mode, 3);

    var qblock: [2]u32 = @splat(0);
    var err = common.blockQuant(&qblock, &candidate_block, bits, &ep, 0, 3);

    // Refine
    const refine_iterations = encoder.settings.refine_iterations[mode];
    for (0..refine_iterations) |_| {
        common.optEndpoints(&ep, &candidate_block, bits, &qblock, 0xFFFFFFFF, 3);
        eqQuantDequant(&qep, &ep, mode, 3);
        err = common.blockQuant(&qblock, &candidate_block, bits, &ep, 0, 3);
    }

    var channel_data: [16]f32 = undefined;
    for (0..16) |k| {
        channel_data[k] = encoder.block[k + rotation * 16];
    }

    // Encoding selected channel
    var aqep: [2]i32 = @splat(0);
    var aqblock: [2]u32 = @splat(0);

    err += encoder.optChannel(&aqblock, &aqep, &channel_data, abits, aepbits);

    if (err < best_err.*) {
        @memcpy(&best_candidate.qep, qep[0..8]);
        @memcpy(&best_candidate.qblock, &qblock);
        @memcpy(&best_candidate.aqblock, &aqblock);
        @memcpy(&best_candidate.aqep, &aqep);
        best_candidate.rotation = rotation;
        best_candidate.swap = swap;
        best_err.* = err;
    }
}

fn encCodeMode45(encoder: *BC7Enc, params: *Mode45Parameters, mode: usize) void {
    var qep = params.qep;
    var qblock = params.qblock;
    var aqep = params.aqep;
    var aqblock = params.aqblock;
    const rotation = params.rotation;
    const swap = params.swap;

    const bits: u32 = 2;
    const abits: u32 = if (mode == 4) 3 else 2;
    const epbits: u32 = if (mode == 4) 5 else 7;
    const aepbits: u32 = if (mode == 4) 6 else 8;

    if (swap == 0) {
        common.bc7CodeApplySwapMode456(&qep, 4, &qblock, bits);
        common.bc7CodeApplySwapMode456(&aqep, 1, &aqblock, abits);
    } else {
        std.mem.swap([2]u32, &qblock, &aqblock);

        common.bc7CodeApplySwapMode456(&aqep, 1, &qblock, bits);
        common.bc7CodeApplySwapMode456(&qep, 4, &aqblock, abits);
    }

    encoder.data = @splat(0);
    var pos: u32 = 0;

    // Mode 4-5
    const safe_mode: u5 = @intCast(mode);
    common.putBits(&encoder.data, &pos, @intCast(mode + 1), @as(u32, 1) << safe_mode);

    // Rotation
    common.putBits(&encoder.data, &pos, 2, (rotation + 1) & 3);

    if (mode == 4) {
        common.putBits(&encoder.data, &pos, 1, swap);
    }

    // Endpoints
    for (0..3) |p| {
        common.putBits(&encoder.data, &pos, epbits, @intCast(qep[p]));
        common.putBits(&encoder.data, &pos, epbits, @intCast(qep[4 + p]));
    }

    // Alpha endpoints
    common.putBits(&encoder.data, &pos, aepbits, @intCast(aqep[0]));
    common.putBits(&encoder.data, &pos, aepbits, @intCast(aqep[1]));

    // Quantized values
    common.bc7CodeQBlock(&encoder.data, &pos, &qblock, bits, 0);
    common.bc7CodeQBlock(&encoder.data, &pos, &aqblock, abits, 0);
}

fn encMode02(encoder: *BC7Enc) void {
    var part_list: [64]i32 = undefined;
    inline for (&part_list, 0..) |*item, i| {
        item.* = @intCast(i);
    }

    encoder.encMode01237(0, &part_list, 16);

    if (encoder.settings.skip_mode2 == 0) {
        encoder.encMode01237(2, &part_list, 64);
    }
}

fn encMode13(encoder: *BC7Enc) void {
    if (encoder.settings.fast_skip_threshold_mode1 == 0 and encoder.settings.fast_skip_threshold_mode3 == 0) return;

    var full_stats: [15]f32 = @splat(0.0);
    common.computeStatsMasked(&full_stats, &encoder.block, 0xFFFFFFFF, 3);

    var part_list: [64]i32 = @splat(0);

    for (0..64) |i| {
        const part: i32 = @intCast(i);
        const mask = common.getPatternMask(part, 0);
        const bound12 = common.blockPcaBoundSplit(&encoder.block, mask, &full_stats, 3);
        const bound: i32 = @intFromFloat(bound12);
        part_list[i] = part + bound * 64;
    }

    const partial_count: u32 = @max(encoder.settings.fast_skip_threshold_mode1, encoder.settings.fast_skip_threshold_mode3);
    common.partialSortList(&part_list, 64, partial_count);

    encoder.encMode01237(1, &part_list, encoder.settings.fast_skip_threshold_mode1);

    encoder.encMode01237(3, &part_list, encoder.settings.fast_skip_threshold_mode3);
}

fn encMode7(encoder: *BC7Enc) void {
    if (encoder.settings.fast_skip_threshold_mode7 == 0) return;

    var full_stats: [15]f32 = @splat(0.0);
    common.computeStatsMasked(&full_stats, &encoder.block, 0xFFFFFFFF, encoder.settings.channels);

    var part_list: [64]i32 = @splat(0);

    for (0..64) |i| {
        const part: i32 = @intCast(i);
        const mask = common.getPatternMask(part, 0);
        const bound12 = common.blockPcaBoundSplit(&encoder.block, mask, &full_stats, encoder.settings.channels);
        const bound: i32 = @intFromFloat(bound12);
        part_list[i] = part + bound * 64;
    }

    common.partialSortList(&part_list, 64, encoder.settings.fast_skip_threshold_mode7);

    encoder.encMode01237(7, &part_list, encoder.settings.fast_skip_threshold_mode7);
}

fn encMode01237(
    encoder: *BC7Enc,
    mode: usize,
    part_list: *[64]i32,
    part_count: usize,
) void {
    if (part_count == 0) {
        return;
    }

    const bits: u32 = if (mode == 0 or mode == 1) 3 else 2;
    const pairs: usize = if (mode == 0 or mode == 2) 3 else 2;
    const channels: u32 = if (mode == 7) 4 else 3;

    var best_qep: [24]i32 = @splat(0);
    var best_qblock: [2]u32 = @splat(0);
    var best_part_id: i32 = -1;
    var best_err = std.math.inf(f32);

    for (part_list[0..part_count]) |part| {
        var part_id = part & 63;
        part_id = if (pairs == 3) part_id + 64 else part_id;

        var qep: [24]i32 = @splat(0);
        var qblock: [2]u32 = @splat(0);
        const err = encoder.encMode01237PartFast(&qep, &qblock, part_id, mode);

        if (err < best_err) {
            @memcpy(best_qep[0..(8 * pairs)], qep[0..(8 * pairs)]);
            @memcpy(&best_qblock, &qblock);

            best_part_id = part_id;
            best_err = err;
        }
    }

    const refine_iterations = encoder.settings.refine_iterations[mode];
    for (0..refine_iterations) |_| {
        var ep: [24]f32 = @splat(0.0);
        for (0..pairs) |j| {
            const mask = common.getPatternMask(best_part_id, @intCast(j));
            common.optEndpoints(
                ep[j * 8 ..],
                &encoder.block,
                bits,
                &best_qblock,
                mask,
                channels,
            );
        }

        var qep: [24]i32 = @splat(0);
        var qblock: [2]u32 = @splat(0);

        eqQuantDequant(&qep, &ep, mode, channels);

        const pattern = common.getPattern(best_part_id);
        const err = common.blockQuant(
            &qblock,
            &encoder.block,
            bits,
            &ep,
            pattern,
            channels,
        );

        if (err < best_err) {
            @memcpy(best_qep[0..(8 * pairs)], qep[0..(8 * pairs)]);
            @memcpy(&best_qblock, &qblock);

            best_err = err;
        }
    }

    if (mode != 7) {
        best_err += encoder.opaque_err;
    }

    if (best_err < encoder.best_err) {
        encoder.best_err = best_err;
        encoder.encCode01237(
            &best_qep,
            &best_qblock,
            best_part_id,
            mode,
        );
    }
}

fn encCode01237(
    encoder: *BC7Enc,
    qep: *[24]i32,
    qblock: *[2]u32,
    part_id: i32,
    mode: usize,
) void {
    const bits: u32 = if (mode == 0 or mode == 1) 3 else 2;
    const pairs: usize = if (mode == 0 or mode == 2) 3 else 2;
    const channels: u32 = if (mode == 7) 4 else 3;

    const flips = common.bc7CodeApplySwapMode01237(qep, qblock, mode, part_id);

    encoder.data = @splat(0);
    var pos: u32 = 0;

    // Mode 0-3, 7
    const safe_mode: u5 = @intCast(mode);
    common.putBits(&encoder.data, &pos, (safe_mode + 1), @as(u32, 1) << safe_mode);

    // Partition
    if (mode == 0) {
        common.putBits(&encoder.data, &pos, 4, @intCast(part_id & 15));
    } else {
        common.putBits(&encoder.data, &pos, 6, @intCast(part_id & 63));
    }

    // Endpoints
    for (0..channels) |p| {
        for (0..pairs * 2) |j| {
            if (mode == 0) {
                common.putBits(&encoder.data, &pos, 4, @intCast(qep[j * 4 + p] >> 1));
            } else if (mode == 1) {
                common.putBits(&encoder.data, &pos, 6, @intCast(qep[j * 4 + p] >> 1));
            } else if (mode == 2) {
                common.putBits(&encoder.data, &pos, 5, @intCast(qep[j * 4 + p]));
            } else if (mode == 3) {
                common.putBits(&encoder.data, &pos, 7, @intCast(qep[j * 4 + p] >> 1));
            } else if (mode == 7) {
                common.putBits(&encoder.data, &pos, 5, @intCast(qep[j * 4 + p] >> 1));
            }
        }
    }

    // P bits
    if (mode == 1) {
        for (0..2) |j| {
            common.putBits(&encoder.data, &pos, 1, @intCast(qep[j * 8] & 1));
        }
    }

    if (mode == 0 or mode == 3 or mode == 7) {
        for (0..pairs * 2) |j| {
            common.putBits(&encoder.data, &pos, 1, @intCast(qep[j * 4] & 1));
        }
    }

    // Quantized values
    common.bc7CodeQBlock(&encoder.data, &pos, qblock, bits, flips);
    common.bc7CodeAdjustSkipMode01237(&encoder.data, mode, part_id);
}

fn encMode01237PartFast(
    encoder: *BC7Enc,
    qep: *[24]i32,
    qblock: *[2]u32,
    part_id: i32,
    mode: usize,
) f32 {
    const pattern = common.getPattern(part_id);
    const bits: u32 = if (mode == 0 or mode == 1) 3 else 2;
    const pairs: usize = if (mode == 0 or mode == 2) 3 else 2;
    const channels: u32 = if (mode == 7) 4 else 3;

    var ep: [24]f32 = @splat(0.0);
    for (0..pairs) |j| {
        const mask = common.getPatternMask(part_id, @intCast(j));
        blockSegment(ep[j * 8 ..], &encoder.block, mask, channels);
    }

    eqQuantDequant(qep, &ep, mode, channels);

    return common.blockQuant(qblock, &encoder.block, bits, &ep, pattern, channels);
}

fn optChannel(encoder: *BC7Enc, qblock: *[2]u32, qep: *[2]i32, channel_block: *[16]f32, bits: u32, epbits: u32) f32 {
    var ep = [_]f32{ 255.0, 0.0 };

    for (0..16) |k| {
        ep[0] = @min(ep[0], channel_block[k]);
        ep[1] = @max(ep[1], channel_block[k]);
    }

    channelQuantDequant(qep, &ep, epbits);

    var err = channelOptQuant(qblock, channel_block, bits, &ep);

    const refine_iterations = encoder.settings.refine_iterations_channel;
    for (0..refine_iterations) |_| {
        channelOptEndpoints(&ep, channel_block, bits, qblock);
        channelQuantDequant(qep, &ep, epbits);
        err = channelOptQuant(qblock, channel_block, bits, &ep);
    }

    return err;
}

fn channelQuantDequant(qep: *[2]i32, ep: *[2]f32, epbits: u32) void {
    const safe_bits: u5 = @intCast(epbits);
    const levels: i32 = @as(i32, 1) << safe_bits;

    for (0..2) |i| {
        const flevel: f32 = @floatFromInt(levels - 1);
        const s = ep[i] / 255.0 * flevel + 0.5;
        const v = @as(i32, @intFromFloat(s));
        qep[i] = std.math.clamp(v, 0, levels - 1);
        ep[i] = @floatFromInt(unpackToByte(qep[i], epbits));
    }
}

fn channelOptEndpoints(ep: *[2]f32, channel_block: *[16]f32, bits: u32, qblock: *[2]u32) void {
    const safe_bits: u5 = @intCast(bits);
    const levels: i32 = @as(i32, 1) << safe_bits;
    const alevels = @as(f32, @floatFromInt(levels - 1));

    var atb1: f32 = 0.0;
    var sum_q: f32 = 0.0;
    var sum_qq: f32 = 0.0;
    var sum: f32 = 0.0;

    for (0..2) |k1| {
        var qbits_shifted = qblock[k1];
        for (0..8) |k2| {
            const k = k1 * 8 + k2;
            const q = @as(f32, @floatFromInt(qbits_shifted & 15));
            qbits_shifted >>= 4;

            const x = alevels - q;

            sum_q += q;
            sum_qq += q * q;

            sum += channel_block[k];
            atb1 += x * channel_block[k];
        }
    }

    const atb2 = alevels * sum - atb1;

    const cxx = 16.0 * (alevels * alevels) - 2.0 * alevels * sum_q + sum_qq;
    const cyy = sum_qq;
    const cxy = alevels * sum_q - sum_qq;
    const scale = alevels / (cxx * cyy - cxy * cxy);

    ep[0] = (atb1 * cyy - atb2 * cxy) * scale;
    ep[1] = (atb2 * cxx - atb1 * cxy) * scale;

    ep[0] = std.math.clamp(ep[0], 0.0, 255.0);
    ep[1] = std.math.clamp(ep[1], 0.0, 255.0);

    if (@abs(cxx * cyy - cxy * cxy) < 0.001) {
        ep[0] = sum / 16.0;
        ep[1] = ep[0];
    }
}

fn channelOptQuant(qblock: *[2]u32, channel_block: *[16]f32, bits: u32, ep: *[2]f32) f32 {
    const safe_bits: u5 = @intCast(bits);
    const levels: i32 = @as(i32, 1) << safe_bits;

    qblock[0] = 0;
    qblock[1] = 0;

    var total_err: f32 = 0.0;

    for (0..16) |k| {
        const proj: f32 = (channel_block[k] - ep[0]) / (ep[1] - ep[0] + 0.001);

        const flevels: f32 = @floatFromInt(levels);
        const q1: i32 = @intFromFloat(proj * flevels + 0.5);
        const q1_clamped = std.math.clamp(q1, 1, levels - 1);

        var err0: f32 = 0.0;
        var err1: f32 = 0.0;

        const w0 = common.getUnquantValue(bits, q1_clamped - 1);
        const w1 = common.getUnquantValue(bits, q1_clamped);

        const ep_0_i: i32 = @intFromFloat(ep[0]);
        const ep_1_i: i32 = @intFromFloat(ep[1]);

        const dec_v0_i: i32 = @divTrunc((64 - w0) * ep_0_i + w0 * ep_1_i + 32, 64);
        const dec_v1_i: i32 = @divTrunc((64 - w1) * ep_0_i + w1 * ep_1_i + 32, 64);

        const dec_v0: f32 = @floatFromInt(dec_v0_i);
        const dec_v1: f32 = @floatFromInt(dec_v1_i);

        err0 += (dec_v0 - channel_block[k]) * (dec_v0 - channel_block[k]);
        err1 += (dec_v1 - channel_block[k]) * (dec_v1 - channel_block[k]);

        const best_err = if (err0 < err1) err0 else err1;

        const best_q = if (err0 < err1) q1_clamped - 1 else q1_clamped;

        qblock[k / 8] |= @as(u32, @intCast(best_q)) << @intCast(4 * (k % 8));
        total_err += best_err;
    }

    return total_err;
}

fn eqQuantDequant(qep: []i32, ep: []f32, mode: usize, channels: u32) void {
    epQuant(qep, ep, mode, channels);
    epDequant(ep, qep, mode);
}

fn epDequant(ep: []f32, qep: []i32, mode: usize) void {
    const pairs_table = [_]usize{ 3, 2, 3, 2, 1, 1, 1, 2 };
    const pairs = pairs_table[mode];

    // mode 3, 6 are 8-bit
    for (0..8 * pairs) |i| {
        if (mode == 3 or mode == 6) {
            ep[i] = @floatFromInt(qep[i]);
        } else if (mode == 1 or mode == 5) {
            ep[i] = @floatFromInt(unpackToByte(qep[i], 7));
        } else if (mode == 0 or mode == 2 or mode == 4) {
            ep[i] = @floatFromInt(unpackToByte(qep[i], 5));
        } else if (mode == 7) {
            ep[i] = @floatFromInt(unpackToByte(qep[i], 6));
        }
    }
}

fn epQuant(qep: []i32, ep: []f32, mode: usize, channels: u32) void {
    const pairs_table = [_]usize{ 3, 2, 3, 2, 1, 1, 1, 2 };
    const pairs = pairs_table[mode];

    for (0..pairs) |i| {
        if (mode == 0 or mode == 3 or mode == 6 or mode == 7) {
            epQuant0367(qep[i * 8 ..], ep[i * 8 ..], mode, channels);
        } else if (mode == 1) {
            epQuant1(qep[i * 8 ..], ep[i * 8 ..]);
        } else if (mode == 2 or mode == 4 or mode == 5) {
            epQuant245(qep[i * 8 ..], ep[i * 8 ..], mode);
        }
    }
}

fn epQuant245(qep: []i32, ep: []f32, mode: usize) void {
    const bits: u32 = if (mode == 5) 7 else 5;
    const safe_bits: u5 = @intCast(bits);
    const levels: i32 = @as(i32, 1) << safe_bits;

    for (0..8) |i| {
        const flevel: f32 = @floatFromInt(levels - 1);
        const s = ep[i] / 255.0 * flevel + 0.5;
        const v = @as(i32, @intFromFloat(s));
        qep[i] = std.math.clamp(v, 0, levels - 1);
    }
}

fn epQuant1(qep: []i32, ep: []f32) void {
    var qep_b: [16]i32 = @splat(0);

    for (0..2) |b| {
        for (0..8) |i| {
            const bb: i32 = @as(i32, @intCast(b));
            const fb: f32 = @floatFromInt(b);
            const s: f32 = (ep[i] / 255.0 * 127.0 - fb) / 2.0 + 0.5;
            const v: i32 = @as(i32, @intFromFloat(s)) * 2 + bb;
            qep_b[b * 8 + i] = std.math.clamp(v, bb, 126 + bb);
        }
    }

    var ep_b: [16]f32 = @splat(0.0);
    for (0..16) |k| {
        ep_b[k] = @floatFromInt(unpackToByte(qep_b[k], 7));
    }

    var err0: f32 = 0.0;
    var err1: f32 = 0.0;
    for (0..2) |j| {
        for (0..3) |p| {
            err0 += (ep[j * 4 + p] - ep_b[j * 4 + p]) * (ep[j * 4 + p] - ep_b[j * 4 + p]);
            err1 += (ep[j * 4 + p] - ep_b[8 + j * 4 + p]) * (ep[j * 4 + p] - ep_b[8 + j * 4 + p]);
        }
    }

    for (0..8) |i| {
        qep[i] = if (err0 < err1) qep_b[i] else qep_b[8 + i];
    }
}

fn epQuant0367(qep: []i32, ep: []f32, mode: usize, channels: u32) void {
    const init_bits: u32 = if (mode == 0) 4 else if (mode == 7) 5 else 7;
    const bits: u5 = @intCast(init_bits);
    const levels: i32 = @as(i32, 1) << bits;
    const levels2 = levels * 2 - 1;

    for (0..2) |i| {
        var qep_b: [8]i32 = @splat(0);

        for (0..2) |b| {
            for (0..4) |p| {
                const bb: i32 = @as(i32, @intCast(b));
                const s: f32 = ((ep[i * 4 + p] / 255.0 * @as(f32, @floatFromInt(levels2)) - @as(f32, @floatFromInt(bb))) / 2.0 + 0.5);
                const v: i32 = @as(i32, @intFromFloat(s)) * 2 + bb;
                qep_b[b * 4 + p] = std.math.clamp(v, bb, levels2 - 1 + bb);
            }
        }

        var ep_b: [8]f32 = @splat(0.0);
        for (0..8) |j| {
            ep_b[j] = @floatFromInt(qep_b[j]);
        }

        if (mode == 0) {
            for (0..8) |j| {
                const unpack = unpackToByte(qep_b[j], 5);
                ep_b[j] = @floatFromInt(unpack);
            }
        }

        var err0: f32 = 0.0;
        var err1: f32 = 0.0;
        for (0..channels) |p| {
            err0 += (ep[i * 4 + p] - ep_b[p]) * (ep[i * 4 + p] - ep_b[p]);
            err1 += (ep[i * 4 + p] - ep_b[4 + p]) * (ep[i * 4 + p] - ep_b[4 + p]);
        }

        for (0..4) |p| {
            qep[i * 4 + p] = if (err0 < err1) qep_b[p] else qep_b[4 + p];
        }
    }
}

fn blockSegment(ep: []f32, block: *[64]f32, mask: u32, channels: u32) void {
    common.blockSegmentCore(ep, block, mask, channels);

    for (0..2) |i| {
        for (0..channels) |p| {
            ep[4 * i + p] = std.math.clamp(ep[4 * i + p], 0.0, 255.0);
        }
    }
}

fn unpackToByte(v: i32, bits: u32) i32 {
    const safe_bits: u5 = @intCast(bits);
    const vv = v << (8 - safe_bits);
    return vv + (vv >> safe_bits);
}

const Mode45Parameters = struct {
    qep: [8]i32 = @splat(0),
    qblock: [2]u32 = @splat(0),
    aqep: [2]i32 = @splat(0),
    aqblock: [2]u32 = @splat(0),
    rotation: u32 = 0,
    swap: u32 = 0,
};
