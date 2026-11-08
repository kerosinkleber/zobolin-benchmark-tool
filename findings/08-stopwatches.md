# Step 8: stopwatches in the game's systems (2026-11-08)

`game/benchmark/bench_zones.gd` (BenchZones) gives named stopwatches
("zones"). In the game's code they look like this, with the on/off check at
the call site so they cost almost nothing when off:

    if BenchZones.on: BenchZones.begin(&"forest")
    _update_near(Vector2(world.x, world.z))
    if BenchZones.on: BenchZones.end(&"forest")

They wrap the heavy calls, never whole functions with early returns:

| Zone | Wraps |
|---|---|
| `forest` | building the near trees after the camera moved (`_update_near`) |
| `forest.blocks` | building one block of near trees |
| `forest.collision` | building and removing trunk collision |
| `objects` | updating the far-object levels |
| `grass` | placing grass tiles |
| `daynight` | day, night and weather each frame |
| `recentre` (physics) | re-centring, split into `.regions` (moving Terrain3D's regions), `.shift` (moving every node), `.collision` (rebuilding the ground's collision) and `.signals` (the systems that follow, like the grass) |

A name with a dot is a piece of the zone before the dot. Zones in physics
steps are counted with the physics time. What the top-level zones don't
cover is shown as **unattributed** (scripts and physics separately).

The recorder switches them on while it records; their cost is measured at
the start of every run and saved in `run.json` (`zone_overhead_us`).

## Checks (plan step 8)

- **Cost:** 1.6 µs per begin/end pair when on, 0.24 µs when off (debug
  build). About 15 pairs per frame: about 0.025 ms, under the 0.1 ms limit.
- **They add up:** on the flight, the re-centring pieces (regions, shift,
  collision) add up to **198.5 ms**; the game's own timing of the same
  7 re-centres is **198.6 ms (−0.1 %)**. The limit was 10 %.

## Where the processor time goes on the flight (GTX 970 PC, 3 runs)

Per frame on average (and the slowest single frame):

| Zone | Average | Slowest frame |
|---|---|---|
| Scripts and physics together | 1.64 ms | |
| Far-object levels (`objects`) | 0.27 ms | 4.0 ms |
| Near trees (`forest`) | 0.16 ms | 22.0 ms |
| – trunk collision (`forest.collision`) | 0.10 ms | **21.9 ms** |
| – tree blocks (`forest.blocks`) | 0.04 ms | 4.3 ms |
| Re-centring (`recentre`) | 0.16 ms | **30.0 ms** |
| – moving the regions | 0.10 ms | 19.0 ms |
| – the ground's collision | 0.06 ms | 10.5 ms |
| – moving every node | 0.004 ms | 0.9 ms |
| Grass placement | 0.04 ms | 0.3 ms |
| Day and night | 0.02 ms | 0.05 ms |
| Unattributed scripts | 0.09 ms | |
| Unattributed physics (mostly Jolt's own step) | 0.89 ms | |

**What it means:** the two worst single-frame costs are **building trunk
collision** (up to 22 ms in one frame) and **moving the terrain regions
when re-centring** (up to 19 ms). Both are one-off spikes, not steady
costs, so they show as stutters, not as a lower frame rate. Spreading the
trunk collision over several frames would remove the bigger one.

In the held views (not moving), only `daynight` runs (0.02 ms): nothing
else has work to do.
