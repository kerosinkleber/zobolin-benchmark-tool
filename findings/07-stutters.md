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

Measured after the independent review's fixes (`10-review.md`), game commit
ff9e4d4. Raw summary: `07-flight-gtx970-summary.json`.

Average frame 21.2 ms (the flight is slower than the views: it looks across
the world while new trees and tiles keep coming), p99 39.5 ms, 17 stutters
per run, of which 4 are the benchmark's own screenshots. Every stutter has
a cause; none is "unknown".

| Main cause | Stutters per run | Slowest | Where (world x) |
|---|---|---|---|
| Re-centring | 6 | 54.1 ms | −3067, −2047, −1020, 1027, 2053, 3073 |
| New grass tile placements | 4 | 46.3 ms | −3053, −2033, 2067, 3087 |
| New far-object tiles | 3 | 40.1 ms | −1007, 20, 1040 |
| The benchmark's screenshots | 4 | about 1.3 s | −1993, 7, 2007, 4007 |

**Check (plan step 7):** the re-centring stutters fall on the 1024 m lines,
as expected. There are 7 re-centres; the one at x = 7 falls on the frame of
a screenshot, so that stutter's main cause is the screenshot.

So the game's own stutters on this flight are 13 per run: about half from
re-centring, the rest from the grass and far-object tiles that come in
right after (a stutter is blamed on its own frame and the one before).
Step 8's stopwatches show which part of each is slowest.

(Earlier versions of this file: before the review, a wider blame window put
11 stutters under re-centring; and the summary line once added up the three
runs as "48 stutters".)
