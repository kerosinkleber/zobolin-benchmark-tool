# Zobolin Benchmark Tool

Measures what each part of the Zobolin game costs (graphics card, processor,
physics, stutters) and ranks the biggest costs. See `PLAN.md` for the plan
and `findings/` for what it found.

Licence: GPL-3.0-or-later (see `LICENSE`).

## Status

Steps 1 to 11a are built (see `PLAN.md`): the one command, switching parts
off (graphics card and processor), stopwatches in the game's systems,
stutter blame, sweeps (more NPCs, items, cargo), micro benchmarks, the
report page, baselines and the comparison between PCs. Step 11b (using it
on the i9 PC and the laptop) is for you; step 12 (a live in-game table) is
optional and not built.

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
