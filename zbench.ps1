# SPDX-License-Identifier: GPL-3.0-or-later
# The Zobolin benchmark tool's one command (see PLAN.md). It runs a scenario
# several times, notes the PC's details, checks that the frame rate isn't
# capped, and combines the repeats into summary.json.
#
#   powershell -ExecutionPolicy Bypass -File zbench.ps1 [-Scenario vista_quick|vista]
#       [-Repeats 3] [-Preset high|low] [-Renderer forward_plus|mobile]
#       [-Gpu auto|intel|nvidia|<number>] [-GpuProfile] [-CoolDown 20]
#       [-GameOptions <options for the game>] [-Game <game repo folder>]
#
# Results: results\<date>_<pc>_<commit>_<scenario>\ with one folder per
# repeat (r1, r2, ...: frames.csv, run.json, screenshots, Godot's output),
# session.json (the PC and settings) and summary.json (the combined numbers).

param(
	[string] $Scenario = "vista_quick",
	[ValidateRange(1, 20)] [int] $Repeats = 3,
	[ValidateSet("high", "low")] [string] $Preset = "high",
	[ValidateSet("forward_plus", "mobile")] [string] $Renderer = "forward_plus",
	[string] $Gpu = "auto",
	[switch] $GpuProfile,
	[ValidateRange(0, 600)] [int] $CoolDown = 20,
	[string[]] $GameOptions = @(),
	[string] $Game = "C:\Claude\Open World Game - Zobolin"
)

# Not "Stop": Godot writes warnings to its error output, which must not end the run.
Import-Module (Join-Path $PSScriptRoot "lib\Machine.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib\Stats.psm1") -Force

function Save-Json($Value, [string] $Path) {
	$Value | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 $Path
}

# --- What to run ---
$scenarioFile = Join-Path $PSScriptRoot "scenarios\$Scenario.json"
if (-not (Test-Path $scenarioFile)) {
	$known = (Get-ChildItem (Join-Path $PSScriptRoot "scenarios") -Filter *.json | ForEach-Object { $_.BaseName }) -join ", "
	Write-Host "Unknown scenario '$Scenario'. Known: $known" -ForegroundColor Red
	exit 1
}
$plan = Get-Content -Raw $scenarioFile | ConvertFrom-Json
$launcher = Join-Path $Game "tools\benchmark.ps1"
if (-not (Test-Path $launcher)) {
	Write-Host "The game's launcher is missing: $launcher" -ForegroundColor Red
	exit 1
}

# --- The PC ---
$machine = Get-MachineInfo $Game
$commit = $machine.game_commit
$short = if ($commit.Length -ge 7) { $commit.Substring(0, 7) } else { $commit }
$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$session = Join-Path $PSScriptRoot "results\$($stamp)_$($machine.pc)_$($short)_$Scenario"
New-Item -ItemType Directory -Force $session | Out-Null

Write-Host "Zobolin benchmark: $Scenario ($($plan.description))" -ForegroundColor Cyan
Write-Host "PC $($machine.pc): $($machine.processor), $($machine.ram_gb) GB"
foreach ($card in $machine.graphics_cards) { Write-Host "  graphics: $($card.name), driver $($card.driver)" }
Write-Host "  power plan: $($machine.power_plan.name)"
Write-Host "  game commit $short$(if ($machine.game_uncommitted_changes) { ' (with uncommitted changes)' })"
$warnings = @()
if (-not $machine.power_plan.full_speed) {
	$warnings += "The power plan is '$($machine.power_plan.name)', not High performance: the numbers may vary more."
}
if ($machine.on_battery) {
	$warnings += "This PC runs on its battery: plug it in, or the numbers will be lower and vary."
}
foreach ($w in $warnings) { Write-Host "WARNING: $w" -ForegroundColor Yellow }
$minutes = [math]::Ceiling($Repeats * (1.0 + $CoolDown / 60.0))
Write-Host "$Repeats runs, about $minutes minutes in all. Don't use the PC meanwhile."

$sessionInfo = [ordered]@{
	tool_version = "0.4"
	scenario = $Scenario
	scenario_plan = $plan
	repeats = $Repeats
	preset = $Preset
	renderer = $Renderer
	gpu = $Gpu
	gpu_profile = [bool]$GpuProfile
	cool_down_s = $CoolDown
	game_options = $GameOptions
	started = (Get-Date -Format "s")
	machine = $machine
	warnings = $warnings
	runs = @()
}

