# The last scenarios: forest, house, weather, fast time, start-up, water (2026-11-08)

The scenarios section 5 of `PLAN.md` still listed as not built, now built
and measured: `forest_lowpass`, `village_walk` (switch `lamps`),
`storm_noon`, `storm_night`, `snow`, `time_fast`, `load` (with and without
`-ColdCache`) and `boat` (switch `water`). 3 runs each, 15 s cooling
between scenarios (20 s for `village_walk` and the `vista_quick` reference).

GTX 970 PC (Ryzen 7 1800X), high preset, Forward+, 5120 × 2880 drawn into
a 2560 × 1440 window, debug build. Game commits 94162ed, 89a0220 and
d7de3f2: between them only documents changed (and, for `village_walk`, how
the lamps switch is checked, see below), not the game. The power plan was
"Balanced" (the tool warns about it); repeats still agreed within
1.9 % (the graphics card's time within 2.4 %). Raw summaries: `11-*-gtx970-summary.json`.

For the weather and time scenarios, the reference is a `vista_quick` run
the same evening (`11-vista-quick-reference-gtx970-summary.json`):
centre_north 14.92 ms, valley_floor 17.35 ms, village_close 18.63 ms, all
waiting for the graphics card (it is no change against the saved baseline,
within 1.5 %).

## Warning: the first single runs were disturbed (and the tool now says so)

The first single runs of `forest_lowpass`, `storm_noon` and `snow` (21:33 to
21:36) were much slower: the forest 42.8 ms instead of 18.3 ms, with
stutters up to 313 ms, and the storm 26 to 29 ms instead of 16 to 20.
Those numbers are wrong. What the game itself drew was the same (the same
draw calls and triangles; its graphics-card time was 19.0 against 17.4 ms),
but each frame waited much longer for its picture: about 22 ms longer in
the forest, 8 to 9 ms in the storm, 4 ms in the snow's village view. Most
likely another program was using the graphics card then. The first
cold-start run (21:38) was hit too.

The tool now catches this. Per run and view, it takes the time the frame
spent drawing, minus the game's own graphics-card time, minus its scripts
and physics. Over all 1248 saved views and phases this is normally below
zero to 1.4 ms in undisturbed runs. In the disturbed runs it was 20.3 ms
(forest), 6.7 to 7.9 ms (storm), 3.3 ms (snow, village_close) and 4.3 ms
(the first cold start). Above 3 ms, `zbench.ps1`
now prints a WARNING naming the run and view, and the warning goes into
`summary.json` and the report page, and `-SaveBaseline` refuses such a
session (it would make every later clean run look faster). Re-analysing
the old runs shows the warning; the new runs below show none.

## Forest, low and fast (`forest_lowpass`)

2 km at 30 m above ground over the densest row of tree blocks, 60 m/s, the
same distance every frame.

| | Frame | Graphics card | Waiting for the card | Stutters per run |
|---|---|---|---|---|
| `forest_lowpass` | 18.25 ms (55 fps) | 17.36 ms | 99 % of frames | 4 |

- **On this PC the forest at low height costs the graphics card, not the
  processor.** Scripts and physics together take 1.06 ms per frame. The
  forest's scripts average 0.044 ms, the trunk collision 0.032 ms.
- **The 4 stutters come from 2 places, every run:** at world x 2050 and
  3075, where the world is re-centred and new grass tiles are made. That
  is the boundary every 1024 m, the same cause as in the flight
  (`07-stutters.md`). Slowest: re-centring 49.5 ms, grass tiles 39.7 ms.
- **Inside a re-centre**, the slowest frames are the regions' update
  (`recentre.regions`, 17.7 ms) and moving the collision (10.2 ms). The
  forest's trunk collision for new blocks has a slowest frame of 10.9 ms
  (`forest.collision`).

## The house: walking to the door, in and out (`village_walk`, switch `lamps`)

| Phase | Frame | Graphics card | Lamps cost (switched off once) |
|---|---|---|---|
| At the door | 16.98 ms | 16.23 ms | none (−0.09 ms, inside the noise) |
| Walking in | 20.43 ms | 20.29 ms | **4.37 ms** |
| Walking out | 15.00 ms | 13.36 ms | 0.96 ms |

- **Inside the house the lamps cost 4.4 ms of 20.4 ms** (about a fifth),
  all of it graphics-card time. They are point lights without shadows, so
  the cost is the lighting work on every pixel they reach, at 5K.
- **The first run marked the lamps switch "NO: nothing less was drawn".**
  That was the tool's mistake, not the switch's: a light is not a draw call,
  so the draw-call count cannot drop. The game's switch table now checks
  the lamps as a setting (still off at the end, frame faster); the second
  run shows "yes". Game commit d7de3f2.

## Weather and fast time (the 3 quick views)

Against the same evening's `vista_quick` (frame time, all waiting for the
graphics card):

| Scenario | centre_north | valley_floor | village_close |
|---|---|---|---|
| Normal (reference) | 14.92 ms | 17.35 ms | 18.63 ms |
| `storm_noon` (rain, lightning every 5 s) | 16.00 (+7.3 %) | 18.08 (+4.2 %) | 19.64 (+5.4 %) |
| `storm_night` (23:00) | 13.84 (−7.2 %) | 15.19 (−12.4 %) | 16.91 (−9.2 %) |
| `snow` (noon) | 15.50 (+3.9 %) | 17.51 (+0.9 %) | 19.00 (+2.0 %) |
| `time_fast` (an hour every 6 s) | 15.90 (+6.6 %) | 18.03 (+3.9 %) | 19.23 (+3.2 %) |

