# Speed Comparison Report

## Per-Target Comparisons

### eval

| Scenario             | NxScript ops/s | Iris ops/s (%Nx) | HScriptImproved ops/s (%Nx) | Winner   |
| -------------------- | -------------: | ---------------: | --------------------------: | -------- |
| Update Loop 100k     |          31045 |      21024 (68%) |                 14205 (46%) | NxScript |
| Arithmetic Chain 60k |          11837 |       7624 (64%) |                  4565 (39%) | NxScript |
| Array Push/Pop 30k   |           7049 |       5247 (74%) |                  2934 (42%) | NxScript |

### hl

| Scenario             | NxScript ops/s | Iris ops/s (%Nx) | HScriptImproved ops/s (%Nx) | Winner   |
| -------------------- | -------------: | ---------------: | --------------------------: | -------- |
| Update Loop 100k     |         149078 |      43182 (29%) |                 30427 (20%) | NxScript |
| Arithmetic Chain 60k |          56519 |      33467 (59%) |                 14093 (25%) | NxScript |
| Array Push/Pop 30k   |          37492 |      21275 (57%) |                  9993 (27%) | NxScript |

### cpp

| Scenario             | NxScript ops/s | Iris ops/s (%Nx) | HScriptImproved ops/s (%Nx) | Winner   |
| -------------------- | -------------: | ---------------: | --------------------------: | -------- |
| Update Loop 100k     |         475181 |     154204 (32%) |                141569 (30%) | NxScript |
| Arithmetic Chain 60k |         153232 |      68372 (45%) |                 43773 (29%) | NxScript |
| Array Push/Pop 30k   |          96874 |      48027 (50%) |                 30717 (32%) | NxScript |

## NxScript Cross-Target

| Scenario             | Target | NxScript ops/s | Relative To Fastest |
| -------------------- | ------ | -------------: | ------------------: |
| Update Loop 100k     | hl     |         149078 |                 31% |
| Update Loop 100k     | eval   |          31045 |                  7% |
| Update Loop 100k     | cpp    |         475181 |                100% |
| Arithmetic Chain 60k | hl     |          56519 |                 37% |
| Arithmetic Chain 60k | eval   |          11837 |                  8% |
| Arithmetic Chain 60k | cpp    |         153232 |                100% |
| Array Push/Pop 30k   | hl     |          37492 |                 39% |
| Array Push/Pop 30k   | eval   |           7049 |                  7% |
| Array Push/Pop 30k   | cpp    |          96874 |                100% |
