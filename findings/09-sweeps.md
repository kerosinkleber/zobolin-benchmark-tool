# Steps 9a and 9b: how NPCs, items and cargo grow (2026-11-08)

The NPC, items and boat checks record themselves with `--record` (agents
built and reviewed the wiring; the independent review's fixes came before
these runs, see `10-review.md`). Each takes a count option, and the tool
runs the counts in turns and fits a straight line through the costs
(`zbench.ps1 -Scenario npc_crowd -Repeats 2`, `-Scenario items`,
`-Scenario boat_cargo`).

GTX 970 PC (Ryzen 7 1800X), high preset, debug build. "Processor" is scripts
plus physics per frame on average. Raw summaries: `09a-npc-crowd-gtx970-summary.json`,
`09b-items-gtx970-summary.json`, `09b-boat-cargo-gtx970-summary.json`.

## NPCs: 8, 24, 64 (2 runs each)

| Phase | Processor, 8 → 24 → 64 NPCs | Per extra NPC | Line fits |
|---|---|---|---|
| Near village A, before 07:00 | 0.74 → 0.98 → 1.63 ms | 0.016 ms | 100 % |
| The 07:00 rush | 0.85 → 1.20 → 2.30 ms | 0.026 ms | 100 % |
| Walking round the wall | 0.91 → 1.29 → 2.37 ms | 0.026 ms | 100 % |
| Village B at noon | 0.80 → 0.98 → 1.51 ms | 0.013 ms | 100 % |
| An 8-hour clock jump | 0.74 → 1.01 → 1.75 ms | 0.018 ms | 100 % |

In the rush, of the 2.30 ms at 64 NPCs: the NPCs' update each frame
(`npc` stopwatch) 0.75 ms (0.14 ms at 8), and the bodies' physics most of
the rest (1.31 ms against 0.52 ms at 8).

**Check (plan step 9a):** the cost grows steadily, along a straight line
(fit 100 % in every phase with NPCs about). The 07:00 rush is the dearest
phase. The frame itself stays around 11 ms: this scene is held back by the
graphics card, so 64 NPCs don't lower the frame rate here yet. On a slower
processor (the laptop) 64 NPCs add about 1.6 ms per frame.

## Items: 300, 1000, 3000 (3 runs each)

| Phase | Processor, 300 → 1000 → 3000 | Frame time |
|---|---|---|
| Lying still (at rest) | 0.71 → 1.09 → 2.97 ms | 10.1 → 10.7 → 15.0 ms |
| Coming to rest | 0.89 → 1.54 → 4.93 ms | 10.0 → 10.7 → 17.0 ms |
| Some floating on waves | 2.06 → 4.08 → 12.04 ms | 11.6 → 11.7 → 17.3 ms |
| **All thrown at once** | 1.40 → 3.24 → **38.0 ms** | 10.1 → 10.8 → **50.8 ms** |

- Items that lie still cost about 0.001 ms each per frame.
- **3000 items moving at once bring the game down to 20 fps**, all of it
  physics. The items' own scripts take 21 ms (the "items" stopwatch: about
  7 µs per moving item per physics step) and Jolt takes 16 ms. From 1000 to
  3000 the cost grows by 12 times, not 3, so moving items get dearer the
  more of them touch each other.
- Moving items stay under half a frame at 60 fps (8 ms) up to somewhere
  between 1000 and 3000 at once on this PC (3 ms at 1000); the sweep
  doesn't show exactly where.

**Check (plan step 9b):** the items and boat checks still pass as before
(their normal runs are unchanged).

## Boat cargo: 0, 13, 26 crates (3 runs each)

| Phase | Processor, 0 → 13 → 26 crates | Per extra crate |
|---|---|---|
| Drifting | 0.82 → 1.05 → 1.30 ms | 0.019 ms |
| Sailing | 0.82 → 1.04 → 1.28 ms | 0.018 ms |
| Walking on deck | 0.89 → 1.17 → 1.45 ms | 0.022 ms |
| Saving and loading | 0.94 → 1.20 → 1.50 ms | 0.022 ms |

The boat's own code hardly grows (its stopwatch 0.082 → 0.107 ms; holding
the cargo 0.012 → 0.041 ms). The rest is the crates' own physics: **stowed
crates still cost about 0.018 ms each per frame**, as if they were moving.
A crate held on deck could be taken out of the physics while stowed.

## Found on the way (game issues, for the owner)

- **Loading a trip with stacked cargo drops it:** with more than one layer
  of crates, loading stows only the bottom layer again; the rest falls
  loose. (One of the agents wrote a fix; it was taken out again because it
  changes how the game works. That's the owner's call.)
- **Unstowing many crates is slow:** loading with 103 crates took 38 ms in
  one frame, because freeing each crate checks every crate on deck.
