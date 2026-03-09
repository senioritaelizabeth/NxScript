# copy src and test to snapshot/date/

$srcDir = "src"
$testDir = "test"
$snapshotBaseDir = "snapshot"
$date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$snapshotDir = Join-Path $snapshotBaseDir $date
New-Item -ItemType Directory -Path $snapshotDir | Out-Null
Copy-Item -Path $srcDir -Destination $snapshotDir -Recurse
Copy-Item -Path $testDir -Destination $snapshotDir -Recurse

Write-Host "Snapshot created at $snapshotDir."