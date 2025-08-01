const std = @import("std");
const Chances = @import("chances.zig").Chances;

pub fn DependentRandom(event_options_capacity: usize) type {
    return struct {
        const This = @This();

        chances_buffer: [event_options_capacity]f64 = undefined,
        events: std.ArrayList(EventData(event_options_capacity)),

        random: std.Random.Xoshiro256,

        pub fn init(allocator: std.mem.Allocator, seed: u64) !This {
            return This{
                .events = std.ArrayList(EventData(event_options_capacity)).init(allocator),
                .random = std.Random.DefaultPrng.init(seed),
            };
        }

        pub fn deinit(random: *This) void {
            random.events.deinit();
        }

        pub fn register(random: *This, chance: f32) !usize {
            var data = EventData(event_options_capacity).init(1);
            data.chances[0] = chance;
            const id = random.events.items.len;
            try random.events.append(data);
            return id;
        }

        pub fn registerMulti(random: *This, chances: []f32) !usize {
            var data = EventData(event_options_capacity).init(chances.len);

            const count = @min(chances.len, event_options_capacity);

            var sum: f32 = 0;
            for (0..count) |i| {
                sum += chances[i];
            }
            for (0..count) |i| {
                data.chances[i] = chances[i] / sum;
            }

            const id = random.events.items.len;
            try random.events.append(data);
            return id;
        }

        pub fn registerMultiEqual(random: *This, count: usize) !usize {
            var data = EventData(event_options_capacity).init(count);

            const sum: f32 = @floatFromInt(data.count);
            for (0..count) |i| {
                data.chances[i] = 1 / sum;
            }

            const id = random.events.items.len;
            try random.events.append(data);
            return id;
        }

        pub fn getCount(random: This, id: usize) usize {
            return random.events.items[id].count;
        }

        pub fn reset(random: *This, id: usize, chance: f32) void {
            var data = &random.events.items[id];
            data.reset(1);
            data.chances[0] = chance;
        }

        pub fn resetMulti(random: *This, id: usize, chances: []f32) void {
            var data = &random.events.items[id];
            data.reset(chances.len);
            const count = data.count;

            var sum: f32 = 0;
            for (0..count) |i| {
                sum += chances[i];
            }
            for (0..count) |i| {
                data.chances[i] = chances[i] / sum;
            }
        }

        pub fn resetEqual(random: *This, id: usize, count: usize) void {
            var data = &random.events.items[id];
            data.reset(count);

            const sum: f32 = @floatFromInt(count);
            for (0..count) |i| {
                data.chances[i] = 100 / sum;
            }
        }

        pub fn roll(random: *This, id: usize) bool {
            return random.rollMulti(id) == 1;
        }

        pub fn rollMulti(random: *This, id: usize) usize {
            var event = &random.events.items[id];

            var sum: f64 = 0;
            for (0..event.count) |i| {
                const history: f64 = @floatFromInt(event.history[i] + 1);
                const chance = Chances.getChance(event.chances[i]) * history;
                random.chances_buffer[i] = chance;
                sum += chance;
            }
            if (event.count > 1) {
                for (0..event.count) |i| {
                    random.chances_buffer[i] = random.chances_buffer[i] / sum;
                }
            }

            var value = random.random.random().float(f64);
            var result = event.count - 1;
            if (event.count == 1) {
                if (random.chances_buffer[0] > value) result = 1;
            } else {
                for (0..event.count) |i| {
                    const chance = random.chances_buffer[i];
                    if (chance > value) {
                        result = i;
                        break;
                    }
                    value -= chance;
                }
            }
            event.updateHistory(result);
            return result;
        }
    };
}

test "single" {
    var random = try DependentRandom(4).init(std.testing.allocator, 123);
    defer random.deinit();

    const id = try random.register(0);
    const true_id = try random.register(100);
    try std.testing.expectApproxEqAbs(0, random.events.items[id].chances[0], 0.001);
    try std.testing.expectApproxEqAbs(0, Chances.getChance(random.events.items[id].chances[0]), 0.001);
    try std.testing.expectEqual(1, random.events.items[id].count);
    try std.testing.expectEqual(false, random.roll(id));
    try std.testing.expectEqual(true, random.roll(true_id));
}

