# Step 5b: new switches for the graphics card (2026-11-08)

New in the terrain benchmark's `--off=`: `sky` (a plain colour instead),
`fog`, and the shadows by what casts them: `terrain_shadows` (Terrain3D's
`cast_shadows`), `tree_shadows` (near trees), `object_shadows` (the nearest
level of houses and rocks; `FarObjects.casts_shadows`, new, with a test).

The scenarios now list separate parts (`switches`: shadows, grass,
objects, trees, terrain, sky, fog) and pieces of them (`detail_switches`:
pictures, terrain_shadows, tree_shadows, object_shadows). Pieces are
measured one by one but left out of "all off" and of adding the parts
up, so nothing is counted twice. (In 5a, the far tree pictures were still
counted as a separate part.)

Sky and fog change how things are drawn, not what, so the draw counts
don't show them. For these the check is: the setting was still off at the
end of every run, and the frame got measurably faster. Every run's
`run.json` says for each switch what it removes, how it is checked, and
whether it was still off.

Not measured yet:
- **Water**: not in the terrain scene, only in the boat test. It needs a boat scenario.
- **House lamps**: these shine only inside the house, so none of the
  outdoor views has them on. They need a house scenario.
- **Glow, SSAO and similar**: the high preset uses none of them. The only
  screen effects are fog and the colour adjustment (part of tonemapping).

Raw summary: `05b-switches-gtx970-high-summary.json`.

## What each part costs (GTX 970, high preset, 3 rounds of 13 runs)

Frame time saved when the part is off, ms. \* = inside the noise.

| Part | centre_north | valley_floor | village_close | Average |
|---|---|---|---|---|
| Ground (Terrain3D) | 6.48 | 2.91 | 3.98 | **4.46** |
| Trees | 1.51 | 3.51 | 4.22 | **3.08** |
| Shadows (all) | 2.16 | 2.62 | 2.30 | **2.36** |
| Grass | 1.44 | 2.19 | 3.13 | **2.25** |
| Sky | 1.11 | 0.32\* | 0.85 | **0.76** |
| Fog | 0.39\* | 0.36\* | 0.26\* | 0.34 (inside the noise) |
| Houses and rocks | 0.33\* | 0.32\* | −0.92 | −0.09 |
| *Pieces:* | | | | |
| – far tree pictures (of trees) | 0.96 | 0.57 | 2.43 | 1.32 |
| – near trees' shadows | 0.38\* | 1.09 | 0.62 | 0.70 |
| – ground's shadows | 0.48 | 0.54 | 0.40\* | 0.47 |
| – houses' and rocks' shadows | 0.21\* | 0.04\* | 0.11\* | 0.12 |
| **Everything off** | 13.74 | 16.05 | 17.29 | 15.70 |

With everything on: 14.9 / 17.2 / 18.5 ms per frame; the three rounds
agree within 0.7 %. With everything off (now including the sky) 1.2 ms
is left.

## What it means

- The order of the big four stays the same as in 5a: ground, trees, shadows, grass.
- **Shadows: the casters explain only half.** The ground, near trees and
  houses together cast about 1.3 ms of the 2.4 ms. The rest is the shadow
  pass itself (four splits on a 4096 atlas) plus what else casts: the
  grass may. Fewer splits or a smaller atlas are worth trying.
- **The sky costs about 0.8 ms**, most when a lot of sky is seen.
- **Fog costs almost nothing.** It is worked out while each surface is drawn, not as a pass of its own.
- **The parts don't add up.** Without the double counting they come to
  12.2–13.8 ms, but everything off saves 13.7–17.3 ms. The ground hides
  much of the rest, and switching everything off also drops passes that
  every part needs, such as the depth pass. So each part's cost is
  "with everything else on".
- **The noise floor is 3 %** (about 0.5 ms here). This PC's repeats
  agree within 0.7 %, so a smaller floor would let fog and the houses'
  shadows show. That is decision 5 in the plan, and worth revisiting now.

## Check

Every switch worked: ten drew less (fewer draw calls or triangles), and
the sky held its setting and made the frame faster. Fog held its setting
too, but its saving is inside the noise, and the tool says so.
