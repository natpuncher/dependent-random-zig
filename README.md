# dependent-random-zig

Dependent random algorithm implementation for zig lang.

## what's it all about?

The uniform or true random distribution describes the probability of random event that underlies no manipulation of the chance depending on earlier outcomes. This means that every "roll" operates independently.

In this implementation of pseudo-random distribution (often shortened to PRD) the event's chance increases every time it does not occur, but is lower in the first place as compensation. This results in the effects occurring more consistently.

The probability of an effect to occur (or proc) on the Nth test since the last successful proc is given by P(N) = C × N. For each instance which could trigger the effect but does not, the PRD augments the probability of the effect happening for the next instance by a constant C. This constant, which is also the initial probability, is lower than the listed probability of the effect it is shadowing. Once the effect occurs, the counter is reset.

## features

- automatically adjusts chances of events after every roll based on roll result
- reduces the number of consequent successes and fails (for 33% chance event after 10^6 iterations it's 28 consequent fails with generic zig random vs only 8 with dependent random)
- increases drop chance of rare items so it will more likely drop after certain amount of tries
- keeps desired chances in a long run
- supports chances up to 0.01% accuracy
- single chance, useful for events like critical hit, block chance or drop an item;
- multiple chances or weights, useful for determining what item will drop from the chest;
- multiple evenly distributed chances
- change registered event chances

## install

execute in your project repository root:

```
zig fetch --save git+https://github.com/natpuncher/dependent-random-zig
```

then add dependency and import in `build.zig` file:

```zig
const dr = build_settings.dependency("dependent_random_zig", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("dependent_random_zig", dr.module("dependent_random_zig"));
```

## usage

```zig
const DependentRandom = @import("dependent_random_zig").DependentRandom;

const gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc = gpa.allocator();

const RandomEventCapacity = 8; // max event argument count

const seed: u64 = @intCast(std.time.milliTimestamp());
var random = try Random(RandomEventCapacity).init(alloc, seed);
defer random.deinit();

const crit_chance = 0.33; // 33%
const crit_event_id = try random.register(crit_chance);
if (random.roll(crit_event_id)) {
 // crit with 33%
}

const new_crit_chance = 0.75; // 75%
random.reset(crit_event_id, new_crit_chance);
if (random.roll(crit_event_id)) {
 // crit with 75%
}

const chest_item_weights = [_]f32 {
 10,
 20,
 70,
};

const chest_event_id = try random.registerMulti(chest_item_weights);
// 10% will be 0, 20% - 1 and 70% - 2
const dropped_item_index = random.rollMulti(chest_event_id);

// 8 evenly distributed chances
const same_chance_items_event_id = random.registerMultiEqual(RandomEventCapacity); 
// 12.5% for 0 to 7 index
const same_chance_id = random.rollMulti(same_chance_items_event_id); 

```
