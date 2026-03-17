# Speed Comparison Report

## Per-Target Comparisons

### hl

| Scenario | NxScript ops/s | Iris ops/s (%Nx) | HScriptImproved ops/s (%Nx) | Winner |
|---|---:|---:|---:|---|
| Update Loop 100k | 313122 | 69229 (22%) | 52667 (17%) | NxScript |
| Arithmetic Chain 60k | 80220 | 41816 (52%) | 21085 (26%) | NxScript |
| Array Push/Pop 30k | 95252 | 17855 (19%) | 9357 (10%) | NxScript |

### cpp

| Scenario | NxScript ops/s | Iris ops/s (%Nx) | HScriptImproved ops/s (%Nx) | Winner |
|---|---:|---:|---:|---|
| Update Loop 100k | 1054688 | 172012 (16%) | 185473 (18%) | NxScript |
| Arithmetic Chain 60k | 279354 | 73915 (26%) | 56633 (20%) | NxScript |
| Array Push/Pop 30k | 193675 | 44058 (23%) | 32023 (17%) | NxScript |

## NxScript Cross-Target

| Scenario | Target | NxScript ops/s | Relative To Fastest |
|---|---|---:|---:|
| Update Loop 100k | hl | 313122 | 30% |
| Update Loop 100k | cpp | 1054688 | 100% |
| Arithmetic Chain 60k | hl | 80220 | 29% |
| Arithmetic Chain 60k | cpp | 279354 | 100% |
| Array Push/Pop 30k | hl | 95252 | 49% |
| Array Push/Pop 30k | cpp | 193675 | 100% |