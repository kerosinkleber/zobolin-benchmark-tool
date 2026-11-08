# Zobolin Benchmark Tool

Measures what each part of the Zobolin game costs (graphics card, processor,
physics, stutters) and ranks the biggest costs. See `PLAN.md`.

Licence: GPL-3.0-or-later (see `LICENSE`).

## Status

Steps 1 to 5b are done (engine check, statistics, recorder, the one
command, switching parts off; see `findings/`). It does not yet write a
report page.

## Running it

1. Close other programs; don't use the PC while it runs.
2. Open PowerShell in this folder (in Explorer: click the address bar,
   type `powershell`, press Enter).
3. Type this and press Enter:

       powershell -ExecutionPolicy Bypass -File zbench.ps1

   The game window opens and closes three times (about half a minute
   each, with 20 s breaks). At the end you see a table: for each view the
   frame time, how much the three runs differed, the graphics card's time
   and the stutters.

Options (add them after `zbench.ps1`):

| Option | What it does |
|---|---|
| `-Ablate` | Also once with each part off (shadows, grass, houses and rocks, trees, ground, sky, fog, and the pieces: far tree pictures, the ground's, near trees' and houses' shadows) and once with the parts all off, then a table of what each part costs. Three rounds of 13 runs: about 21 minutes |
| `-Scenario vista` | All 11 terrain views instead of the quick 3 (`vista_quick`) |
| `-Repeats 5` | Five runs instead of three |
| `-Preset low` | The low graphics preset |
| `-Gpu intel` | The built-in graphics (the low tier on the i9) |
| `-GpuProfile` | Also the graphics card's time per drawing pass |
| `-CoolDown 60` | A longer break between runs (laptops) |

Results go to `results\<date>_<pc>_<commit>_<scenario>\`: one folder per
run (`r1`, `r2`, ...) and `summary.json` with the combined numbers. The
`results` folder isn't committed.

A change counts only if it is bigger than the noise band: how much the
repeats differed, but never less than 1.5 %.

To work out a finished session again without running the game (for
example after a change to the statistics):

    powershell -ExecutionPolicy Bypass -File zbench.ps1 -Reanalyse results\<session folder>

The earlier `summary.json` is kept as `summary.previous.json`.

If it stops with "The frame rate is capped", vsync or a frame limit is on
in the graphics driver: switch it to "use the application setting" and run
again.

## Engine check (step 1)

From the game folder `C:\Claude\Open World Game - Zobolin`:

    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Test engine

The game window opens, runs by itself for about a minute, and closes.
Results: `game\reports\benchmarks\engine\<preset>_<renderer>_<gpu>\engine_check.json`.
