# SPDX-License-Identifier: GPL-3.0-or-later
# The Zobolin benchmark tool's one command (see PLAN.md). It runs a scenario
# several times, notes the PC's details, checks that the frame rate isn't
# capped, and combines the repeats into summary.json.
#
# With -Ablate it also runs the scenario once with each part of the game
# switched off (and once with all of them off), and works out what each
# part costs: the time saved when it is off. The variants run in turns
# (all on, grass off, trees off, ..., then again), so a PC warming up
# affects all of them alike.
#
#   powershell -ExecutionPolicy Bypass -File zbench.ps1 [-Scenario vista_quick|vista]
#       [-Ablate] [-Repeats 3] [-Preset high|low] [-Renderer forward_plus|mobile]
#       [-Gpu auto|intel|nvidia|<number>] [-GpuProfile] [-CoolDown 20]
#       [-GameOptions <options for the game>] [-Game <game repo folder>]
#
# Results: results\<date>_<pc>_<commit>_<scenario>\ with one folder per
# run (r1, r2, ...; with -Ablate <variant>\r1, ...: frames.csv, run.json,
# screenshots, Godot's output), session.json (the PC and settings) and
# summary.json (the combined numbers and, with -Ablate, the costs).

param(
	[string] $Scenario = "vista_quick",
	[switch] $Ablate,
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
# Note: PowerShell doesn't tell upper and lower case apart in names, so no
# variable here may share a name with an option above ($gpu would be $Gpu).
Import-Module (Join-Path $PSScriptRoot "lib\Machine.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib\Stats.psm1") -Force

function Save-Json($Value, [string] $Path) {
	$Value | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 $Path
}

function Get-MedianOf($Items, [scriptblock] $Pick) {
	return Get-Median ([double[]]@($Items | ForEach-Object $Pick))
}

# One variant's repeats (run.json files) combined, view by view.
function Join-Repeats($RunList) {
	$combined = @()
	foreach ($first in $RunList[0].segments) {
		$name = $first.name
		$per = @($RunList | ForEach-Object { $_.segments | Where-Object { $_.name -eq $name } | Select-Object -First 1 })
		$frameBand = Get-NoiseBand ([double[]]@($per | ForEach-Object { $_.frame_ms.mean_ms }))
		$gpuBand = Get-NoiseBand ([double[]]@($per | ForEach-Object { $_.p50.gpu_ms }))
		$segment = [ordered]@{
			name = $name
			repeats = $per.Count
			mean_frame_ms = $frameBand.median
			frame_spread_share = $frameBand.spread_share
			noise_band_share = $frameBand.band_share
			p99_frame_ms = Get-MedianOf $per { $_.frame_ms.p99_ms }
			slowest_1_percent_fps = Get-MedianOf $per { $_.frame_ms.slowest_1_percent_fps }
			gpu_ms = $gpuBand.median
			gpu_spread_share = $gpuBand.spread_share
			gpu_bound_share = Get-MedianOf $per { $_.gpu_bound_share }
			process_ms = Get-MedianOf $per { $_.p50.process_ms }
			draw_ms = Get-MedianOf $per { $_.p50.draw_ms }
			render_cpu_ms = Get-MedianOf $per { $_.p50.render_cpu_ms }
			draw_calls = Get-MedianOf $per { $_.p50.draw_calls }
			shadow_draw_calls = Get-MedianOf $per { $_.p50.shadow_draw_calls }
			primitives = Get-MedianOf $per { $_.p50.primitives }
			hitches = @($per | ForEach-Object { $_.frame_ms.hitches })
			per_repeat_mean_ms = @($per | ForEach-Object { $_.frame_ms.mean_ms })
		}
		$passes = [ordered]@{}
		foreach ($property in $first.p50.PSObject.Properties) {
			if ($property.Name.StartsWith("pass_")) {
				$passName = $property.Name
				$passes[$passName] = Get-MedianOf $per { $_.p50.$passName }
			}
		}
		if ($passes.Count -gt 0) { $segment.gpu_passes_ms = $passes }
		$combined += $segment
	}
	return , $combined
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
$variants = @([ordered]@{ name = "all_on"; off = @() })
if ($Ablate) {
	$parts = @($plan.switches)
	if ($parts.Count -eq 0) {
		Write-Host "Scenario '$Scenario' lists no parts to switch off ('switches')." -ForegroundColor Red
		exit 1
	}
	# "switches" are separate parts; "detail_switches" are pieces of them
	# (the trees' shadows are part of the trees), measured one by one but
	# left out of "all off" and of adding the parts up.
	foreach ($part in $parts) { $variants += [ordered]@{ name = "$($part)_off"; off = @($part); detail = $false } }
	foreach ($part in @($plan.detail_switches)) {
		if ($part) { $variants += [ordered]@{ name = "$($part)_off"; off = @($part); detail = $true } }
	}
	$variants += [ordered]@{ name = "all_off"; off = $parts; detail = $false }
}

# --- The PC ---
$machine = Get-MachineInfo $Game
$commit = $machine.game_commit
$short = if ($commit.Length -ge 7) { $commit.Substring(0, 7) } else { $commit }
$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$label = if ($Ablate) { "$($Scenario)_ablate" } else { $Scenario }
$session = Join-Path $PSScriptRoot "results\$($stamp)_$($machine.pc)_$($short)_$label"
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
$total = $Repeats * $variants.Count
$minutes = [math]::Ceiling($total * 0.5 + ($Repeats - 1) * $CoolDown / 60.0)
if ($Ablate) { Write-Host "Variants: $(($variants | ForEach-Object { $_.name }) -join ', ')" }
Write-Host "$total runs, about $minutes minutes in all. Don't use the PC meanwhile."

$sessionInfo = [ordered]@{
	tool_version = "0.5"
	scenario = $Scenario
	scenario_plan = $plan
	ablate = [bool]$Ablate
	variants = $variants
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

# --- The runs: round after round, each round all variants in turn ---
$failed = $null
$done = 0
for ($r = 1; $r -le $Repeats -and -not $failed; $r++) {
	foreach ($variant in $variants) {
		$done++
		$folder = if ($Ablate) { "$($variant.name)\r$r" } else { "r$r" }
		$out = Join-Path $session $folder
		Write-Host ""
		Write-Host "Run $done of $total$(if ($Ablate) { ": $($variant.name), round $r" })" -ForegroundColor Cyan
		$extra = @($plan.extra) + $GameOptions
		if ($variant.off.Count -gt 0) { $extra += "--off=$($variant.off -join ',')" }
		$options = @{
			Test = $plan.test; Preset = $Preset; Renderer = $Renderer; Gpu = $Gpu
			Record = $true; OutDir = $out; Extra = $extra
		}
		if ($plan.only) { $options.Only = $plan.only }
		if ($GpuProfile) { $options.GpuProfile = $true }
		$started = Get-Date
		& $launcher @options
		$code = $LASTEXITCODE
		$runInfo = [ordered]@{
			variant = $variant.name; repeat = $r; folder = $folder
			seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1); ok = $false
		}
		$runFile = Join-Path $out "run.json"
		if ($code -ne 0 -or -not (Test-Path $runFile)) {
			$runInfo.problem = "The game run did not finish (see $folder\godot_log.txt)."
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
	}
	if (-not $failed -and $r -lt $Repeats -and $CoolDown -gt 0) {
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

# --- Combine the repeats of each variant ---
$byVariant = [ordered]@{}
$firstRun = $null
foreach ($variant in $variants) {
	$runList = @()
	for ($r = 1; $r -le $Repeats; $r++) {
		$folder = if ($Ablate) { "$($variant.name)\r$r" } else { "r$r" }
		$runList += , (Get-Content -Raw (Join-Path $session "$folder\run.json") | ConvertFrom-Json)
	}
	if ($null -eq $firstRun) { $firstRun = $runList[0] }
	$byVariant[$variant.name] = Join-Repeats $runList
}
$segments = $byVariant["all_on"]

# --- What each part costs: all on minus that part off ---
$costs = @()
if ($Ablate) {
	foreach ($variant in ($variants | Where-Object { $_.name -ne "all_on" })) {
		$offSegments = $byVariant[$variant.name]
		$views = @()
		$verified = $false
		foreach ($on in $segments) {
			$off = $offSegments | Where-Object { $_.name -eq $on.name } | Select-Object -First 1
			$frameSaving = $on.mean_frame_ms - $off.mean_frame_ms
			$gpuSaving = $on.gpu_ms - $off.gpu_ms
			# Outside the noise of the all-on repeats (and of this variant's).
			$noise = [math]::Max($on.noise_band_share, $off.noise_band_share) * $on.mean_frame_ms
			$fewerCalls = ($on.draw_calls + $on.shadow_draw_calls) - ($off.draw_calls + $off.shadow_draw_calls)
			$fewerPrimitives = $on.primitives - $off.primitives
			# The switch did something if it took away draw calls or triangles.
			if ($fewerCalls -gt 0 -or $fewerPrimitives -gt 0.01 * $on.primitives) { $verified = $true }
			$views += [ordered]@{
				view = $on.name
				frame_saving_ms = $frameSaving
				gpu_saving_ms = $gpuSaving
				share_of_frame = if ($on.mean_frame_ms -gt 0) { $frameSaving / $on.mean_frame_ms } else { 0 }
				outside_noise = ([math]::Abs($frameSaving) -gt $noise)
				fewer_draw_calls = $fewerCalls
				fewer_primitives = $fewerPrimitives
			}
		}
		$meanFrame = ($views | ForEach-Object { $_.frame_saving_ms } | Measure-Object -Average).Average
		$meanGpu = ($views | ForEach-Object { $_.gpu_saving_ms } | Measure-Object -Average).Average
		# What the game says about each switch, in every round: what it takes
		# away, how to check it, and whether it was still off at the end.
		$removes = @()
		$method = "counts"
		$held = $true
		for ($r = 1; $r -le $Repeats; $r++) {
			$offRun = Get-Content -Raw (Join-Path $session "$($variant.name)\r$r\run.json") | ConvertFrom-Json
			foreach ($property in @($offRun.off.PSObject.Properties)) {
				if ($r -eq 1) { $removes += $property.Value.removes }
				if ($property.Value.check -eq "setting" -and $variant.off.Count -eq 1) { $method = "setting" }
				if (-not $property.Value.still_off) { $held = $false }
			}
		}
		$faster = @($views | Where-Object { $_.outside_noise -and $_.frame_saving_ms -gt 0 }).Count -gt 0
		if (-not $held) {
			$verified = $false
			$check = "NO: something switched it back on during the run"
		} elseif ($method -eq "setting") {
			$verified = $faster
			$check = if ($faster) { "yes (setting held, frame faster)" } else { "setting held, but no measurable saving" }
		} else {
			$check = if ($verified) { "yes (fewer draw calls or triangles)" } else { "NO: nothing less was drawn" }
		}
		$costs += [ordered]@{
			variant = $variant.name
			off = $variant.off
			detail = [bool]$variant.detail
			removes = $removes -join "; "
			check_method = $method
			verified = $verified
			check = $check
			mean_frame_saving_ms = $meanFrame
			mean_gpu_saving_ms = $meanGpu
			views = $views
		}
	}
}

# Do the parts' costs add up to everything off? If not, they affect each other.
$interaction = @()
if ($Ablate) {
	foreach ($on in $segments) {
		$sum = 0.0
		foreach ($c in ($costs | Where-Object { $_.variant -ne "all_off" -and -not $_.detail })) {
			$sum += ($c.views | Where-Object { $_.view -eq $on.name } | Select-Object -First 1).frame_saving_ms
		}
		$all = ($costs | Where-Object { $_.variant -eq "all_off" } | Select-Object -First 1).views |
			Where-Object { $_.view -eq $on.name } | Select-Object -First 1
		$interaction += [ordered]@{
			view = $on.name; sum_of_parts_ms = $sum; all_off_saving_ms = $all.frame_saving_ms
			floor_frame_ms = $on.mean_frame_ms - $all.frame_saving_ms
		}
	}
}

$summary = [ordered]@{
	scenario = $Scenario
	ablate = [bool]$Ablate
	repeats = $Repeats
	machine = $machine
	preset = $Preset
	renderer = $Renderer
	godot = $firstRun.meta.godot
	debug_build = $firstRun.meta.debug_build
	graphics_card_used = $firstRun.meta.graphics_card
	render_3d = $firstRun.meta.render_3d
	warnings = $warnings
	segments = $segments
}
if ($Ablate) {
	$summary.variants = $byVariant
	$summary.costs = $costs
	$summary.interaction = $interaction
}
Save-Json $summary (Join-Path $session "summary.json")

# --- Print ---
Write-Host ""
Write-Host "Summary ($Repeats runs$(if ($Ablate) { ' of everything on' }), middle value of each):" -ForegroundColor Cyan
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

if ($Ablate) {
	Write-Host ""
	Write-Host "What each part costs (frame time saved when it is off, ms; * = inside the noise):" -ForegroundColor Cyan
	Write-Host "(Lines starting with '-' are pieces of a part above, such as the trees' shadows.)"
	$header = "{0,-22}" -f "part"
	foreach ($s in $segments) { $header += " {0,14}" -f ($s.name.Substring(0, [math]::Min(14, $s.name.Length))) }
	$header += " {0,8} {1,8}  {2}" -f "average", "gpu avg", "switch worked?"
	Write-Host $header
	$ranked = @($costs | Where-Object { $_.variant -ne "all_off" -and -not $_.detail } | Sort-Object { $_.mean_frame_saving_ms } -Descending)
	$ranked += @($costs | Where-Object { $_.detail } | Sort-Object { $_.mean_frame_saving_ms } -Descending)
	$ranked += @($costs | Where-Object { $_.variant -eq "all_off" })
	foreach ($c in $ranked) {
		$line = "{0,-22}" -f $(if ($c.detail) { "- $($c.variant)" } else { $c.variant })
		foreach ($v in $c.views) {
			$mark = if ($v.outside_noise) { " " } else { "*" }
			$line += " {0,13:N2}{1}" -f $v.frame_saving_ms, $mark
		}
		$check = $c.check
		$line += " {0,8:N2} {1,8:N2}  {2}" -f $c.mean_frame_saving_ms, $c.mean_gpu_saving_ms, $check
		Write-Host $line
	}
	Write-Host ""
	Write-Host "Do the parts add up to everything off? (if not, they affect each other)"
	foreach ($i in $interaction) {
		Write-Host ("  {0,-24} parts together {1,6:N2} ms, everything off {2,6:N2} ms, frame with everything off {3,6:N2} ms" -f $i.view,
			$i.sum_of_parts_ms, $i.all_off_saving_ms, $i.floor_frame_ms)
	}
}
Write-Host "Results: $session" -ForegroundColor Green
