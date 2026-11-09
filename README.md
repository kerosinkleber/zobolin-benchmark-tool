# Zobolin Benchmark Tool

Measures what each part of the Zobolin game costs (graphics card, processor,
physics, stutters) and ranks the biggest costs. See `PLAN.md` for the plan
and `findings/` for what it found.

Licence: GPL-3.0-or-later (see `LICENSE`).

## Status

Every step of `PLAN.md` is built: the one command, switching parts off
(graphics card and processor), stopwatches in the game's systems, stutter
blame, sweeps (more NPCs, items, cargo), micro benchmarks, the report page,
baselines and the comparison between PCs, the i9/laptop run (step 11b) and
a live cost table in the game (step 12, F4). Public repository:
https://github.com/kerosinkleber/zobolin-benchmark-tool

## Running it

1. Close other programs; don't use the PC while it runs.
2. Open PowerShell in this folder (in Explorer: click the address bar,
   type `powershell`, press Enter).
3. Type this and press Enter:

       powershell -ExecutionPolicy Bypass -File zbench.ps1

   The game window opens and closes three times (about half a minute
   each, with 20 s breaks). At the end you see a table: for each view the
   frame time, how much the three runs differed, the graphics card's time
   and the stutters per run, and where the processor time goes.
4. Open `report.html` in the session folder (the last line says where):
   the same results as a page, with charts and plain-words explanations.
   It opens in any web browser, also without internet.

### Options (add them after `zbench.ps1`)

