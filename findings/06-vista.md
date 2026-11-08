# Step 6: all 11 views, every part switched off (2026-11-08)

    powershell -ExecutionPolicy Bypass -File zbench.ps1 -Scenario vista -Ablate -Kind gpu

3 rounds of 13 variants (everything on, each part off, each piece off,
everything off), 39 runs, about 45 minutes. GTX 970, high preset
(5120 × 2880), game commit 60e1ab3. Every view was held back by the
graphics card in 100 % of frames. Raw summary:
`06-vista-ablate-gtx970-summary.json`; the page is the session's
`report.html`.

## Frame time with everything on

| View | Frame | 60 fps? |
|---|---|---|
| centre (north, east, south, west) | 14.8–15.1 ms | yes |
| high above the centre | 17.8 ms | no |
| valley floor | 17.1 ms | no |
| west edge looking east | 18.2 ms | no |
| corner looking in | 17.2 ms | no |
| village close | 18.4 ms | no |
| village from 1.5 km | 10.7 ms | yes |
| village from 3 km | 9.8 ms | yes |

The three runs agree within 2.2 %.

## What each part costs (average of the 11 views)

| Part | Average | Range over the views |
|---|---|---|
| **Ground (Terrain3D)** | **6.0 ms** | 2.8 (valley floor) – 9.5 (high above the centre) |
| Trees | 2.2 ms | 1.1 – 4.2 (village close) |
| – of it the far tree pictures | 1.3 ms | 0.3 – 2.5 |
| Shadows | 1.7 ms | 0.7 – 2.5 |
| – the ground's | 0.3 ms | |
| – the near trees' | 0.3 ms | up to 1.1 (valley floor) |
| – the houses' and rocks' | 0.1 ms | |
| Grass | 1.5 ms | 0 (from high up and far away) – 3.2 (west edge) |
| Sky | 0.9 ms | 0.4 – 1.6 |
| Fog | 0.2 ms | |
| Houses and rocks | 0.1 ms | −1.1 (village close: they hide what's behind) – 0.4 |
| Everything off | 14.2 ms saved; 1.2 ms left | |

**The ground is the biggest cost on 9 of the 11 views**, most of all
looking across open land (9.5 ms from high above the centre). On the valley
floor and close to the village, the trees cost more (3.5 and 4.2 ms). The
ground's shader is the first place to look for time.

## Check (plan step 6)

- **The report page:** made at the end of every session (since step 6).
- **"Grass about 3.5 ms (±25 %)": not met.** It measures 1.5 ms on
  average and 3.2 ms at most. The 3.5 ms came from prototype item 1b,
  before there were trees and while the grass thinned out to 250 m; it now
  ends at 200 m (the owner's choice, to keep 60 fps at 5K) and trees hide
  much of it. That the tool sees grass changes
  is shown by step 11a: grass out to 300 m made every view 7–10 % slower.
- **"UHD 770 says GPU-bound":** needs the i9 PC (step 11b).
