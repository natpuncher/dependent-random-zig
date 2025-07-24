const std = @import("std");

pub fn DependentRandom(max_event_size: usize) type {
    return struct {
        const This = @This();

        chances_buffer: [max_event_size]f32 = undefined,
        events: std.ArrayList(EventData(max_event_size)),

        random: std.Random.Xoshiro256,

        pub fn init(allocator: std.mem.Allocator, seed: u64) !This {
            return This{
                .events = std.ArrayList(EventData(max_event_size)).init(allocator),
                .random = std.Random.DefaultPrng.init(seed),
            };
        }

        pub fn deinit(random: *This) void {
            random.events.deinit();
        }

        // chance 0% - 100%
        pub fn register(random: *This, chance: f32) !usize {
            var data = EventData(max_event_size).init(1);
            data.chances[0] = chance;
            const id = random.events.items.len;
            try random.events.append(data);
            return id;
        }

        pub fn registerMulti(random: *This, chances: []f32) !usize {
            var data = EventData(max_event_size).init(chances.len);

            const count = @min(chances.len, max_event_size);

            var sum: f32 = 0;
            for (0..count) |i| {
                sum += chances[i];
            }
            for (0..count) |i| {
                data.chances[i] = 100 * chances[i] / sum;
            }

            const id = random.events.items.len;
            try random.events.append(data);
            return id;
        }

        pub fn registerMultiEqual(random: *This, count: usize) !usize {
            var data = EventData(max_event_size).init(count);

            const sum: f32 = @floatFromInt(data.count);
            for (0..count) |i| {
                data.chances[i] = 100 / sum;
            }

            const id = random.events.items.len;
            try random.events.append(data);
            return id;
        }

        pub fn getCount(random: This, id: usize) usize {
            return random.events.items[id].count;
        }

        pub fn reset(random: *This, id: usize, chances: []f32) void {
            var data = &random.events.items[id];
            data.reset(chances.len);
            const count = data.count;

            var sum: f32 = 0;
            for (0..count) |i| {
                sum += chances[i];
            }
            for (0..count) |i| {
                data.chances[i] = 100 * chances[i] / sum;
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

        // for single event returns 1 = true, 0 = false
        // for multiple returns index in array
        pub fn roll(random: *This, id: usize) usize {
            var event = &random.events.items[id];

            var sum: f32 = 0;
            for (0..event.count) |i| {
                const history: f32 = @floatFromInt(event.history[i] + 1);
                const chance = Chances.getChance(event.chances[i]) * history;
                random.chances_buffer[i] = chance;
                sum += chance;
            }
            if (event.count > 1) {
                for (0..event.count) |i| {
                    random.chances_buffer[i] = random.chances_buffer[i] / sum;
                }
            }

            var value = random.random.random().float(f32);
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

    const id = try random.register(0.12);
    const true_id = try random.register(100);
    try std.testing.expectApproxEqAbs(0.12, random.events.items[id].chances[0], 0.001);
    try std.testing.expectApproxEqAbs(0, Chances.getChance(random.events.items[id].chances[0]), 0.001);
    try std.testing.expectEqual(1, random.events.items[id].count);
    try std.testing.expectEqual(0, random.roll(id));
    try std.testing.expectEqual(1, random.roll(true_id));
}

test "multy" {
    var random = try DependentRandom(4).init(std.testing.allocator, 123);
    defer random.deinit();

    var weights = [_]f32{ 100, 200, 700 };
    const id = try random.registerMulti(&weights);
    try std.testing.expectEqual(3, random.events.items[id].count);
    try std.testing.expectApproxEqAbs(10, random.events.items[id].chances[0], 0.001);
    try std.testing.expectApproxEqAbs(20, random.events.items[id].chances[1], 0.001);
    try std.testing.expectApproxEqAbs(70, random.events.items[id].chances[2], 0.001);

    const count = 1_000_000;
    var results: [weights.len]f32 = std.mem.zeroes([weights.len]f32);
    for (0..count) |_| {
        results[random.roll(id)] += 1;
    }
    try std.testing.expectApproxEqAbs(0.1, results[0] / count, 0.01);
    try std.testing.expectApproxEqAbs(0.2, results[1] / count, 0.01);
    try std.testing.expectApproxEqAbs(0.7, results[2] / count, 0.01);
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

const Chances = struct {
    const Step = 0.5;
    const ReverseStep = 1 / Step;

    const Values = [_]f32{
        0,
        0.00003,
        0.00014,
        0.00031,
        0.0005599999,
        0.0009000005,
        0.001289999,
        0.001749997,
        0.00234,
        0.002900004,
        0.00365001,
        0.004390015,
        0.005140021,
        0.006130029,
        0.007080036,
        0.007950036,
        0.009229986,
        0.01039994,
        0.0114599,
        0.01299984,
        0.01422979,
        0.01563974,
        0.01727983,
        0.01888991,
        0.02037999,
        0.02219009,
        0.02403019,
        0.02570028,
        0.02725037,
        0.02959049,
        0.03147055,
        0.03330031,
        0.03563,
        0.03780971,
        0.03984945,
        0.04231912,
        0.04456882,
        0.04723847,
        0.04952817,
        0.05164789,
        0.05418755,
        0.05714716,
        0.05993679,
        0.06222649,
        0.06460617,
        0.06828569,
        0.07089534,
        0.07432489,
        0.0772645,
        0.07985416,
        0.08325371,
        0.08653328,
        0.08957288,
        0.09328239,
        0.09633198,
        0.09970154,
        0.1029011,
        0.1064306,
        0.1104001,
        0.1135997,
        0.1169393,
        0.1205688,
        0.1246882,
        0.1283378,
        0.1317773,
        0.1362467,
        0.1397562,
        0.1436957,
        0.1474852,
        0.1521146,
        0.1557241,
        0.1595536,
        0.1637531,
        0.1682325,
        0.1730019,
        0.1767414,
        0.1809308,
        0.1853102,
        0.1895797,
        0.1951189,
        0.1991684,
        0.2035478,
        0.2076373,
        0.2134765,
        0.2181059,
        0.2225453,
        0.2275846,
        0.232204,
        0.2369934,
        0.2418728,
        0.2465421,
        0.2512634,
        0.2557495,
        0.2625587,
        0.2673352,
        0.2731531,
        0.2772887,
        0.2832268,
        0.288584,
        0.2942517,
        0.2990682,
        0.304806,
        0.3093522,
        0.3142588,
        0.3201368,
        0.3243425,
        0.330571,
        0.3367193,
        0.3434184,
        0.3491462,
        0.3568766,
        0.3622639,
        0.3695839,
        0.3759725,
        0.3826216,
        0.3880689,
        0.394758,
        0.4007962,
        0.4066241,
        0.4135235,
        0.4189709,
        0.4254897,
        0.4314978,
        0.4371655,
        0.4429934,
        0.4488313,
        0.4548195,
        0.4603069,
        0.4664853,
        0.4723833,
        0.4779609,
        0.4838288,
        0.4890359,
        0.4955747,
        0.500211,
        0.5104048,
        0.5236528,
        0.5334361,
        0.5450318,
        0.5557163,
        0.5649388,
        0.5745018,
        0.5844052,
        0.5956705,
        0.6048129,
        0.6143458,
        0.6238687,
        0.6332214,
        0.6429245,
        0.648402,
        0.6611092,
        0.66908,
        0.6797044,
        0.6884363,
        0.696347,
        0.7036068,
        0.7129695,
        0.721441,
        0.7286508,
        0.7368219,
        0.7452133,
        0.752423,
        0.7591622,
        0.7680843,
        0.7751539,
        0.7829645,
        0.7889326,
        0.7983654,
        0.804764,
        0.8130953,
        0.8192837,
        0.8267138,
        0.8324816,
        0.8393109,
        0.8465908,
        0.8527391,
        0.8599088,
        0.865977,
        0.8728964,
        0.8781235,
        0.8855937,
        0.8916318,
        0.8975899,
        0.9043291,
        0.9100368,
        0.9157746,
        0.9209716,
        0.9276206,
        0.9326475,
        0.938936,
        0.9445837,
        0.9504416,
        0.9563997,
        0.9614666,
        0.9667237,
        0.9722211,
        0.9776485,
        0.9829557,
        0.9884632,
        0.9931595,
        1,
    };

    pub fn getChance(chance: f32) f32 {
        if (chance < 0) return 0;

        const index: usize = @intFromFloat(@round(chance * ReverseStep));
        if (index >= Chances.Values.len) return Chances.Values[Chances.Values.len - 1];

        return Chances.Values[index];
    }
};

test "get chance" {
    const delta = (Chances.Values[1] - Chances.Values[0]) / 5;
    try std.testing.expectApproxEqAbs(Chances.Values[1], Chances.getChance(0.32), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[0], Chances.getChance(0.22), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[0], Chances.getChance(0.12), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[0], Chances.getChance(0.24), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[1], Chances.getChance(0.25), delta);
}

test "last chance" {
    const delta = (Chances.Values[1] - Chances.Values[0]) / 5;
    try std.testing.expectApproxEqAbs(Chances.Values[Chances.Values.len - 1], Chances.getChance(232), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[Chances.Values.len - 1], Chances.getChance(100), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[Chances.Values.len - 1], Chances.getChance(99.9), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[Chances.Values.len - 2], Chances.getChance(99.4), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[Chances.Values.len - 2], Chances.getChance(99.6), delta);
    try std.testing.expectApproxEqAbs(Chances.Values[Chances.Values.len - 1], Chances.getChance(99.75), delta);
}

test "negative chance" {
    const delta = (Chances.Values[1] - Chances.Values[0]) / 5;
    try std.testing.expectApproxEqAbs(0, Chances.getChance(-123), delta);
    try std.testing.expectApproxEqAbs(0, Chances.getChance(0.01), delta);
    try std.testing.expectApproxEqAbs(0, Chances.getChance(-0.01), delta);
}
