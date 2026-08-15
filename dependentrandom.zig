const std = @import("std");
const Chances = @import("chances.zig").Chances;

pub fn DependentRandom(event_options_capacity: usize) type {
    if (event_options_capacity == 0) @compileError("event options capacity must be greater than zero");

    return struct {
        const This = @This();

        chances_buffer: [event_options_capacity]f64 = undefined,
        events: std.ArrayList(EventData(event_options_capacity)),

        random: std.Random.Xoshiro256,
        allocator: std.mem.Allocator,

        pub const RollConfig = struct {
            ignored: ?[]const bool = null,
        };

        pub const SingleEvent = struct {
            id: usize,

            pub fn roll(event: SingleEvent, random: *This) bool {
                return random.rollSingle(event.id);
            }

            pub fn reset(event: SingleEvent, random: *This, chance: f32) void {
                var data = &random.events.items[event.id];
                data.reset(1);
                data.chances[0] = chance;
            }
        };

        pub const MultiEvent = struct {
            id: usize,

            pub fn roll(event: MultiEvent, random: *This, config: RollConfig) ?usize {
                return random.rollMulti(event.id, config);
            }

            pub fn getCount(event: MultiEvent, random: *const This) usize {
                return random.events.items[event.id].count;
            }

            pub fn reset(event: MultiEvent, random: *This, chances: []const f32) void {
                assertValidChances(chances);
                var data = &random.events.items[event.id];
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

            pub fn resetEqual(event: MultiEvent, random: *This, count: usize) void {
                assertValidCount(count);
                var data = &random.events.items[event.id];
                data.reset(count);

                const sum: f32 = @floatFromInt(count);
                for (0..count) |i| {
                    data.chances[i] = 100 / sum;
                }
            }
        };

        pub fn init(allocator: std.mem.Allocator, seed: u64) This {
            return This{
                .events = .empty,
                .random = std.Random.DefaultPrng.init(seed),
                .allocator = allocator,
            };
        }

        pub fn deinit(random: *This) void {
            random.events.deinit(random.allocator);
        }

        pub fn register(random: *This, chance: f32) !SingleEvent {
            var data = EventData(event_options_capacity).init(1);
            data.chances[0] = chance;
            const id = random.events.items.len;
            try random.events.append(random.allocator, data);
            return .{ .id = id };
        }

        pub fn registerMulti(random: *This, chances: []const f32) !MultiEvent {
            assertValidChances(chances);
            var data = EventData(event_options_capacity).init(chances.len);

            const count = chances.len;

            var sum: f32 = 0;
            for (0..count) |i| {
                sum += chances[i];
            }
            for (0..count) |i| {
                data.chances[i] = chances[i] / sum;
            }

            const id = random.events.items.len;
            try random.events.append(random.allocator, data);
            return .{ .id = id };
        }

        pub fn registerMultiEqual(random: *This, count: usize) !MultiEvent {
            assertValidCount(count);
            var data = EventData(event_options_capacity).init(count);

            const sum: f32 = @floatFromInt(data.count);
            for (0..count) |i| {
                data.chances[i] = 1 / sum;
            }

            const id = random.events.items.len;
            try random.events.append(random.allocator, data);
            return .{ .id = id };
        }

        fn assertValidCount(count: usize) void {
            std.debug.assert(count > 0);
            std.debug.assert(count <= event_options_capacity);
        }

        fn assertValidChances(chances: []const f32) void {
            assertValidCount(chances.len);

            var sum: f32 = 0;
            for (chances) |chance| {
                std.debug.assert(chance >= 0);
                sum += chance;
            }
            std.debug.assert(std.math.isFinite(sum));
            std.debug.assert(sum > 0);
        }

        fn rollSingle(random: *This, id: usize) bool {
            return (random.rollMulti(id, .{}) orelse return false) == 1;
        }

        fn rollMulti(random: *This, id: usize, config: RollConfig) ?usize {
            var event = &random.events.items[id];

            var sum: f64 = 0;
            for (0..event.count) |i| {
                if (config.ignored) |ignored| {
                    if (i < ignored.len and ignored[i]) continue;
                }

                const history: f64 = @floatFromInt(event.history[i] + 1);
                const chance = Chances.getChance(event.chances[i]) * history;
                random.chances_buffer[i] = chance;
                sum += chance;
            }
            if (sum == 0) return null;

            var result = event.count - 1;
            if (event.count == 1) {
                result = if (random.chances_buffer[0] > random.random.random().float(f64)) 1 else 0;
            } else {
                var value = random.random.random().float(f64) * sum;
                for (0..event.count) |i| {
                    if (config.ignored) |ignored| {
                        if (i < ignored.len and ignored[i]) continue;
                    }

                    const chance = random.chances_buffer[i];
                    if (chance > value) {
                        result = i;
                        break;
                    }
                    value -= chance;
                }
            }

            if (config.ignored) |ignored| {
                event.updateHistoryIgnoring(result, ignored);
            } else {
                event.updateHistory(result);
            }
            return result;
        }
    };
}

test "single" {
    var random = DependentRandom(4).init(std.testing.allocator, 123);
    defer random.deinit();

    const event = try random.register(0);
    const true_event = try random.register(100);
    try std.testing.expectApproxEqAbs(0, random.events.items[event.id].chances[0], 0.001);
    try std.testing.expectApproxEqAbs(0, Chances.getChance(random.events.items[event.id].chances[0]), 0.001);
    try std.testing.expectEqual(1, random.events.items[event.id].count);
    try std.testing.expectEqual(false, event.roll(&random));
    try std.testing.expectEqual(true, true_event.roll(&random));
}

test "multy" {
    var random = DependentRandom(4).init(std.testing.allocator, 123);
    defer random.deinit();

    var weights = [_]f32{ 100, 200, 700 };
    const event = try random.registerMulti(&weights);
    try std.testing.expectEqual(3, random.events.items[event.id].count);
    try std.testing.expectApproxEqAbs(0.1, random.events.items[event.id].chances[0], 0.001);
    try std.testing.expectApproxEqAbs(0.2, random.events.items[event.id].chances[1], 0.001);
    try std.testing.expectApproxEqAbs(0.7, random.events.items[event.id].chances[2], 0.001);

    const count = 1_000_000;
    var results: [weights.len]f32 = std.mem.zeroes([weights.len]f32);
    for (0..count) |_| {
        results[event.roll(&random, .{}) orelse unreachable] += 1;
    }
    try std.testing.expectApproxEqAbs(0.1, results[0] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.2, results[1] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.7, results[2] / count, 0.001);
}

test "multi equal" {
    var random = DependentRandom(4).init(std.testing.allocator, 123);
    defer random.deinit();

    const event = try random.registerMultiEqual(3);
    try std.testing.expectEqual(3, random.events.items[event.id].count);
    try std.testing.expectApproxEqAbs(0.333, random.events.items[event.id].chances[0], 0.001);
    try std.testing.expectApproxEqAbs(0.333, random.events.items[event.id].chances[1], 0.001);
    try std.testing.expectApproxEqAbs(0.333, random.events.items[event.id].chances[2], 0.001);

    const count = 1_000_000;
    var results: [3]f32 = std.mem.zeroes([3]f32);
    for (0..count) |_| {
        results[event.roll(&random, .{}) orelse unreachable] += 1;
    }
    try std.testing.expectApproxEqAbs(0.333, results[0] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.333, results[1] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.333, results[2] / count, 0.001);
}

test "multi equal ignores options without changing remaining chances" {
    var random = DependentRandom(3).init(std.testing.allocator, 123);
    defer random.deinit();

    const event = try random.registerMultiEqual(3);
    const ignored = [_]bool{ false, true, false };
    const count = 1_000_000;
    var results: [3]f32 = std.mem.zeroes([3]f32);

    for (0..count) |_| {
        const result = event.roll(&random, .{ .ignored = &ignored }) orelse unreachable;
        results[result] += 1;
    }

    try std.testing.expectEqual(0, results[1]);
    try std.testing.expectApproxEqAbs(0.5, results[0] / count, 0.001);
    try std.testing.expectApproxEqAbs(0.5, results[2] / count, 0.001);
}

test "validation" {
    var dependent_random = DependentRandom(1).init(std.testing.allocator, 123);
    defer dependent_random.deinit();

    var normal_random = std.Random.DefaultPrng.init(123);

    const chance: f32 = 33;
    const normalized_chance = chance * 0.01;
    const event = try dependent_random.register(normalized_chance);

    const iteration_count = 1_000_000;

    var dependent_longest_same_roll_count: usize = 0;
    var dependent_same_roll_count: usize = 0;
    var dependent_last_roll: bool = false;

    var normal_longest_same_roll_count: usize = 0;
    var normal_same_roll_count: usize = 0;
    var normal_last_roll: bool = false;

    var success_count: usize = 0;
    for (0..iteration_count) |_| {
        const dependent_result = event.roll(&dependent_random);

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
            std.debug.assert(count > 0 and count <= max_event_size);
            return This{
                .chances = std.mem.zeroes([max_event_size]f32),
                .history = std.mem.zeroes([max_event_size]u16),
                .count = count,
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

        pub fn updateHistoryIgnoring(event: *This, id: usize, ignored: []const bool) void {
            for (0..event.count) |i| {
                if (i < ignored.len and ignored[i]) continue;

                if (i == id) {
                    event.history[i] = 0;
                } else {
                    event.history[i] += 1;
                }
            }
        }

        pub fn reset(event: *This, count: usize) void {
            std.debug.assert(count > 0 and count <= max_event_size);
            for (0..event.count) |i| {
                event.history[i] = 0;
            }
            event.count = count;
        }
    };
}
