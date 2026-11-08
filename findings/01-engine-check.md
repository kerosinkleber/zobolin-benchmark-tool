# Step 1: engine check (2026-11-08)

Which of Godot 4.7.2's measuring tools really work, tested on the
development PC: GTX 970, Ryzen 7 1800X, high preset (5120 × 2880 drawn),
Forward+, Vulkan, Jolt. The probe is `game/benchmark/engine_check.gd` in the
game repo; run it with

    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Test engine
    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Test engine -GpuProfile

Raw results: `01-engine-check-gtx970-high.json` (the `-GpuProfile` run).

## Results

| Question | Answer | What the tool does about it |
|---|---|---|
| Is this a debug build? | **Yes** (the editor binary). Script times are higher than in a shipped game | Record the build type with every result |
| Render thread model | 1 = Single-Safe: drawing runs **on the main thread** | Main-thread time includes waiting for the graphics card (see below) |
| Frame cap? | None: 14.5 ms median, spread 13.9–14.9 ms | Cap detector works; keep it for every run |
| `TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, `TIME_FPS` | **Update only about once a second.** `TIME_PROCESS` (14.9 ms) is the whole main-loop step including drawing, not "script time" | **Not used per frame.** Our own stopwatches at the frame edges instead |
| Our frame-edge stopwatches | Work. Per frame: scripts (`_process`) 0.09 ms, drawing 13.7 ms (mostly waiting for the graphics card), physics tick 0.57 ms | These become the recorder's processor columns |
| Measured GPU time (`viewport_get_measured_render_time_gpu`) | **Changes every frame** (13.8 ms here, ≈ the frame time) | Per-frame GPU column. This PC is GPU-bound at high |
| Measured render CPU time | 1.0 ms per frame | Per-frame column |
| Draw calls, triangles, objects (`viewport_get_render_info`, `RENDER_TOTAL_*`) | Per frame, main and shadow pass separately | Per-frame columns |
| Shader-compile counters (`PIPELINE_COMPILATIONS_*`) | **Add up** over the run (never fall). Almost no new compiles, because the shader cache was already warm | Use the change from the previous frame; record cache state |
| Jolt physics counters (`PHYSICS_3D_ACTIVE_OBJECTS`, pairs, islands) | **Always 0**, even with 20 boxes awake | Our own awake-body counters in items, boat, NPC bodies |
| Navigation counters | All 0 in the terrain scene (no navigation there) | Check again in the NPC scene |
| Does hiding Terrain3D remove its drawing? | **Yes**: −37 draw calls, −91 shadow draw calls, −256 k triangles, **−4.2 ms GPU** at that view | Terrain switch = `visible`, verified by draw calls. Terrain3D also has `cast_shadows` and `collision_mode` for finer switches |
| Frame-profile functions (`get_frame_profile` etc.) | **Not available** to scripts | — |
| GPU timestamps (`RenderingDevice.get_captured_timestamp_*`) | Normally only 2. **With `--gpu-profile`: 60 named timestamps every frame**, readable from the script, with no visible extra cost (13.70 vs 13.77 ms GPU, one run each) | **Per-pass GPU time on every frame** from the script, better than the once-a-second printout. Moves forward from step 10 |
| `--gpu-profile` printout | Works, once a second, per pass | Not needed if the timestamps are read directly |
| Stopwatch cost (debug build) | On: **1.08 µs** per begin/end pair. Off: **0.5 µs** (the function call itself). Plain clock: 0.12 µs | Keep zones coarse: about 90 pairs per frame cost 0.1 ms. Try the on/off check at the call site, which should make "off" much cheaper (to be measured in step 8) |

## Graphics-card time per pass (steady view at the centre, high preset)

From the `--gpu-profile` run, ms per frame:

| Pass | ms |
|---|---|
| Opaque pass (terrain, grass, trees, objects) | 8.6–9.0 |
| Depth pre-pass | 1.9–2.1 |
| Sky | 1.25–1.3 |
| Directional shadows | 0.88–0.98 |
| Tonemap | 0.41–0.44 |
| Canvas (2D overlay) | 0.12–0.13 |
| Transparent pass | 0.11–0.13 |
| **Total** | **13.3–14.0** |

So on this PC the graphics card is the limit, and two thirds of its time is
the opaque pass. Switching parts off (steps 5–6) will split that pass up by
feature (terrain alone was 4.2 ms of it at the test view).

## Changes to the plan

1. The recorder uses our own frame-edge stopwatches, not the `TIME_*` monitors.
2. Per-pass GPU time comes from the captured timestamps in a `-GpuProfile`
   run, every frame. This moves part of step 10 forward.
3. Physics: own awake-body counters, since Jolt reports 0.
4. Shader compiles: frame-to-frame difference of the counters.
5. Stopwatches stay coarse; step 8 measures whether an on/off check at the
   call site (`if BenchZones.on: BenchZones.begin(...)`) is cheaper.
