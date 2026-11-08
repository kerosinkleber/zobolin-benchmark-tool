# Independent review of the tool (2026-11-08)

After steps 1 to 9 were built, four reviewers each read all of the tool's
code with one question (are the numbers right; is the PowerShell robust;
does the game still behave the same when nothing is measured; do the docs
match), and a fifth tried to disprove every finding against the code. 29
findings, 24 confirmed, 5 rejected. All 24 were fixed the same day.

## What was wrong, and what it changed

**1. Stopwatches per item, per NPC and per NPC body** (step 9). Each
stopwatch costs about 1.6 µs while recording. Run once per item in every
physics step, that is about 5 ms per step with 3000 items, growing with the
count: it would have made the sweeps' "cost per extra item / NPC" much too
steep. Their on/off checks also cost a little in normal play. **Removed**:
stopwatches now only run once per frame or step (for example all items
together), or on rare events. The bodies' cost shows in the physics time.

**2. The recorder's columns were not all about the same frame** (step 3).
`frame_ms` was one frame behind the scripts and drawing columns, the
physics time missed Jolt's sync of the bodies at the start of each step,
and work done by the checks' own coroutines fell outside the scripts time.
**Now** each row is one span, from the start of one frame's scripts to the
next, and every column belongs to it:

- physics time runs from the end of drawing;
- the scripts time includes the checks' coroutines;
- the recorder's own work is a separate column (`recorder_ms`).

Frame times still match the real clock (within 0.3 %).

Effect on earlier numbers (GTX 970, centre_north):

| | Before | Now |
|---|---|---|
| Scripts per frame | 0.11 ms | 0.28 ms |
| Physics per frame | 0.34 ms | 0.47 ms |

The scripts time now includes the benchmark's own stepping and the
recorder; that part shows as "unattributed" or `recorder_ms`, not in the
game's zones. The step 5c processor savings (measured as differences) are
not affected by the shift, only the totals.

**3. Stutter blame window.** With the columns aligned, a window of two
frames before and one after blamed tile building on the re-centre before
it. Now: the stutter's own frame and the one before. The flight now shows
6 re-centring stutters, 4 from grass tiles, 3 from far-object tiles and the
4 screenshots, instead of 11 under re-centring.

**4. The picture check** for the switches that act only while measuring
compared screenshots taken after the work was switched back on. Now the
screenshot is taken first.

**5. Smaller ones, all fixed:**

- A piece of a stopwatch whose parent never ran (the grabber in the boat
  scene) was counted as Jolt's time.
- The baseline comparison used the mean's noise for every number (p99 is
  far noisier).
- `summary.json` for a one-view session (the flight) stored its view as an
  object instead of a list.
- Re-analysing step 5a sessions marked every switch as switched back on.
- `compare_pcs.ps1 -Scenario vista` also picked up `vista_quick`.
- Baselines ignored which graphics card was used. They are now named per
  card, and no longer compared across different cards.
- Folder names ending in `\` broke the launcher's arguments.
- An untracked folder marked the game as changed.
- Several game options in one string went to the game as one.
- The README, both plans and two findings were out of date or off by a
  number (05c said "up to 1.1 ms", the data says 1.37 ms).

## Rejected

Five findings did not hold up, or were not defects:

- The launcher didn't set its exit code on success. Only a narrow case
  could go wrong, but the launcher now ends with an explicit success code
  anyway.
- The physics probe ball falls in every terrain run. One sphere costs Jolt
  next to nothing, and every baseline has it.
- The items check now waits for the spawn queue however long it takes.
  That is deliberate, because 3000 items take longer than 8 s; a stuck run
  is still stopped by the time limit.
- The stopwatch test's timing limits could fail on a busy PC. They have a
  fivefold margin, so this is unlikely and wasn't shown.
- Step 6's grass check isn't met by the quick scenario's numbers. That
  check is for the full 11-view scenario; it's plan status, not a defect.

## What this means for the findings so far

- **Steps 1, 2, 4, 5a, 5b:** not affected. They are differences in frame
  and graphics-card time, measured the same way before and after.
- **Step 5c:** the savings stand; the totals were too low (see above).
- **Steps 7 and 8:** the flight's cause table changed as described.
- **Steps 9a and 9b:** the sweeps were stopped and measured again after the
  fixes. The numbers in `09-sweeps.md` are from after them.