# --- The runs ---
$failed = $null
for ($r = 1; $r -le $Repeats; $r++) {
	$out = Join-Path $session "r$r"
	Write-Host ""
	Write-Host "Run $r of $Repeats" -ForegroundColor Cyan
	$options = @{
		Test = $plan.test; Preset = $Preset; Renderer = $Renderer; Gpu = $Gpu
		Record = $true; OutDir = $out; Extra = @($plan.extra) + $GameOptions
	}
	if ($plan.only) { $options.Only = $plan.only }
	if ($GpuProfile) { $options.GpuProfile = $true }
	$started = Get-Date
	& $launcher @options
	$code = $LASTEXITCODE
	$runInfo = [ordered]@{ repeat = $r; folder = "r$r"; seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1); ok = $false }
	$runFile = Join-Path $out "run.json"
	if ($code -ne 0 -or -not (Test-Path $runFile)) {
		$runInfo.problem = "The game run did not finish (see r$r\godot_log.txt)."
	} else {
		$run = Get-Content -Raw $runFile | ConvertFrom-Json
		$capped = @($run.segments | Where-Object { $_.frame_cap.looks_capped })
		if ($capped.Count -gt 0) {
			$names = ($capped | ForEach-Object { "$($_.name) (held at $($_.frame_cap.near_fps) fps)" }) -join ", "
			$runInfo.problem = "The frame rate is capped in: $names. That measures the cap, not the game. Switch vsync and any frame limit off in the graphics driver's settings (NVIDIA: 'Vertical sync' = 'Use the 3D application setting'; Intel: 'Vertical Sync' = 'Use application settings') and run again."
		} else {
			$runInfo.ok = $true
		}
	}
	$sessionInfo.runs += $runInfo
	Save-Json $sessionInfo (Join-Path $session "session.json")
	if (-not $runInfo.ok) {
		$failed = $runInfo.problem
		break
	}
	if ($r -lt $Repeats -and $CoolDown -gt 0) {
		Write-Host "Cooling down for $CoolDown s..."
		Start-Sleep -Seconds $CoolDown
	}
}
$sessionInfo.finished = (Get-Date -Format "s")
Save-Json $sessionInfo (Join-Path $session "session.json")
if ($failed) {
	Write-Host ""
	Write-Host "STOPPED: $failed" -ForegroundColor Red
	Write-Host "Results so far: $session"
	exit 1
}

# --- Combine the repeats ---
$runs = @()
for ($r = 1; $r -le $Repeats; $r++) {
	$runs += , (Get-Content -Raw (Join-Path $session "r$r\run.json") | ConvertFrom-Json)
}
$segments = @()
foreach ($first in $runs[0].segments) {
	$name = $first.name
	$per = @($runs | ForEach-Object { $_.segments | Where-Object { $_.name -eq $name } | Select-Object -First 1 })
	$frame = Get-NoiseBand ([double[]]@($per | ForEach-Object { $_.frame_ms.mean_ms }))
	$gpuBand = Get-NoiseBand ([double[]]@($per | ForEach-Object { $_.p50.gpu_ms }))
	$segment = [ordered]@{
		name = $name
		repeats = $per.Count
		mean_frame_ms = $frame.median
		frame_spread_share = $frame.spread_share
		noise_band_share = $frame.band_share
		p99_frame_ms = Get-Median ([double[]]@($per | ForEach-Object { $_.frame_ms.p99_ms }))
		slowest_1_percent_fps = Get-Median ([double[]]@($per | ForEach-Object { $_.frame_ms.slowest_1_percent_fps }))
		gpu_ms = $gpuBand.median
		gpu_spread_share = $gpuBand.spread_share
		gpu_bound_share = Get-Median ([double[]]@($per | ForEach-Object { $_.gpu_bound_share }))
		process_ms = Get-Median ([double[]]@($per | ForEach-Object { $_.p50.process_ms }))
		render_cpu_ms = Get-Median ([double[]]@($per | ForEach-Object { $_.p50.render_cpu_ms }))
		hitches = @($per | ForEach-Object { $_.frame_ms.hitches })
		per_repeat_mean_ms = @($per | ForEach-Object { $_.frame_ms.mean_ms })
	}
	$passes = [ordered]@{}
	foreach ($property in $first.p50.PSObject.Properties) {
		if ($property.Name.StartsWith("pass_")) {
			$passes[$property.Name] = Get-Median ([double[]]@($per | ForEach-Object { $_.p50.($property.Name) }))
		}
	}
	if ($passes.Count -gt 0) { $segment.gpu_passes_ms = $passes }
	$segments += $segment
}
$summary = [ordered]@{
	scenario = $Scenario
	repeats = $Repeats
	machine = $machine
	preset = $Preset
	renderer = $Renderer
	godot = $runs[0].meta.godot
	debug_build = $runs[0].meta.debug_build
	graphics_card_used = $runs[0].meta.graphics_card
	render_3d = $runs[0].meta.render_3d
	warnings = $warnings
	segments = $segments
}
Save-Json $summary (Join-Path $session "summary.json")

# --- Print ---
Write-Host ""
Write-Host "Summary ($Repeats runs, middle value of each):" -ForegroundColor Cyan
Write-Host ("{0,-24} {1,9} {2,8} {3,9} {4,8} {5,8} {6,9}  {7}" -f "view", "frame ms", "spread", "p99 ms", "gpu ms", "gpu-bnd", "stutters", "each run (ms)")
foreach ($s in $segments) {
	$each = ($s.per_repeat_mean_ms | ForEach-Object { "{0:N2}" -f $_ }) -join " / "
	Write-Host ("{0,-24} {1,9:N2} {2,7:N1}% {3,9:N2} {4,8:N2} {5,7:N0}% {6,9}  {7}" -f $s.name, $s.mean_frame_ms,
		($s.frame_spread_share * 100), $s.p99_frame_ms, $s.gpu_ms, ($s.gpu_bound_share * 100),
		(($s.hitches | Measure-Object -Sum).Sum), $each)
}
$worst = 0.0
foreach ($s in $segments) { $worst = [math]::Max($worst, $s.frame_spread_share) }
$band = [math]::Max($MinNoiseShare, $worst)
Write-Host ("Repeats differ by up to {0:N1}%: on this PC, changes smaller than {1:N1}% count as 'no change'." -f ($worst * 100), ($band * 100))
Write-Host "Results: $session" -ForegroundColor Green
