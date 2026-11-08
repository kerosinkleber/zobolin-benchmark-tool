# Step 9c: micro benchmarks without a window (2026-11-08)

`game/benchmark/micro_bench.gd` times, without a window or graphics card,
the processor cost of systems that will grow with the game, at sizes the
game doesn't have yet. Built by an agent and checked by a second one.

    powershell -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Test micro -Extra "--quick"

(from the game folder; without `--quick` it also loads 100 000 records).
Results in `micro.json` (the `--quick` run below: `09c-micro-ryzen1800x.json`). Each case runs once to warm up, then 3 to 5 times;
the numbers are the middle value. Debug build, Ryzen 7 1800X.

| Case | Size | Time |
|---|---|---|
| One NPC route search (`RouteNetwork.route`) | 10 places | 0.044 ms |
| | 100 places | 3.1 ms |
| | 1000 places | **464 ms** |
| One update of an NPC that turns back on the road | 10 places | 0.48 ms |
| | 100 places | **428 ms** |
| Loading records (the real loader) | 1 000 records | 35 ms (35 µs each) |
| | 10 000 records | 272 ms (27 µs each) |
| An 8-hour clock jump, every NPC updated each hour | 0 NPCs | 0.008 ms |
| (100-place road net) | 100 NPCs | 415 ms (4.1 ms per NPC) |
| | 1000 NPCs | 4.3 s |
| The player waiting 8 hours (weather, sky) | | 0.24 ms |

## What it means

**Route finding is the game's biggest future processor problem.** One
search takes about 70 times longer from 10 to 100 places and another 150
times longer from 100 to 1000. In `game/npc/route_network.gd`, every step
of the search looks at every road in the world, so the cost grows with
places × roads.

- An NPC that has to turn back on the road searches a route from every
  place: at 100 places one such update takes 0.43 s, a visible freeze.
- An 8-hour wait with 150 NPCs on a 100-place map would take about 0.6 s.
- The playable slice plans about 10 NPCs and one town, where this is still
  fine (0.5 ms). It matters for 3 towns and 150 named NPCs (version 1.0).

A search that only looks at the roads leaving the current place (a list of
neighbours per place), or searching from the target backwards once instead
of from every place, would make this grow far more slowly. That is a game
change, for the owner to decide.

Record loading grows evenly (about 30 µs per record), so 100 000 records
would take about 3 s at start-up.
