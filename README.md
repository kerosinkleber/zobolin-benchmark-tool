# Zobolin Benchmark Tool

Measures what each part of the Zobolin game costs (graphics card, processor,
physics, stutters) and ranks the biggest costs. See `PLAN.md`.

Licence: GPL-3.0-or-later (see `LICENSE`).

## Status

Steps 1 (engine check, see `findings/01-engine-check.md`) and 2 (statistics) are done. There is
no one-command run yet.

## Engine check (step 1)

From the game folder `C:\Claude\Open World Game - Zobolin`:

    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Test engine

The game window opens, runs by itself for about a minute, and closes.
Results: `game\reports\benchmarks\engine\<preset>_<renderer>_<gpu>\engine_check.json`.
