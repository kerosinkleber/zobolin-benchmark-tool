# Zobolin Benchmark Tool: plan

Goal: measure what every part of Zobolin costs, and rank which parts use the
most processor time, graphics-card time, and which cause stutters.

Status: the owner accepted the recommended decisions in section 8
(2026-11-08). **Step 1 is done** (2026-11-08); its results are in
`findings/01-engine-check.md` and change the plan in five places (listed
there). Corrections from the first fact-check pass are
marked ✱. **Step 2 is done** (2026-11-08): `game/benchmark/bench_stats.gd`.
**Step 3 is done** (2026-11-08): `game/benchmark/bench_recorder.gd`, see
`findings/03-recorder.md`. **Step 4 is done** (2026-11-08): `zbench.ps1`,
see `findings/04-runner.md` and the README. **Step 5a is done**
(2026-11-08): `zbench.ps1 -Ablate`, see `findings/05a-switches.md` (first
cost ranking: ground 4.4 ms, trees 3.1, shadows 2.2, grass 2.2 on the
GTX 970). **Step 5b is done** (2026-11-08): sky, fog and shadows by
caster, see `findings/05b-switches.md`. Water and house lamps wait for
their scenarios (boat, house). The noise floor is now 1.5 % (decision 5,
2026-11-08), and `zbench.ps1 -Reanalyse <folder>` works out a finished
session again. **Step 5c is done** (2026-11-08): processor and physics
switches, see `findings/05c-cpu-switches.md` (the processor does 0.5 ms
per frame, 0.31 ms of it Jolt's step). Its "re-centring makes the graphics
card slower" turned out to be the grass vanishing without re-centring; the
processor switches are now also checked by comparing screenshots
(`lib/Pictures.psm1`).

**Steps 6 to 11a are done** (2026-11-08), see the table in section 7 and
`findings/07` to `findings/10`. After step 9 an independent review (four
reviewers and a verifier) found 24 problems; all were fixed and the sweeps
measured again (`findings/10-review.md`).

**Steps 11b and 12 are done too** (2026-11-08): the tool is on GitHub
(https://github.com/kerosinkleber/zobolin-benchmark-tool) and was run on the
i9's built-in graphics (Intel UHD 770; `baselines/DESKTOP-PK8LI3N`, the game's
`measurements/i9-low-tier.md`); the i7 7700K + GTX 1050 run is under way in
its own session. The live cost table is in the terrain test (F4). The last
scenarios of section 5 are built and measured (`findings/11-scenarios.md`).
Every step of this plan is built.

---

## 1. How this is done (short explainer)

**A frame has two halves running at the same time.** The *processor (CPU)*
runs scripts and physics and prepares the list of things to draw. The
*graphics card (GPU)* draws it. The frame takes as long as the slower half.
When the graphics card is the slower half, the frame is *GPU-bound*; when the
processor is slower, it is *CPU-bound*. So "what costs most?" has two answers,
and the tool first says which half is the limit.

There are four ways to measure:

| Method | What it is | Good for | Limit |
|---|---|---|---|
| **Stopwatches** (instrumentation) | A timer around a piece of our code: "forest update took 0.4 ms" | Processor time of *our* scripts, named per system | Only our own code, only processor time |
| **Switch off and measure again** (ablation) | Run the same camera route with grass on, then off. The difference is what grass costs | The **only** way to get graphics-card cost per feature, and to measure Terrain3D (compiled add-on) | Systems affect each other, so the savings don't simply add up |
| **Engine counters** | Godot's own numbers: physics time, draw calls, triangles, GPU total | Cheap overall picture | Totals only, not per system |
| **Sampling / outside tools** | A program (Tracy, PIX, RenderDoc) watches the game from outside | Deep dives on one suspect | Manual; Tracy needs a custom-built Godot |

**How results are read:**
- **Milliseconds, not fps.** 60 fps = 16.7 ms per frame. Milliseconds can be
  added up ("grass costs 3.5 ms"); fps can't.
- **Percentiles.** p50 = the typical frame; p99 = the slowest 1 in 100.
  Averages hide stutters, percentiles show them.
- **Hitches (stutters).** One frame much slower than its neighbours (today's
  rule: over 33.3 ms). Each hitch is logged with the time, the camera position
  and what happened on that frame (e.g. "terrain re-centred").
- **Noise.** Two identical runs never give identical numbers (heat, clock
  speeds). Each run is repeated 3 times and the middle value is used; a
  difference smaller than the run-to-run spread counts as "no change".

---

## 2. What Godot 4.7.2 gives us, and its limits

| Feature | Gives | Limit |
|---|---|---|
| Measured render time (`RenderingServer.viewport_get_measured_render_time_gpu/cpu`) | Total GPU ms and render-prep CPU ms. Already used today | One total, no split by feature; arrives 1–2 frames late |
| `Performance` monitors | Main-loop time ✱, physics tick time, navigation, draw calls, triangles, shader compiles, video memory | ✱ `TIME_PROCESS` is the whole main-loop step, not "script time". ✱ Some monitors refresh with up to ~1 s delay, so they're not per-frame values |
| Custom monitors | Our stopwatch values show in the editor's Debugger graphs | Display only; nothing is saved |
| `--gpu-profile` launch flag | GPU ms per drawing pass (shadows, opaque, transparent, sky, post) once a second | By pass, not by feature (grass and terrain are both "opaque"). ✱ Has its own cost, so it gets its own separate run |
| Editor profiler | Top script functions | Needs the editor attached; hard to automate |
| Tracy/Perfetto (since 4.6) | Full timeline of engine + scripts | Needs a custom-compiled Godot. Not now |
| RenderDoc / PIX / Nsight | Cost per single draw call | Manual, one frame at a time |

Not available from a script at all: GPU time per feature, and the editor
profiler's per-function data. That's why the plan relies on **switch-off runs
for the graphics card** and **our own stopwatches for the processor**.

✱ All runs use the editor binary (a debug build), so script numbers are higher
than in a shipped game. The build type is recorded with every result; a
`-Release` mode with an exported build can come later.

---

## 3. Tool architecture

### Components
1. **Runner – `zbench.ps1`** (this folder). The one command you run. Builds
   the run list (everything on, each switch off, everything off, × 3 repeats),
   runs them interleaved (A B C A B C, with a short cool-down) so heat affects
   all variants equally, stamps the PC details and the game commit, combines
   the results, compares them with saved baselines and writes the report.
2. **Launcher – `tools\benchmark.ps1`** (game repo). Extended, not copied.
   New options: `-Extra` (pass settings to the game), `-Out`, `-Scenario`,
   `-GpuProfile`.
3. **In-game recorder.** One row per frame: real frame ms, GPU ms, render CPU
   ms, main-loop and physics ms (✱ measured with our own timers at the frame
   boundaries, not the delayed monitors), physics ticks this frame, draw calls
   (main and shadow), triangles, shader compiles, video memory, camera
   position, event counts and stopwatch values.
4. **Stopwatches ("zones").** One-line `begin`/`end` calls in each system,
   off by default (then each costs one yes/no check). Many-copy systems
   (items, doors, NPC bodies) share one zone.
5. **Event counters.** Tiny counts like "terrain re-centred", "tree block
   built", "far-object tiles rebuilt", "game hour changed", "blocks freed".
   These name the cause of almost every stutter.
6. **Switches.** One `--off=grass,trees_far,…` setting. Each switch declares
   what it removes (drawing only, or the script work too) and how it is
   verified (screenshot difference, draw-call difference, or a counter).
7. **Scenarios.** Fixed, repeatable routes: fixed seed, time stopped, weather
   held, vsync off, no fps cap. Each waits until shader compiles and
   background loading have stopped before measuring.
8. **Report.** One HTML file that opens offline.

### Folder layout (as built)
```
C:\Claude\Open World Game - Zobolin\     (only what must run inside Godot)
  tools\benchmark.ps1                     the launcher: -Record, -OutDir, -Extra,
                                          -GpuProfile, -TimeLimit, -Test micro|engine
  game\benchmark\bench_stats.gd           percentiles, 1% low, stutters, noise, frame cap
  game\benchmark\bench_recorder.gd        per-frame rows -> frames.csv + run.json,
                                          event counters (event_sources), stutter blame
  game\benchmark\bench_zones.gd           stopwatches
  game\benchmark\terrain_cpu_switches.gd  processor and physics switches + counters
  game\benchmark\micro_bench.gd           micro benchmarks without a window
  game\benchmark\engine_check.gd          step 1's check of Godot's tools
  game\prototypes\terrain\terrain_benchmark.gd   views, flight, --off= drawing switches
  game\prototypes\npcs|items|boat\*       their checks record with --record, and take
                                          --npcs= / --items= / --cargo=
  game\world, npc, vehicles, player       one-line stopwatches and event counters
  game\tests\bench_*_test.gd and others   GdUnit4 tests

C:\Claude\Zobolin Benchmark Tool\         (this folder)
  zbench.ps1                              the one command
  report.ps1, compare_pcs.ps1             report page; PCs side by side
  lib\Stats.psm1 Report.psm1 Machine.psm1 Pictures.psm1
  scenarios\*.json                        vista_quick, vista, flight, npc_crowd, items, boat_cargo
  baselines\<pc>\<scenario>_<preset>_<renderer>_<graphics card>.json
  results\<date>_<pc>_<commit>_<scenario>\   raw runs + summary.json + report.html (not committed)
  findings\*.md                           what each step found, with raw summaries
  README.md
```
Scripts that run inside the game must live in the game repo (Godot only loads
them from inside the project, and the stopwatches sit inside `forest.gd` etc.).
The recorder is a node added only for benchmark runs, not an autoload, so
`project.godot` and normal play stay unchanged.

---

## 4. Measurement map

**Z** stopwatch · **C** counter · **M** engine monitor · **A** switch-off · **P** per-pass GPU printout

| System | Measured by | Expected cost |
|---|---|---|
| Terrain drawing (Terrain3D) | **A** terrain (✱ via Terrain3D's own toggles, confirmed by draw-call delta), shader variants; **P** opaque | GPU, probably top 2 |
| Terrain re-centring (`TerrainWorld.recentre`) | **Z** with sub-zones; **C**; ✱ blame window = that frame + 2 (follow-on physics cost) | Stutter, 21–29 ms, ~7 per flight |
| ✱ Terrain3D collision around the player | **M** physics time + **C** in walk/flight | Physics |
| Grass (~200k clumps) | **A** grass + distance sweep 100/200/300 m; **Z** tile placement | GPU, top 2 (~3.5 ms at 5K) |
| Far tree pictures (impostors) | **A** trees_far | GPU |
| Near 3D trees, block building | **A** trees_near, tree_shadows; **Z** `forest` update; **C** blocks made / ✱ freed | GPU + stutter |
| Trunk collision | **A** trunks; **Z**; **M** bodies | Physics stutter |
| Far objects (4 bands) | **A** objects; **Z**; **C** tiles made | Stutter, some GPU |
| Shadows | **A** shadows, ✱ split by caster: terrain / trees / far objects; **M** shadow draw calls; **P** | GPU, large |
| Sky shader + updates every 0.1 s | **A** sky, sky_updates; **P** sky | GPU, medium |
| ✱ Water surface (`water_surface.gdshader`, `WaterVolume`) | **A** water; **Z** | GPU near shore |
| ✱ Post-processing (fog, glow, SSAO etc., downscale) | **A** post, ssao… (whatever the graphics preset enables); **P** post | GPU |
| Day/night + weather blending | **A** daynight; **Z** `update_now` (✱ incl. season parsing) | CPU, small |
| Rain/snow, lightning | Weather held clear / rain / snow / storm | GPU (transparency) |
| Lighting zones, ✱ house lamps | **A** zones, lamps; **Z**; **C** | CPU + GPU |
| Spawn queue | its own existing ms counter | CPU, capped at 2 ms |
| NPC detail levels, schedules, route finding | **Z** per tier, `best_way`, Dijkstra; **C** level changes, new hour; **A** NPC count 0/8/16/32/64 | CPU, likely future hotspot |
| NPC bodies (walking, avoidance) | **Z** physics + `move_and_slide`; **M** navigation | CPU / physics |
| Navmesh baking | **Z** load rows | Loading stutter |
| Loose items, buoyancy | **Z** shared; **M**; ✱ own awake-body counter if Jolt reports 0; **A** count 300/1000/3000 | Physics |
| Boat + cargo | **Z**; **A** cargo 0/13/26 (one layer) | Physics scripts |
| Doors, player, grabber | **Z** shared | Small |
| Game clock jumps | **Z**; headless micro test | Spike, grows with NPCs |
| Records, save/load | **Z** load rows; micro test 1k/10k/100k records | Loading time |
| ImGui, overlay, the tool itself | hidden while measuring; **Z** | ~0.6 ms claimed for ImGui |
| ✱ Video memory | **M** texture + buffer memory; warn above ~3.3 GB (GTX 970) | Ceiling |
| ✱ Physics catch-up | physics ticks per frame are part of hitch blame | Multiplies physics on slow frames |
| Unattributed remainder | ✱ main-loop ms − render CPU − our process-side zones | Engine, Terrain3D, untimed code |

---

## 5. Scenarios

Built (scenario files in `scenarios\`):

| Name | What it does | Stresses |
|---|---|---|
| `vista_quick` | 3 of the views (centre, valley floor, village close), 3 s each; the everyday run | Steady GPU load |
| `vista` | The 8 fixed views + 3 village views, 3 s each (the planned 10 s was not needed: repeats agree within 1.5 %) | Steady GPU load; main switch-off target |
| `flight` | The flight x −4080 → 4080, moving a fixed distance per frame (`--fixed-flight`) so every PC visits the same positions | Re-centring, streaming stutters |
| `npc_crowd` | Villagers with 8, 24 and 64 NPCs: their day, the 07:00 rush, an 8-hour clock jump (about 7 min a run, so 2 repeats) | NPC CPU, navigation |
| `items` | 300, 1000 and 3000 items: adding, settling, at rest, all thrown, floating on waves | Jolt physics, buoyancy |
| `boat_cargo` | 0, 13 and 26 crates on deck (one layer: stacked cargo isn't re-stowed after loading, a game bug for the owner) | Cargo code |
| `micro` (the game's `-Test micro`) | Without a window: route finding with 10/100/1000 places, records, clock jumps with 0/100/1000 NPCs | Future hotspots |

| `forest_lowpass` | 2 km at 30 m over the densest row of tree blocks, 60 m/s fixed | Near trees, trunk collision, grass streaming |
| `village_walk` | To the house's door, in and out (switch: `lamps`) | House light and lamps |
| `storm_noon` / `storm_night` / `snow` | The quick views in a storm (lightning every 5 s) at noon or 23:00, or in snow | Weather drawing and scripts |
| `time_fast` | The quick views with time 600 times faster | Day-and-night updates |
| `load` | The start-up (with `-ColdCache`: shaders, pipelines and tree pictures cleared first) | Loading, shader compiling |
| `boat` | The boat scene (switch: `water`) | Water surface, buoyancy |

Run lengths on the development PC: `vista_quick` 3 runs about 2 min;
`-Ablate` on `vista_quick` about 35 min; `npc_crowd` about 45 min.

---

## 6. Output

Per run: `frames.csv` (one row per frame) and `run.json` (summary per
segment: frame ms p50/p95/p99/max, 1% low, GPU ms, GPU-bound share, CPU split,
counts, zones, unattributed ms, hitches with causes, load times, warm-up,
video memory, and PC/build/thread-model/cache-state details). The old
`results.json` files stay as they are, so existing checks keep working.

Per session: `summary.json` (medians, noise band, each switch's saving) and
**`report.html`**:
1. **Verdict in plain words** – e.g. "This PC is held back by the graphics
   card in 82 % of frames. The biggest stutters come from re-centring."
2. **Top costs table** – every system in one list, sorted by ms: resource
   (GPU / CPU / physics / stutter), ms, % of the 16.7 ms budget, confidence
   (outside noise or not), how measured, red mark if over its own budget.
3. Frame-time chart per scenario with hitch marks (hover shows the cause).
4. Hitches grouped by cause.
5. CPU vs GPU per view (✱ shown as "critical path", not a stacked sum, since
   the halves run in parallel), load-time table.
6. Warning when systems clearly affect each other.
7. Comparison with the baseline (green/red only outside the noise band), and
   PCs side by side (GTX 970 high, UHD 770 low, HD 630 low) each against its
   own target. This replaces typing up `measurements\*.md` by hand.

---

## 7. Build plan (small steps, each with a check)

Every step also passes the three standard checks from the game's CLAUDE.md
(import, one-frame run, GdUnit4 tests).

| Step | Deliverable | Check |
|---|---|---|
| 0 | Owner's decisions (section 8); entry in the game's `PLAN.md`; this folder set up | Owner says yes |
| 1 ✅ 2026-11-08 | **Engine check**: a run prints which 4.7.2 numbers really work (Jolt physics counts, shader compiles cumulative or per frame, which monitors refresh every frame, `--gpu-profile` format, thread model) | Done: see `findings/01-engine-check.md`. Per-pass GPU time per frame is readable in `-GpuProfile` runs, so part of step 10 moves forward |
| 2 ✅ 2026-11-08 | `bench_stats.gd` + tests | Done: 11 tests pass; average fps, slowest 1 % and slowest frame match `_summarise` exactly on four made-up runs (50–3000 frames) |
| 3 ✅ 2026-11-08 | Recorder on terrain views → `frames.csv` + `run.json` (`benchmark.ps1 -Record`) | Done: frame ms within 0.5 % of the real clock and of the benchmark on 3 views; CPU columns not 0. With `-GpuProfile` it also records per-pass GPU time every frame (sum within 3 % of GPU ms) |
| 4 ✅ 2026-11-08 | `benchmark.ps1` options (`-OutDir`, `-Extra`; scenarios live in the tool's `scenarios\*.json`, so no `-Scenario` there) + `zbench.ps1` with repeats, PC stamp, shared vsync/fps-cap detector (fails the run if capped) | Done: 3 repeats agree within 1.4 % on the GTX 970; a run held at 60 fps was refused |
| 5a ✅ 2026-11-08 | Switches mapped to existing flags (`--off=shadows,grass,objects,trees,pictures,terrain`) + `zbench.ps1 -Ablate` (all on, each off, all off, in turns) | Done: every switch took away draw calls or triangles on every view (verified by counts, not screenshots) |
| 5b ✅ 2026-11-08 | New GPU switches: sky, fog, shadows by caster (ground, near trees, nearest houses and rocks); parts vs pieces (`detail_switches`) so nothing is counted twice. Water and lamps moved to the boat and house scenarios (not in the outdoor views); the high preset has no glow or SSAO | Done: 10 switches drew less, the sky held its setting and saved time; fog held but saves less than the noise |
| 5c ✅ 2026-11-08 | CPU/physics switches in the terrain test (world updates, day and night, panel, Jolt's step, re-centring, ground and trunk collision, ImGui; the update ones act only while a view is measured) + `physics_ms` column + `zbench.ps1 -Kind cpu`. NPC and item switches move to steps 9a/9b with their scenarios | Done: every counter showed the work stopped, in all 3 rounds |
| 6 ✅ 2026-11-08 (check partly not met) | Switch-off matrix on `vista` + `report.html` (built by agents, reviewed) | Report: done. Grass ≈ 3.5 ms: **not met**, it is 1.5 ms on average (3.2 at most): the 3.5 ms is from item 1b, before trees and with grass to 250 m (now 200 m). UHD 770: needs the i9 (11b). `findings/06-vista.md` |
| 7 ✅ 2026-11-08 | Event counters + stutter blame + the recorded flight (`--fixed-flight`, scenario `flight`) | Done: 6 stutters per flight under re-centring at the 1024 m lines (the 7th re-centre falls on a screenshot frame); `findings/07-stutters.md` |
| 8 ✅ 2026-11-08 | Stopwatches (`BenchZones`) in the world systems + unattributed rows | Done: 1.6 µs per pair on, 0.24 off (about 0.025 ms per frame); the re-centre pieces add up to the game's own timing within 0.1 %; `findings/08-stopwatches.md` |
| 9a ✅ 2026-11-08 | NPC recording, stopwatch, events, `--npcs=` + scenario `npc_crowd` (8/24/64) | Done: processor time grows along a straight line (fit 100 % in every phase), the 07:00 rush is the dearest phase (0.026 ms per NPC); `findings/09-sweeps.md` |
| 9b ✅ 2026-11-08 | Items and boat recording, stopwatches, events, `--items=` / `--cargo=` + scenarios `items`, `boat_cargo` (doors: no separate scenario, they cost too little to see) | Done: the normal items and boat checks pass as before; 3000 moving items take 38 ms of physics; `findings/09-sweeps.md` |
| 9c ✅ 2026-11-08 | Micro benchmarks without a window (`tools\benchmark.ps1 -Test micro`) | Done: they run headless and finish (`MICRO DONE`); route finding is the future hotspot; `findings/09c-micro.md` |
| 10 ✅ 2026-11-08 | `-GpuProfile`: per-pass GPU time every frame (built in step 3) | Done: the passes add up to within 3 % of the GPU total on every view (`findings/10-gpu-passes-gtx970-summary.json`) |
| 11a ✅ 2026-11-08 | Baselines (`-SaveBaseline`), comparison, `compare_pcs.ps1` | Done: the same commit shows "no change" on every view; grass to 300 m shows "slower" on every view (+7 to +10 %), processor "no change" |
| 11b ✅ 2026-11-08 | Use it on the i9 and the laptop: public GitHub repository; run by a session on the i9 (UHD 770, both renderers) and one on an i7 7700K + GTX 1050 | Done on the i9: graphics-card bound (94-100 % of frames with Forward+), 0 of 3 views at 60 with Forward+, 1 with Mobile; baselines committed. i7: in its own session |
| 12 ✅ 2026-11-08 | Live in-game cost table (ImGui, F4 or `-- --bench-panel`); Tracy not built (the stopwatches and switches were enough so far) | Visible, its own cost shown as `bench_panel` (about 0.15 ms) |

Steps 1–7 already answer the main question for terrain, flight and forest.

---

## 8. Decisions for the owner

| # | Question | Recommendation |
|---|---|---|
| 1 | May small one-line hooks go into the game repo (`game/benchmark/` + probes in forest, grass, terrain_world, day_night, npcs…)? | **Yes** – they do nothing unless the benchmark setting is given |
| 2 | Recorder as a global autoload, or a node added only in benchmark runs? | **Benchmark-only node** – normal play unchanged |
| 3 | Is this folder its own git repo (GPL-3.0), with baselines and reports committed here? | **Yes** |
| 4 | PowerShell only, or also Python? | **PowerShell only** – nothing to install on the i9 or laptop |
| 5 | Thresholds: hitch > 33.3 ms or > 2× typical; noise band ~~3 %~~ **1.5 %** (wider per PC if needed); alarm at > 5 % and outside noise | **Accepted. Noise floor lowered to 1.5 % on 2026-11-08** (owner's choice): repeats on the GTX 970 agree within 0.7 % |
| 6 | Default run length | **The quick scenario (`vista_quick`) everyday, the full ones before milestones** |
| 7 | Custom Godot build with Tracy? | **Not now** |
| 8 | Make this a side item in the game's `PLAN.md` now? | **Yes** – steps 1–7 directly help the current 60 fps checks |
| 9 | Install RenderDoc/PIX? | **Later**, at step 10, only if needed |

## Risks
- Switch-off savings don't simply add up (systems interact) → the report
  shows the everything-off floor and an interaction warning.
- Hidden ≠ gone: hiding stops drawing, not script work → each switch says
  which it removes.
- GPU time is late and noisy → uncapped runs, medians, noise band, 2-frame
  blame window, skip 2–3 frames after each screenshot.
- Compiled parts (Terrain3D, Jolt, navigation, worker threads) can't be timed
  from inside → measured around their calls, by counters and by switching off.
- Shader and picture caches on disk make the first repeat different → cache
  state recorded; first repeat discarded or `-ColdCache` used deliberately.
- Laptops and Intel graphics vary with heat and power → power plan, battery
  and elapsed time recorded; cool-down between runs.
