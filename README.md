# dependent-random-zig

dependent random distribution for zig

## api

```zig
const DependentRandom = @import("dependent_random_zig").DependentRandom;

const Random = DependentRandom(8); // maximum options per event

var random = try Random.init(allocator, seed);
defer random.deinit();
```

```zig
// single event
const crit = try random.register(0.33);

if (crit.roll(&random)) {
    // critical hit
}

crit.reset(&random, 0.5);
```

```zig
// weighted multi event
var weights = [_]f32{ 10, 20, 70 };
const loot = try random.registerMulti(&weights);

const item_index = loot.roll(&random, .{}) orelse unreachable;
```

```zig
// equally weighted multi event
const tile = try random.registerMultiEqual(8);

const tile_index = tile.roll(&random, .{}) orelse unreachable;
```

```zig
// temporarily exclude options without changing their history
const ignored = [_]bool{ false, true, false, false, true, false, false, false };

const tile_index = tile.roll(&random, .{
    .ignored = &ignored,
}) orelse unreachable;
```

Events store only their id. Pass the random by reference when rolling or resetting, so the random can safely move in memory.

## how it works

Unlike independent random rolls, dependent random distribution increases an event's effective chance each time it does not occur and resets its history when it does. This reduces long streaks while preserving the configured distribution over time. Ignored multi-event options do not participate in a roll and their history remains unchanged.

## install

Execute in your project repository root:

```
zig fetch --save git+https://github.com/natpuncher/dependent-random-zig
```

Then add the dependency and import in `build.zig`:

```zig
const dependent_random = b.dependency("dependent_random_zig", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport(
    "dependent_random_zig",
    dependent_random.module("dependent_random_zig"),
);
```
