# Step 4: the one command (2026-11-08)

`zbench.ps1` runs a scenario several times through the game's
`tools\benchmark.ps1` (new options `-OutDir` and `-Extra`), gives each run
its own folder, notes the PC (processor, graphics cards and drivers,
memory, Windows, power plan, battery, the game's commit), refuses capped
runs, and combines the repeats into `summary.json`.

## Check: three repeats (GTX 970, high preset, `vista_quick`)

| View | Run 1 | Run 2 | Run 3 | Middle | Spread |
|---|---|---|---|---|---|
| centre_north | 14.85 ms | 14.97 ms | 15.05 ms | 14.97 ms | 1.4 % |
| valley_floor | 17.21 ms | 17.42 ms | 17.39 ms | 17.39 ms | 1.3 % |
| village_close | 18.65 ms | 18.69 ms | 18.74 ms | 18.69 ms | 0.5 % |

The repeats agree within 1.4 %, below the 3 % noise band, so on this PC a
change has to be over 5 % (the alarm limit) to count. An earlier session
the same afternoon gave 1.2 % / 0.2 % / 0.9 %. Each run took about 27 s.
The power plan was "Balanced" (the tool warns about it); "High
performance" may narrow the spread further.

## Check: a capped run is refused

With the game held at 60 fps (`-GameOptions @('--max-fps=60')`, a test
option of the terrain benchmark), the tool stopped after the first run:
"The frame rate is capped in: centre_north (held at 60.0 fps)". The other
two views were slower than 60 fps anyway, so they weren't capped.

The first version of the check missed it: the graphics card was still busy
87 % of each frame (the limit was 85 %). What gives a frame limit away is
the main thread: busy only 2.2 ms of 16.7 ms. The check now looks at both
(the graphics card waiting, as with vsync, or the main thread waiting, as
with a frame limit).

## Learned on the way

- PowerShell doesn't tell upper and lower case apart in names: a variable
  `$out` overwrites an option `-Out`, and `$gpu` an option `-Gpu`. Both
  happened; the options are now `-OutDir`, and the variable `$gpuBand`.
- `Measure-Object -Property` doesn't work on PowerShell's ordered tables;
  the summary loops instead.