test "multy" {
    var random = try DependentRandom(4).init(std.testing.allocator, 123);
    defer random.deinit();

    var weights = [_]f32{ 100, 200, 700 };
    const id = try random.registerMulti(&weights);
    try std.testing.expectEqual(3, random.events.items[id].count);
    try std.testing.expectApproxEqAbs(0.1, random.events.items[id].chances[0], 0.001);
    try std.testing.expectApproxEqAbs(0.2, random.events.items[id].chances[1], 0.001);
    try std.testing.expectApproxEqAbs(0.7, random.events.items[id].chances[2], 0.001);

    const count = 1_000_000;
    var results: [weights.len]f32 = std.mem.zeroes([weights.len]f32);
    for (0..count) |_| {
        results[random.rollMulti(id)] += 1;
    }
    try std.testing.expectApproxEqAbs(0.1, results[0] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.2, results[1] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.7, results[2] / count, 0.001);
}

test "multi equal" {
    var random = try DependentRandom(4).init(std.testing.allocator, 123);
    defer random.deinit();

    const id = try random.registerMultiEqual(3);
    try std.testing.expectEqual(3, random.events.items[id].count);
    try std.testing.expectApproxEqAbs(0.333, random.events.items[id].chances[0], 0.001);
    try std.testing.expectApproxEqAbs(0.333, random.events.items[id].chances[1], 0.001);
    try std.testing.expectApproxEqAbs(0.333, random.events.items[id].chances[2], 0.001);

    const count = 1_000_000;
    var results: [3]f32 = std.mem.zeroes([3]f32);
    for (0..count) |_| {
        results[random.rollMulti(id)] += 1;
    }
    try std.testing.expectApproxEqAbs(0.333, results[0] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.333, results[1] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.333, results[2] / count, 0.001);
}

test "validation" {
    var dependent_random = try DependentRandom(1).init(std.testing.allocator, 123);
    defer dependent_random.deinit();

    var normal_random = std.Random.DefaultPrng.init(123);

    const chance: f32 = 33;
    const normalized_chance = chance * 0.01;
    const id = try dependent_random.register(normalized_chance);

    const iteration_count = 1_000_000;

    var dependent_longest_same_roll_count: usize = 0;
    var dependent_same_roll_count: usize = 0;
    var dependent_last_roll: bool = false;

    var normal_longest_same_roll_count: usize = 0;
    var normal_same_roll_count: usize = 0;
    var normal_last_roll: bool = false;

    var success_count: usize = 0;
    for (0..iteration_count) |_| {
        const dependent_result = dependent_random.roll(id);

        if (dependent_result) success_count += 1;
        if (dependent_last_roll == dependent_result) {
            dependent_same_roll_count += 1;
            if (dependent_same_roll_count > dependent_longest_same_roll_count) dependent_longest_same_roll_count = dependent_same_roll_count;
        } else {
            dependent_last_roll = dependent_result;
            dependent_same_roll_count = 0;
        }

        const normal_result = normalized_chance > normal_random.random().float(f32);
        if (normal_last_roll == normal_result) {
            normal_same_roll_count += 1;
            if (normal_same_roll_count > normal_longest_same_roll_count) normal_longest_same_roll_count = normal_same_roll_count;
        } else {
            normal_last_roll = normal_result;
            normal_same_roll_count = 0;
        }
    }

    std.debug.print("dependent longest same roll = {} vs normal longest same roll = {}\n", .{ dependent_longest_same_roll_count, normal_longest_same_roll_count });
    try std.testing.expect(normal_longest_same_roll_count > dependent_longest_same_roll_count);

    const fcount: f32 = @floatFromInt(success_count);
    const dependent_chance: f32 = (fcount / iteration_count);
    std.debug.print("chance = {}%, dependent chance = {}%\n", .{ chance, dependent_chance * 100 });
    try std.testing.expectApproxEqAbs(normalized_chance, dependent_chance, 0.0001);
}

fn EventData(max_event_size: usize) type {
    return struct {
        const This = @This();

        chances: [max_event_size]f32,
        history: [max_event_size]u16,
        count: usize,

        pub fn init(count: usize) This {
            return This{
                .chances = std.mem.zeroes([max_event_size]f32),
                .history = std.mem.zeroes([max_event_size]u16),
                .count = @min(count, max_event_size),
            };
        }

        pub fn updateHistory(event: *This, id: usize) void {
            if (event.count == 1) {
                if (id == 1) {
                    event.history[0] = 0;
                } else {
                    event.history[0] += 1;
                }
            } else {
                for (0..event.count) |i| {
                    if (i == id) {
                        event.history[i] = 0;
                    } else {
                        event.history[i] += 1;
                    }
                }
            }
        }

        pub fn reset(event: *This, count: usize) void {
            for (0..event.count) |i| {
                event.history[i] = 0;
            }
            event.count = @min(count, max_event_size);
        }
    };
}
