# Step 3: the recorder (2026-11-08)

`game/benchmark/bench_recorder.gd` writes one row per frame (`frames.csv`)
and a summary per view with the PC and settings (`run.json`, schema 2).
The terrain benchmark uses it with `--record`:

    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Only "centre_north,valley_floor,village_close" -Record
    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Only "centre_north,valley_floor,village_close" -Record -GpuProfile

Raw summary of the second run: `03-recorder-gtx970-high-run.json`.

## Check

The recorder's average frame time against the real clock over the whole
view, and against the benchmark's own number (GTX 970, high preset):

| View | Frames | Recorder | Real clock | Benchmark | Difference |
|---|---|---|---|---|---|
| centre_north | 202 | 14.88 ms | 14.88 ms | 14.87 ms | +0.1 % |
| valley_floor | 174 | 17.25 ms | 17.25 ms | 17.25 ms | 0.0 % |
| village_close | 162 | 18.61 ms | 18.61 ms | 18.58 ms | +0.2 % |

The limit was 5 %. The processor columns aren't 0: scripts 0.09 ms, drawing
(including waiting) 14–18 ms, render preparation about 1 ms, about one
physics step per frame. Every frame waited for the graphics card.

## Graphics card per pass (from the `-GpuProfile` run), typical frame, ms

| View | GPU total | Opaque | Depth pre-pass | Shadows | Sky | Tonemap | Other | Sum of passes |
|---|---|---|---|---|---|---|---|---|
| centre_north | 14.41 | 9.31 | 2.02 | 0.90 | 1.21 | 0.44 | 0.28 | 14.17 |
| valley_floor | 16.49 | 10.62 | 2.84 | 1.60 | 0.41 | 0.48 | 0.13 | 16.08 |
| village_close | 17.73 | 11.13 | 3.58 | 1.14 | 1.00 | 0.47 | 0.13 | 17.45 |

The passes add up to within 3 % of the total, so part of step 10 is done.

## Learned on the way

- Godot keeps its own options (like `--gpu-profile`) to itself: a script
  can't see them on the command line. The recorder notices the profile by
  its timestamps instead (about 60 per frame with it, 2 without).
- A benchmark run with `-Only` writes `results.json` into the same folder
  as a full run, replacing the full run's file. The numbers that matter
  are typed up in the game's `PLAN.md`, but step 4's runner must give each
  run its own folder.