- **The storm costs 0.7 to 1.1 ms at noon.** At night the frame is 1.1 to
  2.2 ms *cheaper* than a normal noon. At 23:00 on the test's date the
  moon gives no light, so the game switches its sun-and-moon light off
  completely, and with it all shadows (0 shadow draw calls, against 250 to
  440 at noon). Shadows alone cost about 1.7 ms at noon (`06-vista.md`).
  That saving hides the storm's own cost. On a night with the moon up, the
  light and its shadows stay on, and the night would save less.
- **Lightning makes no stutter:** 0 stutters per run in both storms, with a
  strike every 5 s.
- **Snow costs at most 0.6 ms.**
- **Fast time, the scripts:** the day-and-night script (`daynight`
  stopwatch) takes 0.178 ms per frame instead of about 0.02, with the
  slowest frame at 0.53 ms. On this PC it is hidden, because the frame
  waits for the graphics card. On a PC where the processor is the limit it
  would count.
- **Fast time, the picture:** the frame is 0.6 to 1.0 ms slower, nearly
  all on the graphics card, so not because of the scripts. The likeliest
  reason is that the sky keeps changing. In the other tests the clock is
  stopped, but here the game updates the sky every few game minutes, and
  Godot has to work out the sky's light again each time. The light also
  changes as the afternoon goes on. The test does not show which of these
  costs how much.

## Start-up (`load`, with and without `-ColdCache`)

From the game's start to the first steady frame of one view (centre_north):

| | To the view | Landscape | Forest | Other | Tree pictures |
|---|---|---|---|---|---|
| Warm (caches as they were) | 13.11 s | 3.14 s | 3.60 s | 4.31 s | 8 cached |
| Cold (caches deleted before each run) | 14.04 s | 3.21 s | 3.60 s | 5.23 s | 8 new |

(The rest is 2.0 s of fixed waits in the test.)

- **A cold start is 0.9 s longer**, all in "other" (Godot starting, the
  scene, houses and rocks, grass, shaders). Making the 8 tree pictures anew
  costs no visible time: the forest's 3.6 s is the same both ways. So the
  0.9 s is most likely compiling the shaders again (2 MB of them were
  deleted).
- **Limit:** the "shaders compiled" counter shows 0 even after a cold
  start. That is because the tool only starts counting at the first
  measured view, after loading is done, so shaders compiled while the game
  loads are never counted. (The counter does work: in the boat scene it
  caught a 190 ms shader compile.) So the 0.9 s comes from the times, not
  from a count.
- After start-up there are no unsteady frames, and the first frame takes
  15 ms.

## The boat and its water (`boat`, switch `water`)

The boat scene with no cargo: settling, drifting, sailing, turning,
walking on deck, saving and loading.

| Phase | Frame | Water off | Water costs | Waiting for the card |
|---|---|---|---|---|
| Settling | 10.57 ms | 4.82 ms | 5.75 ms | 69 % |
| Drifting | 10.13 ms | 4.63 ms | 5.50 ms | 70 % |
| Sailing | 10.23 ms | 4.56 ms | 5.67 ms | 70 % |
| Turning | 10.08 ms | 4.64 ms | 5.43 ms | 71 % |
| Walking on deck | 11.55 ms | 5.06 ms | 6.48 ms | 94 % |
| Saving and loading | 11.82 ms | 4.72 ms | 7.10 ms | 97 % |

- **Drawing the water is more than half of the boat scene's frame:** 5.4 to
  7.1 ms, 6.0 ms on average, nearly all graphics-card time. The water
  surface is about 320,000 triangles. Without it, the scene has 60 to 456.
  The test can't tell how much is the triangles and how much is the water's
  colouring of each pixel at 5K. Measuring that would need a smaller
  water mesh (the owner's call).
- **Buoyancy and the waves are cheap on the processor:** the boat's
  scripts are 0.08 to 0.10 ms per frame, buoyancy 0.05 to 0.06 ms of
  that.
- **One stutter per run at the start:** 190 ms compiling shaders when
  the boat scene first draws. Saving the trip has one slowest frame of
  4.5 ms.

## All three PCs (step 11b)

Measured by their own sessions; `compare_pcs.ps1` (`vista_quick`, frame
time, against 60 fps = 16.7 ms):

| View | i9, UHD 770, low, Forward+ | i9, UHD 770, low, Mobile | Laptop, GTX 1050, low | Laptop, GTX 1050, high | This PC, GTX 970, high |
|---|---|---|---|---|---|
| centre_north | 18.2 ms (55 fps) | 12.1 (83) | 6.6 (153) | 26.2 (38) | 14.8 (68) |
| valley_floor | 23.4 (43) | 18.3 (55) | 8.0 (124) | 31.2 (32) | 17.1 (59) |
| village_close | 24.5 (41) | 16.9 (59) | 8.4 (119) | 31.5 (32) | 18.4 (54) |

The laptop is an i7-7700HQ with a GTX 1050 laptop card (PC name
ENCELADUS). On every PC the graphics card is the limit. The laptop's low
flight has stutters up to 409 ms (making tree blocks): the stutter
causes are the same as here, only longer. Details are in the game's
`measurements/i9-low-tier.md` and `measurements/i7-gtx1050.md`.

## What this means for the game

1. **Water** is the biggest single cost found in this round: about 6 ms on a
   GTX 970 at 5K. On weaker cards it will matter more.
2. **The house lamps** cost 4.4 ms indoors. With several lit houses in view
   it adds up.
3. **Re-centring every 1024 m** is still the cause of the travel stutters,
   now confirmed low over the forest too (up to 50 ms).
4. **Weather and fast time** are cheap on this PC (at most about 1 ms).
5. **Benchmark hygiene:** don't run anything else that draws during a run.
   The tool now warns when a run was disturbed.
