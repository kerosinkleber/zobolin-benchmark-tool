# Step 5a: switching existing parts off (2026-11-08)

The terrain benchmark takes `--off=shadows,grass,objects,trees,pictures,terrain`
(the older `--grass=off` and so on still work). `zbench.ps1 -Ablate` runs
the scenario with everything on, with each part off, and with all of them
off, in turns, three rounds, and works out what each part costs.

    powershell -ExecutionPolicy Bypass -File zbench.ps1 -Ablate

Every switch stops only the **drawing**: the part's scripts and collision
keep running. So these costs are graphics card and drawing time.

Raw summary: `05a-switches-gtx970-high-summary.json`.

## What each part costs (GTX 970, high preset, 5120 × 2880 drawn)

Frame time saved when the part is off, middle value of 3 rounds, ms.
\* = inside the noise (smaller than the repeats' spread).

| Part | centre_north | valley_floor | village_close | Average | Fewer draw calls |
|---|---|---|---|---|---|
| Ground (Terrain3D) | 6.38 | 2.83 | 3.91 | **4.38** | 91–129 |
| Trees (near and far) | 1.67 | 3.41 | 4.15 | **3.07** | 100–107 |
| Shadows | 2.00 | 2.48 | 2.25 | **2.24** | 247–442 (all shadow calls) |
| Grass | 1.34 | 2.11 | 3.10 | **2.19** | 51–80 |
| Far tree pictures (part of trees) | 0.87 | 0.46\* | 2.40 | 1.24 | 24–59 |
| Houses and rocks | 0.27\* | 0.14\* | **−1.08** | −0.22 | 343–506 |
| **Everything off** | 10.85 | 13.13 | 14.40 | 12.79 | 617–826 |

With everything on, a frame takes 14.8 / 17.1 / 18.4 ms; the three
rounds agree within 1.5 %. With everything off, 4.0 ms is left on every
view: the sky, the depth pass, tonemapping and the 2D overlay.

A single round earlier gave nearly the same numbers (within 0.2 ms).

## What it means

- **The ground is the biggest single cost**, most of all looking across
  the open centre (6.4 ms). Its shader (`early2000s`) is the first thing
  to look at; the terrain benchmark can already compare other shaders
  (`--terrain-shader=`).
- **Trees, shadows and grass** cost 2–3 ms each, more near the village.
- **Houses and rocks cost almost nothing on the graphics card**, although
  they are the most draw calls. Close to the village, switching them off
  makes the frame **1.1 ms slower**, repeatably: the houses hide ground,
  grass and trees behind them, which then have to be drawn. So the draw
  call count is not what limits this PC.
- **The parts don't simply add up.** Added together they come to 11.4–14.7
  ms, against 10.9–14.4 ms for everything off: up to 1.7 ms apart, because
  they hide each other and share the shadow pass. The ranking holds, but
  each part's cost is "with all the others on".

## Check

Every switch made something less drawn (fewer draw calls or triangles) on
every view, so each switch really works; none had "no effect".
