# SPDX-License-Identifier: GPL-3.0-or-later
# Puts the PCs side by side: every saved baseline of one scenario (one per
# PC, preset and renderer, from zbench.ps1 -SaveBaseline), each against the
# target of 60 frames per second (16.7 ms per frame) that all three tiers
# share (Step 0.md). These are tiers, not regressions: a laptop on low is
# not "slower" than the development PC on high, it has its own target.
#
#   powershell -ExecutionPolicy Bypass -File compare_pcs.ps1 [-Scenario vista_quick]
#
# Baselines from other PCs get here by committing them (baselines\ is part
# of the tool's repository) and pulling on this PC.

param(
	[string] $Scenario = "vista_quick"
)

$TargetMs = 1000.0 / 60.0
$folder = Join-Path $PSScriptRoot "baselines"
# Exactly this scenario: <scenario>_<preset>_<renderer>_<graphics card>[_gpuprofile]
# ("vista" must not pick up "vista_quick").
$pattern = '^' + [regex]::Escape($Scenario) + '_(high|low)_(forward_plus|mobile)_[^_]+$'
$files = @(Get-ChildItem $folder -Recurse -Filter "*.json" -ErrorAction SilentlyContinue |
	Where-Object { $_.BaseName -match $pattern })
if ($files.Count -eq 0) {
	Write-Host "No baselines for '$Scenario' yet. Make one on each PC with: zbench.ps1 -Scenario $Scenario -SaveBaseline" -ForegroundColor Yellow
	exit 1
}

$columns = @()
foreach ($file in $files) {
	$summary = Get-Content -Raw $file.FullName | ConvertFrom-Json
	$card = $summary.graphics_card_used
	$columns += [ordered]@{
		label = "$($summary.machine.pc) $($summary.preset)"
		detail = "$card, $($summary.renderer), $([int]$summary.render_3d[0]) x $([int]$summary.render_3d[1])"
		commit = $summary.machine.game_commit
		segments = $summary.segments
	}
}

Write-Host "Scenario $Scenario, target 60 fps (16.7 ms per frame):" -ForegroundColor Cyan
foreach ($c in $columns) {
	$short = if ("$($c.commit)".Length -ge 7) { "$($c.commit)".Substring(0, 7) } else { $c.commit }
	Write-Host ("  {0}: {1}, game commit {2}" -f $c.label, $c.detail, $short)
}
Write-Host ""
$header = "{0,-24}" -f "view"
foreach ($c in $columns) { $header += " {0,26}" -f $c.label }
Write-Host $header
$views = @()
foreach ($c in $columns) { foreach ($s in $c.segments) { if ($views -notcontains $s.name) { $views += $s.name } } }
foreach ($view in $views) {
	$line = "{0,-24}" -f $view
	foreach ($c in $columns) {
		$s = $c.segments | Where-Object { $_.name -eq $view } | Select-Object -First 1
		if ($null -eq $s) { $line += " {0,26}" -f "-"; continue }
		$fps = 1000.0 / [double]$s.mean_frame_ms
		$mark = if ([double]$s.mean_frame_ms -le $TargetMs) { "ok" } else { "too slow" }
		$line += " {0,26}" -f ([string]::Format([cultureinfo]::InvariantCulture, "{0:F1} ms {1:F0} fps {2}", [double]$s.mean_frame_ms, $fps, $mark))
	}
	Write-Host $line
}
