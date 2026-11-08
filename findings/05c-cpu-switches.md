# Step 5c: switches for the processor and physics (2026-11-08)

New in the terrain benchmark's `--off=` (`game/benchmark/terrain_cpu_switches.gd`):

| Switch | What stops | When | Counter that proves it |
|---|---|---|---|
| `world_updates` | updating trees, grass and far objects | while a view is measured | their new `process_calls` stay still |
| `daynight` | day, night, weather, rain, lightning | while measured | DayNight's cloud timer stays still |
| `overlay` | the information panel | while measured | the panel's text stays the same |
| `physics_engine` | Jolt's physics step | while measured | a probe ball, falling freely high above the world, stays put |
| `recentre` | re-centring the world | whole run | no re-centre during the views |
| `terrain_collision` | the ground's collision | whole run | collision mode 0, and a ray down no longer hits the ground |
| `trunk_collision` | the tree trunks' collision | whole run | no trunk bodies, while near trees still exist |
| `imgui` | the ImGui layer | whole run (removed) | ImGuiRoot gone |

**Why some act only while a view is measured.** In the terrain test, the
real update work (new trees, grass tiles and far-object tiles) happens just
after the camera jumps, while the view settles. Switching it off for the
whole run would leave the new views without trees or grass, which changes
the drawing too. So each view settles with everything running, the work
stops for the 3 s measurement, and then it runs again. (Four agents mapped
the work and a fifth checked their plan; it caught this and three switches
that would not really have stopped.)

The recorder has a new `physics_ms` column: the time from the first physics
step of a frame to the start of that frame's scripts, so all
`_physics_process` scripts plus Jolt's own step. Physics runs on about 9 of
10 frames here, so the tool uses averages (new `mean` in `run.json`), not
the middle frame. These switches are judged on **processor time per frame**
(scripts plus physics), not frame time, because the frame waits for the
graphics card either way.

    powershell -ExecutionPolicy Bypass -File zbench.ps1 -Ablate -Kind cpu

Raw summary: `05c-cpu-switches-gtx970-high-summary.json`.

## What each part costs on the processor (GTX 970 PC, Ryzen 7 1800X, high preset)

Processor time saved per frame, ms, middle value of 3 rounds. \* = inside the noise.

| Part | centre_north | valley_floor | village_close | Average |
|---|---|---|---|---|
| *(all processor time, everything on)* | 0.453 | 0.512 | 0.538 | 0.50 |
| Jolt's physics step | 0.271 | 0.320 | 0.342 | **0.311** |
| Day, night and weather updates | 0.047 | 0.053 | 0.052 | 0.051 |
| World updates (trees, grass, far objects) | 0.039 | 0.043 | 0.055 | 0.046 |
| Re-centring | 0.010\* | 0.041 | 0.050 | 0.034 |
| Information panel | 0.019 | 0.027 | 0.022 | 0.022 |
| Trunk collision | 0.008\* | 0.014 | 0.006\* | 0.010 |
| Ground collision | 0.008\* | 0.004\* | 0.005\* | 0.006 |
| ImGui | 0.005\* | −0.001\* | 0.011\* | 0.005 |

Every counter showed the work stopped in all three rounds. With everything
on, the same counters moved (for example 525–600 update calls per view, the
probe ball falling 76–156 m, 343–1071 trunk bodies).

## What it means

- **The processor is not what limits the terrain test**: about 0.5 ms of
  a 15–19 ms frame. The graphics card is the limit (steps 5a and 5b).
- **Most of the processor time is Jolt's step itself (0.31 ms)**, even
  though almost nothing moves. Switching off the ground's and the trunks'
  collision hardly changes it, so it is the step's fixed cost with this
  scene, in the debug build. It is worth watching once NPCs and items run
  in the same world (step 9).
- **All the scripts together cost about 0.15 ms per frame** while a view
  is held. Their real cost is the work right after a jump, which these
  views don't measure. The flight and the stutter blame (step 7) will.

## Corrected: re-centring does NOT make the graphics card slower

With re-centring off, the frame was 0.83 ms faster on average (up to
1.1 ms on the two views away from the centre), with the same draw calls
and triangles. This first looked like "something draws more slowly after
re-centring". It was not (looked into the same day):

- Per drawing pass (`-GpuProfile`), the extra time was in the depth pass
  (+0.3 ms) and the opaque pass (+0.4 to 1.0 ms).
- With the grass off, re-centring made no difference at all; with the
  ground off (more grass visible), the difference doubled. So: grass.
- The screenshots show why: **with re-centring off, the grass is gone**
  on views far from the centre. The grass shader looks up ground heights
  in Terrain3D's region map; without re-centring, those views lie 1.8 km
  from Godot's origin and the lookup finds no ground, so every clump is
  shrunk to nothing. The clumps are still sent to the graphics card, so
  draw calls and triangles stay the same.

So the "saving" was the grass not being drawn. In the game, re-centring
always runs and keeps the camera within about 1 km of the origin, so this
never shows. The re-centring switch still measures the processor saving
(0.034 ms), but its frame time can't be used.

**What changed in the tool because of this:** the processor switches are
now also checked by their **pictures**: each view's screenshot is compared
with everything on (shrunk to 160 × 90, the information panel left out).
Working switches and repeats differ by 0.0000; re-centring off by 0.008;
the limit is 0.002. Re-centring off is now reported as "NO: the picture
changed in valley_floor, village_close".

## Also found

- A parse error in a game script made the game wait forever instead of
  quitting, so the launcher waited too. The runner needs a time limit per
  run (noted for step 11).
- A PowerShell filter on Godot's error output hid that parse error. The
  import check now runs in Bash with `grep`, as in the game's CLAUDE.md.
