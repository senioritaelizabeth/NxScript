# dox 1.6.0's run.js is CommonJS, but a parent package.json with "type":"module"
# causes Node to choke on it. Fix: write {"type":"commonjs"} directly into the
# dox folder so Node finds it before climbing up to the offending parent., idk works for now
$haxelibRoot = (haxelib config 2>$null).Trim()
$doxDir = Get-ChildItem (Join-Path $haxelibRoot "dox") -Directory |
Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName

if ($doxDir) {
    $pkgJson = Join-Path $doxDir "package.json"
    if (!(Test-Path $pkgJson)) {
        '{"type":"commonjs"}' | Set-Content $pkgJson
        Write-Host "Created $pkgJson (CommonJS override)"
    }
}
else {
    Write-Warning "Could not find dox installation under $haxelibRoot"
}

haxe doc.hxml
haxelib run dox -i doc.xml -o docs/ --title "NxScript" --include "nz"