# Steps 9a and 9b: how NPCs, items and cargo grow (2026-11-08)

The NPC, items and boat checks record themselves with `--record` (agents
built and reviewed the wiring; the independent review's fixes came before
these runs, see `10-review.md`). Each takes a count option, and the tool
runs the counts in turns and fits a straight line through the costs
(`zbench.ps1 -Scenario npc_crowd -Repeats 2`, `-Scenario items`,
`-Scenario boat_cargo`).

GTX 970 PC (Ryzen 7 1800X), high preset, debug build, game commit
1d84a30 (after the review's fixes and the screenshot fix: the first runs
counted a screenshot's save as physics in phases with a screenshot; the
growth per NPC, item or crate hardly changed). "Processor" is scripts
plus physics per frame on average. Raw summaries: `09a-npc-crowd-gtx970-summary.json`,
`09b-items-gtx970-summary.json`, `09b-boat-cargo-gtx970-summary.json`.

## NPCs: 8, 24, 64 (2 runs each)

| Phase | Processor, 8 → 24 → 64 NPCs | Per extra NPC | Line fits |
|---|---|---|---|
| Near village A, before 07:00 | 0.78 → 1.01 → 1.64 ms | 0.016 ms | 100 % |
| The 07:00 rush | 0.88 → 1.25 → 2.32 ms | 0.026 ms | 100 % |
| Walking round the wall | 0.89 → 1.27 → 2.31 ms | 0.026 ms | 100 % |
| Village B at noon | 0.83 → 1.02 → 1.53 ms | 0.013 ms | 100 % |
| An 8-hour clock jump | 0.76 → 1.05 → 1.78 ms | 0.018 ms | 100 % |

In the rush, of the 2.32 ms at 64 NPCs: the NPCs' update each frame
(`npc` stopwatch) 0.75 ms (0.15 ms at 8), and the bodies' physics most of
the rest (1.33 ms against 0.53 ms at 8).

**Check (plan step 9a):** the cost grows steadily, along a straight line
(fit 100 % in every phase with NPCs about). The 07:00 rush is the dearest
phase. The frame itself stays around 11 ms: this scene is held back by the
graphics card, so 64 NPCs don't lower the frame rate here yet. On a slower
processor (the laptop) 64 NPCs add about 1.6 ms per frame.

## Items: 300, 1000, 3000 (3 runs each)

| Phase | Processor, 300 → 1000 → 3000 | Frame time |
|---|---|---|
| Lying still (at rest) | 0.76 → 1.12 → 3.03 ms | 10.8 → 10.8 → 15.3 ms |
| Coming to rest | 0.91 → 1.57 → 5.12 ms | 10.1 → 10.8 → 17.4 ms |
| Some floating on waves | 1.44 → 3.44 → 11.04 ms | 11.8 → 11.8 → 17.5 ms |
| **All thrown at once** | 1.42 → 3.31 → **40.2 ms** | 10.1 → 10.9 → **53.2 ms** |

- Items that lie still cost about 0.001 ms each per frame.
- **3000 items moving at once bring the game down to 19 fps**, all of it
  physics. The items' own scripts take 22 ms (the "items" stopwatch: about
  7 µs per moving item per physics step) and Jolt takes 17 ms. From 1000 to
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
| Drifting | 0.84 → 1.08 → 1.32 ms | 0.018 ms |
| Sailing | 0.84 → 1.07 → 1.31 ms | 0.018 ms |
| Walking on deck | 0.93 → 1.21 → 1.47 ms | 0.021 ms |
| Saving and loading | 0.97 → 1.24 → 1.53 ms | 0.022 ms |

The boat's own code hardly grows (its stopwatch 0.081 → 0.109 ms; holding
the cargo 0.012 → 0.042 ms). The rest is the crates' own physics: **stowed
crates still cost about 0.018 ms each per frame**, as if they were moving.
A crate held on deck could be taken out of the physics while stowed.

## Found on the way (game issues, for the owner)

- **Loading a trip with stacked cargo drops it:** with more than one layer
  of crates, loading stows only the bottom layer again; the rest falls
  loose. (One of the agents wrote a fix; it was taken out again because it
  changes how the game works. That's the owner's call.)
- **Unstowing many crates is slow:** loading with 103 crates took 38 ms in
  one frame, because freeing each crate checks every crate on deck.