| Option | What it does |
|---|---|
| `-Scenario flight` | The flight across the whole world: stutters and what causes them (re-centring, new trees and tiles) |
| `-Scenario npc_crowd -Repeats 2` | The NPC test with 8, 24 and 64 NPCs, and how their cost grows (about 45 minutes) |
| `-Scenario items` | The items test with 300, 1000 and 3000 items, and how their cost grows |
| `-Scenario boat_cargo` | The boat with 0, 13 and 26 crates of cargo, and how their cost grows |
| `-Scenario vista` | All 11 terrain views instead of the quick 3 (`vista_quick`) |
| `-Scenario forest_lowpass` | Low (30 m) and fast over the densest forest for 2 km: near trees, trunk collision and grass keep coming |
| `-Scenario village_walk` | To the house's door, in and out again (its light and lamps); with `-Ablate` the lamps are switched off once |
| `-Scenario storm_noon` / `storm_night` / `snow` | The 3 quick views in a storm (a loud lightning strike every 5 s) at noon or at 23:00, or in snow |
| `-Scenario time_fast` | The 3 quick views with the game time running 600 times faster (an hour every 6 s) |
| `-Scenario load` (add `-ColdCache`) | The start-up: how long until the first view, and where the time goes; `-ColdCache` first clears Godot's compiled shaders, graphics pipelines and tree pictures (only those) |
| `-Scenario boat -Ablate` | The boat scene with and without drawing the water, with only its coarse pieces (`water_mesh`) and with no shadows on it (`water_shadows`) |
| `-Scenario storm` | A storm with fully wet surfaces (7c), at the centre, valley floor, village, lake shore and market stall; with `-Ablate` also what rain (`precipitation`), the wet look (`wet`) and the lake (`lake`) cost |
| `-Scenario low_7c -Preset low -Ablate -Kind gpu` | What 7c's parts cost on the low preset (lake, grass, trees, houses and rocks, ground); `low_parts` is the same without the lake, for game versions before 7c |
| `-Ablate` | Also once with each part off (shadows, grass, houses and rocks, trees, ground, sky, fog, and the pieces: far tree pictures, the ground's, near trees' and houses' shadows) and once with the parts all off, then a table of what each part costs; then the processor switches (physics, updates, day and night, panel, re-centring, collision, ImGui) and a table of processor time saved. Three rounds of 21 runs: about 35 minutes |
| `-Ablate -Kind gpu` / `-Kind cpu` | Only the graphics card's switches (about 21 minutes) or only the processor's (about 15 minutes) |
| `-Repeats 5` | Five runs instead of three |
| `-Preset low` | The low graphics preset |
| `-Gpu intel` | The built-in graphics (the low tier on the i9) |
| `-GpuProfile` | Also the graphics card's time per drawing pass |
| `-CoolDown 60` | A longer break between runs (laptops) |
| `-SaveBaseline` | Keep this session as this PC's baseline (see below) |
| `-Baseline <summary.json>` | Compare with this session instead of the saved baseline |
| `-GameOptions "--grass-end=300"` | Options for the game itself (several in one string, separated by spaces) |

Results go to `results\<date>_<pc>_<commit>_<scenario>\`: one folder per
run (`r1`, `r2`, ...; with several variants `<variant>\r1`, ...),
`summary.json` with the combined numbers and `report.html`. The `results`
folder isn't committed.

### When does a difference count?

- **A part's cost** (switching it off) counts if it is bigger than the noise:
  how much the repeats differed, but never less than 1.5 %. Smaller ones are
  marked `*` ("inside the noise").
- **A change against a baseline** counts only if it is over 5 % and
  outside the noise, each number with its own noise.
- **A disturbed run** gets a WARNING. That happens when the frames waited
  more than 3 ms for something that is neither the game's graphics work
  nor its scripts, which usually means another program was using the
  graphics card. Close other programs and run again; `-SaveBaseline`
  won't save such a session.

### The live cost table (in the game)

In the terrain test, press **F4**: a window shows, averaged over the last
second, the frame time, the graphics card's time, Godot's main-loop and
physics time, and every stopwatch (what each system's scripts cost), with
the table's own cost as `bench_panel`. `-- --bench-panel` on the command
line opens it at the start. It is for looking around; the tool's runs are
what count.

### Baselines and comparing PCs

    powershell -ExecutionPolicy Bypass -File zbench.ps1 -SaveBaseline

keeps the session as this PC's baseline, in
`baselines\<pc>\<scenario>_<preset>_<renderer>_<graphics card>.json`. Every
later session of the same kind is compared with it: "faster", "slower"
(red) or "no change" per view. Commit the `baselines` folder to share it.

    powershell -ExecutionPolicy Bypass -File compare_pcs.ps1 -Scenario vista_quick

puts every PC's baseline of a scenario side by side, each against 60 frames
per second (the target of all three tiers).

### Other things

- Work out a finished session again without running the game (for example
  after a change to the statistics):

      powershell -ExecutionPolicy Bypass -File zbench.ps1 -Reanalyse results\<session folder>

  The earlier `summary.json` is kept as `summary.previous.json`.
- Make a session's report page again: `powershell -ExecutionPolicy Bypass -File report.ps1 results\<session folder>`.
- If it stops with "The frame rate is capped", vsync or a frame limit is on
  in the graphics driver: switch it to "use the application setting" and
  run again.
- A run that hangs (for example after a script error in the game) is
  stopped after 15 minutes; the game's launcher takes `-TimeLimit <seconds>`.

## In the game's folder

From `C:\Claude\Open World Game - Zobolin`, the game's launcher runs single
tests (the tool uses it):

    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Test engine
    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Test micro -Extra "--quick"

- `-Test engine`: which of Godot's measuring tools work (step 1).
- `-Test micro`: the micro benchmarks, without a window: NPC route finding,
  record loading, clock jumps with many NPCs (step 9c).
- `-OutDir <folder>` writes the results there; don't end the folder name
  with `\` (Windows PowerShell then mixes up the options after it).
- `tools\benchmark_low_tier_intel.bat` (the i9 and the laptop) runs the
  old low-tier checks and then this tool, if it is next to the game's
  folder; `tools\i9_test_session_prompt.md` is the prompt for a measuring
  session there.

## On another PC

Clone this repository next to the game's folder (the same parent folder):

    git clone https://github.com/kerosinkleber/zobolin-benchmark-tool "Zobolin Benchmark Tool"

`zbench.ps1` finds the game folder `Open World Game - Zobolin` next to it
(or give `-Game <folder>`). Save a baseline there with `-SaveBaseline` and
commit the `baselines` folder, so `compare_pcs.ps1` can show every PC.
