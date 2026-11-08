# Step 7: what causes the stutters (2026-11-08)

The recorder now notes, every frame, which of the game's **events** happened:
re-centring (`recentre`), new near tree blocks (`tree_blocks`), new trunk
bodies (`trunk_bodies`), new grass tile placements (`grass_tiles`), new
far-object tiles (`object_tiles`), and the benchmark's own screenshots
(`screenshot`). The counters are one line each in the game's world scripts
(`forest.gd`, `grass_field.gd`, `far_objects.gd`) or existed already.

Every stutter (a frame over 33.3 ms, or over twice the typical frame) is
**blamed** on the events in the frames around it (two before, one after,
because the parts of a frame are noted at slightly different times), plus
a physics catch-up (more than one physics step in a frame) or shader
compiles. Its **main cause** is the first of: screenshot, re-centring, tree
blocks, trunk bodies, far-object tiles, grass tiles, shader compiles,
physics catch-up. (A physics catch-up mostly follows a long frame rather
than causing it, so it comes last.) The other causes found stay listed with
the stutter.

The flight is now recorded too, and `--fixed-flight` moves it the same
distance every frame (as at 60 fps), so every PC sees the same places.

    powershell -ExecutionPolicy Bypass -File zbench.ps1 -Scenario flight

## The flight on the GTX 970 (high preset, 3 runs)

Average frame 21.1 ms (the flight is slower than the views: it looks across
the world while new trees and tiles keep coming), p99 39.4 ms, 16 stutters
per run, of which 4 are the benchmark's own screenshots. Every stutter has
a cause; none is "unknown".

| Main cause | Stutters per run | Slowest | Where (world x) |
|---|---|---|---|
| Re-centring | 6 | 54.1 ms | −3060, −2040, −1013, 1033, 2060, 3080 |
| New far-object tiles | 4 | 46.5 ms | −3047, −1000, 27, 2073 |
| New grass tile placements | 2 | 37.0 ms | −2027, 3093 |
| The benchmark's screenshots | 4 | about 1.2 s | −1987, 13, 2013, 4013 |

**Check (plan step 7):** the re-centring stutters fall on the 1024 m lines,
as expected. There are 7 re-centres; the one at x = 13 falls on the frame
of a screenshot, so that stutter's main cause is the screenshot.

So the game's own stutters on this flight are 12 per run: half from
re-centring, the rest from new far-object and grass tiles. Step 8's
stopwatches show which part of each is slowest.

(First printed as "48 stutters": the tool's summary line added up the three
runs. It now shows stutters per run.)
