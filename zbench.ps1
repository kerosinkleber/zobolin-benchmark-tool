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
#       [-Ablate [-Kind all|gpu|cpu]] [-Repeats 3] [-Preset high|low] [-Renderer forward_plus|mobile]
#       [-Gpu auto|intel|nvidia|<number>] [-GpuProfile] [-CoolDown 20]
#       [-GameOptions <options for the game>] [-Game <game repo folder; default: "Open World Game - Zobolin" next to this folder>]
#       [-SaveBaseline] [-Baseline <summary.json to compare with>] [-ColdCache]
#   powershell -ExecutionPolicy Bypass -File zbench.ps1 -Reanalyse <results folder>
#
# Start-up (-Scenario load, and any run with -ColdCache): how long the game
# takes from its start to the first measured frame, and where that time
# goes (landscape, forest and tree pictures, the benchmark's waits, the
# rest), in summary.json's "load" block and a "Start-up" table.
# -ColdCache deletes Godot's caches for the game before every run (the
# compiled shaders, the graphics card's pipelines, the tree pictures; only
# those, and it says what it deleted), so each run starts cold.
#
# -Reanalyse works out summary.json again from a finished session's runs,
# without running the game (for example after a change to the statistics).
#
# Baselines: -SaveBaseline keeps this session's summary as this PC's
# baseline for the scenario (baselines\<pc>\<scenario>_<preset>_<renderer>.json).
# Every later session of the same kind is compared with it (or with the
# summary.json named by -Baseline): "faster", "slower" or "no change" per
# view, counting only changes over 5 % and outside the noise.
#
# A scenario with "variants" (for example 8, 16, 32, 64 NPCs) is a sweep:
# every variant runs in turns, and the tool fits a straight line through
# the costs to show how they grow.
#
# Results: results\<date>_<pc>_<commit>_<scenario>\ with one folder per
# run (r1, r2, ...; with -Ablate <variant>\r1, ...: frames.csv, run.json,
# screenshots, Godot's output), session.json (the PC and settings) and
# summary.json (the combined numbers and, with -Ablate, the costs).

param(
	[string] $Scenario = "vista_quick",
	[switch] $Ablate,
	[string[]] $Only = @(),
	[ValidateSet("all", "gpu", "cpu")] [string] $Kind = "all",
	[ValidateRange(1, 20)] [int] $Repeats = 3,
	[ValidateSet("high", "low")] [string] $Preset = "high",
	[ValidateSet("forward_plus", "mobile")] [string] $Renderer = "forward_plus",
	[string] $Gpu = "auto",
	[switch] $GpuProfile,
	[ValidateRange(0, 600)] [int] $CoolDown = 20,
	[string[]] $GameOptions = @(),
	[string] $Game = "",
	[string] $Reanalyse = "",
	[switch] $SaveBaseline,
	[string] $Baseline = "",
	[switch] $ColdCache
)

# Several game options may come as one string ("--npcs=8 --grass=off"),
# as `powershell -File` passes them: split them at spaces.
$GameOptions = @($GameOptions | ForEach-Object { $_ -split '\s+' } | Where-Object { $_ })
# The game's folder: -Game, else the folder "Open World Game - Zobolin"
# next to this one (as on every PC so far), else C:\Claude\....
if (-not $Game) {
	$besideTool = Join-Path (Split-Path $PSScriptRoot -Parent) "Open World Game - Zobolin"
	$Game = if (Test-Path (Join-Path $besideTool "tools\benchmark.ps1")) { $besideTool } else { "C:\Claude\Open World Game - Zobolin" }
}
# Not "Stop": Godot writes warnings to its error output, which must not end the run.
# Note: PowerShell doesn't tell upper and lower case apart in names, so no
# variable here may share a name with an option above ($gpu would be $Gpu).
Import-Module (Join-Path $PSScriptRoot "lib\Machine.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib\Stats.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib\Pictures.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib\Report.psm1") -Force
# A processor switch must leave the picture as it is: screenshots may
# differ by at most this much (0 to 1) from everything on. Repeats and
# working switches differ by 0.0000; re-centring off (grass gone far from
# the centre) by 0.008.
$PictureLimit = 0.002

function Save-Json($Value, [string] $Path) {
	$Value | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 $Path
}

function Get-MedianOf($Items, [scriptblock] $Pick) {
	return Get-Median ([double[]]@($Items | ForEach-Object $Pick))
}

# --- Start-up: the game's caches (-ColdCache) ---
# Where Godot 4.7 keeps this project's caches, as found on the development
# PC (2026-11-08): the game's runs write the compiled shaders to
# user://shader_cache and the graphics card's pipelines to
# user://vulkan/pipelines.<renderer>.<card>.cache (both updated by every
# run; the ".editor.cache" one is the editor's and is kept); the editor
# keeps its own compiled shaders in game\.godot\shader_cache (deleted too,
# so no copy of them is left); the tree pictures are in the folder that
# TreeImpostorBaker.CACHE_DIR names (user://cache/tree_pictures). user://
# is %APPDATA%\Godot\app_userdata\<config/name from project.godot>.
# Each entry: the folder, the name it must have, what may be in it, and the
# folder it must be inside. A "files_only" entry deletes only the matching
# files in the folder, not the folder.
function Get-GameCaches([string] $GameRoot) {
	$projectFile = Join-Path $GameRoot "game\project.godot"
	if (-not (Test-Path $projectFile)) { throw "There is no game\project.godot in $GameRoot." }
	$projectText = Get-Content -Raw $projectFile
	if ($projectText -match '(?m)^config/use_custom_user_dir\s*=\s*true') {
		throw "The project keeps its user data in a folder of its own (use_custom_user_dir): the tool doesn't know where its caches are, so it deletes nothing."
	}
	if ($projectText -notmatch '(?m)^config/name\s*=\s*"([^"]+)"') { throw "No config/name in $projectFile." }
	$projectName = $Matches[1]
	if ($projectName -match '[\\/:*?"<>|]' -or $projectName.Trim(' ', '.').Length -eq 0) {
		throw "The project's name '$projectName' can't be a folder name: the tool deletes nothing."
	}
	$appData = [Environment]::GetFolderPath("ApplicationData")
	if (-not $appData) { throw "Windows doesn't say where the user's application data is: the tool deletes nothing." }
	$userDir = [IO.Path]::GetFullPath((Join-Path $appData "Godot\app_userdata\$projectName"))
	$bakerFile = Join-Path $GameRoot "game\world\tree_impostor_baker.gd"
	if (-not (Test-Path $bakerFile)) { throw "The tree picture baker is missing ($bakerFile): the tool doesn't know where the tree pictures are." }
	if ((Get-Content -Raw $bakerFile) -notmatch 'const CACHE_DIR: String = "user://([^"]+)"') {
		throw "The tree picture baker's CACHE_DIR isn't a user:// folder any more: check where the tree pictures are kept."
	}
	$picturesRelative = $Matches[1].TrimEnd('/')
	if ($picturesRelative -ne "cache/tree_pictures") {
		throw "The tree pictures moved to user://$picturesRelative; check it is a cache folder and update zbench.ps1 (Get-GameCaches)."
	}
	$projectCache = [IO.Path]::GetFullPath((Join-Path $GameRoot "game\.godot"))
	return @(
		[ordered]@{ what = "compiled shaders (the game's)"; path = Join-Path $userDir "shader_cache"; leaf = "shader_cache"; inside = $userDir; files = '\.cache$' },
		[ordered]@{ what = "compiled shaders (the editor's)"; path = Join-Path $projectCache "shader_cache"; leaf = "shader_cache"; inside = $projectCache; files = '\.cache$' },
		[ordered]@{ what = "tree pictures"; path = Join-Path $userDir "cache\tree_pictures"; leaf = "tree_pictures"; inside = (Join-Path $userDir "cache"); files = '\.png$' },
		[ordered]@{ what = "graphics card pipelines (the game's)"; path = Join-Path $userDir "vulkan"; leaf = "vulkan"; inside = $userDir; files = '^pipelines\..+\.cache$'; keep = '\.editor\.cache$'; files_only = $true }
	)
}

# Why a cache entry must not be deleted, or $null if it may. It must be the
# folder named, inside the folder named, no link to somewhere else, and hold
# only the cache's own files.
function Get-CacheProblem($Cache) {
	$full = [IO.Path]::GetFullPath($Cache.path)
	$inside = [IO.Path]::GetFullPath($Cache.inside).TrimEnd('\')
	if ((Split-Path $full -Leaf) -ne $Cache.leaf) { return "$full is not a folder called $($Cache.leaf)" }
	if (-not $full.StartsWith($inside + "\", [StringComparison]::OrdinalIgnoreCase)) { return "$full is not inside $inside" }
	if ($Cache.inside -notmatch '\\Godot\\app_userdata\\[^\\]+(\\cache)?$' -and $Cache.inside -notmatch '\\game\\\.godot$') {
		return "$inside is neither Godot's user data folder nor the project's .godot folder"
	}
	if (-not (Test-Path -LiteralPath $full)) { return $null }
	$folder = Get-Item -LiteralPath $full -Force
	if (-not $folder.PSIsContainer) { return "$full is a file, not a folder" }
	if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) { return "$full is a link to another folder" }
	$items = if ($Cache.files_only) { @(Get-ChildItem -LiteralPath $full -Force -File) } else { @(Get-ChildItem -LiteralPath $full -Force -Recurse) }
	foreach ($item in $items) {
		if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return "$($item.FullName) is a link" }
		if ($item.PSIsContainer) { continue }
		if ($Cache.files_only) { continue }
		if ($item.Name -notmatch $Cache.files) { return "$($item.FullName) is not a cache file (expected only files matching $($Cache.files))" }
	}
	return $null
}

# Deletes the game's caches (see Get-GameCaches), after checking every one
# of them first; stops (throws) without deleting anything if one doesn't
# look like a cache. Returns what it deleted.
function Clear-GameCaches([string] $GameRoot) {
	$caches = Get-GameCaches $GameRoot
	foreach ($cache in $caches) {
		$problem = Get-CacheProblem $cache
		if ($problem) { throw "Not deleting the caches: $problem." }
	}
	$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Godot*" })
	if ($running.Count -gt 0) {
		Write-Host "WARNING: Godot is running ($($running.Count) programs): it may write its caches back meanwhile, so this run may start less cold." -ForegroundColor Yellow
	}
	$deleted = @()
	foreach ($cache in $caches) {
		$full = [IO.Path]::GetFullPath($cache.path)
		$entry = [ordered]@{ what = $cache.what; path = $full; files = 0; mb = 0.0 }
		if (Test-Path -LiteralPath $full) {
			if ($cache.files_only) {
				$files = @(Get-ChildItem -LiteralPath $full -Force -File | Where-Object { $_.Name -match $cache.files -and -not ($cache.keep -and $_.Name -match $cache.keep) })
			} else {
				$files = @(Get-ChildItem -LiteralPath $full -Force -Recurse -File)
			}
			$entry.files = $files.Count
			$entry.mb = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
			if ($cache.files_only) {
				foreach ($file in $files) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop }
				$entry.names = @($files | ForEach-Object { $_.Name })
			} else {
				# Not Remove-Item -Recurse: in Windows PowerShell it can leave
				# files behind without an error. A file another program still
				# has open goes only when that program lets go: try a few times.
				$lastError = "it is still there"
				for ($try = 1; $try -le 5 -and (Test-Path -LiteralPath $full); $try++) {
					try { [IO.Directory]::Delete($full, $true) } catch { if ($try -eq 5) { $lastError = $_.Exception.Message } else { Start-Sleep -Milliseconds 400 } }
				}
				if (Test-Path -LiteralPath $full) { throw "Could not delete $full ($lastError; a program may hold a file in it)." }
			}
		}
		$what = if ($entry.files -gt 0) { "deleted $($entry.files) files, $($entry.mb) MB" } else { "was empty or not there" }
		Write-Host ("Cold cache: {0}: {1} ({2})" -f $cache.what, $full, $what)
		$deleted += $entry
	}
	return , $deleted
}

# --- Start-up: where a run's time went before its first measured frame ---
# The run starts when zbench calls the game's launcher (started_at in
# session.json; for older sessions: when Godot's output was written, minus
# the run's seconds). The first view's measuring ends when its screenshot
# is written, so its start is the screenshot's time minus the view's
# measured seconds (this includes writing the picture, about 0.1-0.3 s).
function Get-StartupOfRun([string] $SessionDir, $Entry, [bool] $WasCold, [double] $WaitsS) {
	$dir = Join-Path $SessionDir $Entry.folder
	$runFile = Join-Path $dir "run.json"
	if (-not (Test-Path $runFile)) { return $null }
	$run = Get-Content -Raw $runFile | ConvertFrom-Json
	$first = @($run.segments)[0]
	$info = [ordered]@{ folder = $Entry.folder; cache = if ($WasCold) { "cold" } else { "warm" }; first_view = $first.name }
	$resultsFile = Join-Path $dir "results.json"
	$results = if (Test-Path $resultsFile) { Get-Content -Raw $resultsFile | ConvertFrom-Json } else { $null }
	$logFile = Join-Path $dir "godot_log.txt"
	$landscapeMs = $null
	if ($results -and $null -ne $results.landscape_build_ms) { $landscapeMs = [double]$results.landscape_build_ms }
	elseif ((Test-Path $logFile) -and ((Get-Content -Raw $logFile) -match 'Terrain test ready: landscape built in ([\d.]+) s')) {
		$landscapeMs = [double]::Parse($Matches[1], [cultureinfo]::InvariantCulture) * 1000.0
	}
	$info.landscape_build_ms = $landscapeMs
	$info.forest_setup_ms = if ($results -and $null -ne $results.forest_setup_ms) { [double]$results.forest_setup_ms } else { $null }
	$info.tree_picture_rows_from_cache = if ($results) { $results.tree_picture_rows_from_cache } else { $null }
	$info.tree_picture_rows_photographed = if ($results) { $results.tree_picture_rows_photographed } else { $null }
	$info.shader_compiles_first_view = $first.shader_compiles
	$info.first_view_max_frame_ms = $first.frame_ms.max_ms
	$info.first_view_p50_frame_ms = $first.frame_ms.p50_ms
	$info.first_view_hitches = $first.frame_ms.hitches
	# The first measured frames: the very first one, and how many were over
	# 1.5 times the view's middle frame (not yet steady).
	$framesFile = Join-Path $dir "frames.csv"
	if (Test-Path $framesFile) {
		$rows = @(Import-Csv $framesFile | Where-Object { $_.segment -eq $first.name })
		if ($rows.Count -gt 0) {
			$info.first_frame_ms = [double]::Parse($rows[0].frame_ms, [cultureinfo]::InvariantCulture)
			$limit = 1.5 * [double]$first.frame_ms.p50_ms
			$info.unsteady_frames = @($rows | Where-Object { [double]::Parse($_.frame_ms, [cultureinfo]::InvariantCulture) -gt $limit }).Count
		}
	}
	# When the run started.
	$startedAt = $null
	if ($Entry.started_at) {
		$startedAt = if ($Entry.started_at -is [datetime]) { $Entry.started_at } else { [datetime]::Parse([string]$Entry.started_at, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
		$info.start_from = "started_at"
	} elseif (Test-Path $logFile) {
		$startedAt = (Get-Item $logFile).LastWriteTime.AddSeconds(-[double]$Entry.seconds)
		$info.start_from = "log time minus run seconds"
	}
	$info.run_seconds = [double]$Entry.seconds
	$shot = Join-Path $dir "$($first.name).png"
	if ($startedAt -and (Test-Path $shot)) {
		# LastWriteTime, not CreationTime: a copied session keeps the former
		# but gets a new creation time, which would spoil the start-up time.
		$shotAt = (Get-Item $shot).LastWriteTime
		$untilShot = ($shotAt.ToUniversalTime() - $startedAt.ToUniversalTime()).TotalSeconds
		$toFirst = $untilShot - [double]$first.seconds
		$info.to_first_frame_s = [math]::Round($toFirst, 2)
		$info.after_first_view_s = [math]::Round([double]$Entry.seconds - $untilShot, 2)
		$info.benchmark_waits_s = $WaitsS
		if ($null -ne $landscapeMs -and $null -ne $info.forest_setup_ms) {
			# Engine start, loading the scene, houses and rocks, grass, the sky...
			$info.other_s = [math]::Round($toFirst - $landscapeMs / 1000.0 - $info.forest_setup_ms / 1000.0 - $WaitsS, 2)
		}
	}
	return $info
}

# One variant's repeats (run.json files) combined, view by view.
## How long a segment's drawing waited, per frame on average, for something
## that is neither the game's own graphics-card work nor its own scripts and
## physics: draw time - graphics-card time - scripts - physics. Normally it
## is below zero to about 1.5 ms (over about 1280 saved segments from
## undisturbed runs the most was 1.4 ms; adding many items makes it far
## below zero, as their creation is counted in the scripts as well). When
## another program uses the graphics card, the game's frames wait for it
## and this grows (a forest run with something else running: 20.3 ms, the
## same run alone: -1.5 ms).
function Get-OutsideWait($Segment) {
	$m = $Segment.mean
	if ($null -eq $m -or $null -eq $m.draw_ms -or $null -eq $m.gpu_ms) { return $null }
	return [double]$m.draw_ms - [double]$m.gpu_ms - [double]$m.process_ms - [double]$m.physics_ms
}

## Above this many ms per frame, a run probably shared the PC with another
## program (see Get-OutsideWait).
$OutsideWaitLimitMs = 3.0

## Warnings for runs whose frames waited for something outside the game.
function Get-OutsideWaitWarnings($ByVariant) {
	$found = @()
	foreach ($variantName in $ByVariant.Keys) {
		foreach ($s in @($ByVariant[$variantName])) {
			$waits = @($s.per_repeat_outside_wait_ms)
			for ($i = 0; $i -lt $waits.Count; $i++) {
				if ($null -ne $waits[$i] -and $waits[$i] -gt $OutsideWaitLimitMs) {
					# Named like the run's folder: r2, or lamps_off\r2.
					$where = if ($ByVariant.Count -gt 1) { "$variantName\" } else { "" }
					$found += ("Run {1}r{0} ({2}): each frame waited {3:N1} ms for something outside the game (most likely another program using the graphics card): its numbers are too slow. Close other programs and run again." -f ($i + 1), $where, $s.name, $waits[$i])
				}
			}
		}
	}
	return $found
}

function Join-Repeats($RunList) {
	$combined = @()
	foreach ($first in $RunList[0].segments) {
		$name = $first.name
		$per = @($RunList | ForEach-Object { $_.segments | Where-Object { $_.name -eq $name } | Select-Object -First 1 })
		$frameBand = Get-NoiseBand ([double[]]@($per | ForEach-Object { $_.frame_ms.mean_ms }))
		$gpuBand = Get-NoiseBand ([double[]]@($per | ForEach-Object { $_.p50.gpu_ms }))
		# Processor time per frame: scripts plus physics, as averages (physics
		# runs only on some frames, so the middle frame can show none).
		$cpuBand = Get-NoiseBand ([double[]]@($per | ForEach-Object { [double]$_.mean.process_ms + [double]$_.mean.physics_ms }))
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
			gpu_noise_band_share = $gpuBand.band_share
			p99_noise_band_share = (Get-NoiseBand ([double[]]@($per | ForEach-Object { $_.frame_ms.p99_ms }))).band_share
			gpu_bound_share = Get-MedianOf $per { $_.gpu_bound_share }
			process_ms = Get-MedianOf $per { $_.p50.process_ms }
			process_mean_ms = Get-MedianOf $per { $_.mean.process_ms }
			physics_mean_ms = Get-MedianOf $per { $_.mean.physics_ms }
			cpu_ms = $cpuBand.median
			cpu_spread_share = $cpuBand.spread_share
			cpu_noise_band_share = $cpuBand.band_share
			draw_ms = Get-MedianOf $per { $_.p50.draw_ms }
			render_cpu_ms = Get-MedianOf $per { $_.p50.render_cpu_ms }
			draw_calls = Get-MedianOf $per { $_.p50.draw_calls }
			shadow_draw_calls = Get-MedianOf $per { $_.p50.shadow_draw_calls }
			primitives = Get-MedianOf $per { $_.p50.primitives }
			hitches = @($per | ForEach-Object { $_.frame_ms.hitches })
			per_repeat_mean_ms = @($per | ForEach-Object { $_.frame_ms.mean_ms })
			# Per run: how long drawing waited beyond the game's own graphics-card
			# time and its own processor work (see Get-OutsideWaitWarnings).
			per_repeat_outside_wait_ms = @($per | ForEach-Object { Get-OutsideWait $_ })
		}
		$passes = [ordered]@{}
		foreach ($property in $first.p50.PSObject.Properties) {
			if ($property.Name.StartsWith("pass_")) {
				$passName = $property.Name
				$passes[$passName] = Get-MedianOf $per { $_.p50.$passName }
			}
		}
		if ($passes.Count -gt 0) { $segment.gpu_passes_ms = $passes }
		# Stopwatch zones (step 8): average ms per frame and the slowest frame,
		# middle value over the repeats; plus what they leave unexplained.
		$zoneNames = @()
		foreach ($run in $per) {
			if ($run.zones) { foreach ($p in $run.zones.PSObject.Properties) { if ($zoneNames -notcontains $p.Name) { $zoneNames += $p.Name } } }
		}
		if ($zoneNames.Count -gt 0) {
			$zoneTable = [ordered]@{}
			foreach ($zoneName in ($zoneNames | Sort-Object)) {
				$zoneTable[$zoneName] = [ordered]@{
					mean_ms = Get-MedianOf $per { if ($_.zones.$zoneName) { $_.zones.$zoneName.mean_ms } else { 0 } }
					max_ms = Get-MedianOf $per { if ($_.zones.$zoneName) { $_.zones.$zoneName.max_ms } else { 0 } }
				}
			}
			$segment.zones = $zoneTable
			$segment.unattributed_process_ms = Get-MedianOf $per { $_.unattributed_process_ms }
			$segment.unattributed_physics_ms = Get-MedianOf $per { $_.unattributed_physics_ms }
		}
		# Stutters by main cause, over the repeats: the middle count, the
		# slowest stutter, and where (world x) in the first repeat.
		$causeNames = @()
		foreach ($run in $per) {
			if ($run.hitch_causes) { foreach ($p in $run.hitch_causes.PSObject.Properties) { if ($causeNames -notcontains $p.Name) { $causeNames += $p.Name } } }
		}
		if ($causeNames.Count -gt 0) {
			$causes = [ordered]@{}
			foreach ($causeName in $causeNames) {
				$counts = [double[]]@($per | ForEach-Object { if ($_.hitch_causes.$causeName) { $_.hitch_causes.$causeName.count } else { 0 } })
				$worst = 0.0
				foreach ($run in $per) { if ($run.hitch_causes.$causeName) { $worst = [math]::Max($worst, [double]$run.hitch_causes.$causeName.worst_ms) } }
				$firstAt = @()
				if ($per[0].hitch_causes.$causeName) { $firstAt = @($per[0].hitch_causes.$causeName.at_x) }
				$causes[$causeName] = [ordered]@{ count = Get-Median $counts; worst_ms = $worst; at_x = $firstAt }
			}
			$segment.hitch_causes = $causes
		}
		$combined += $segment
	}
	return , $combined
}

if ($Reanalyse) {
	# --- A finished session: take everything from its session.json ---
	$session = (Resolve-Path $Reanalyse).Path
	$sessionFile = Join-Path $session "session.json"
	if (-not (Test-Path $sessionFile)) {
		Write-Host "No session.json in $session" -ForegroundColor Red
		exit 1
	}
	$sessionInfo = Get-Content -Raw $sessionFile | ConvertFrom-Json
	$variants = @($sessionInfo.variants | Where-Object { $_ })
	# Sessions from before step 5a kept no variants: everything on only.
	if ($variants.Count -eq 0) { $variants = @([ordered]@{ name = "all_on"; off = @() }) }
	$expected = $variants.Count * [int]$sessionInfo.repeats
	$okRuns = @($sessionInfo.runs | Where-Object { $_.ok }).Count
	if ($okRuns -lt $expected) {
		Write-Host "That session has $okRuns good runs of $expected; it can't be analysed." -ForegroundColor Red
		exit 1
	}
	$Scenario = $sessionInfo.scenario
	$Repeats = [int]$sessionInfo.repeats
	$Ablate = [bool]$sessionInfo.ablate
	$Preset = $sessionInfo.preset
	$Renderer = $sessionInfo.renderer
	if ($sessionInfo.gpu) { $Gpu = $sessionInfo.gpu }
	$GpuProfile = [bool]$sessionInfo.gpu_profile
	$ColdCache = [bool]$sessionInfo.cold_cache
	$machine = $sessionInfo.machine
	$warnings = @($sessionInfo.warnings)
	$plan = $sessionInfo.scenario_plan
	$multi = $variants.Count -gt 1
	Write-Host "Analysing again: $session" -ForegroundColor Cyan
} else {

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
	$parts = @($plan.switches | Where-Object { $_ })
	# A scenario may list only processor switches (the NPC test has no
	# drawing switches); then there is no "all off" run.
	$anyParts = $parts.Count + @($plan.detail_switches | Where-Object { $_ }).Count + @($plan.cpu_switches | Where-Object { $_ }).Count
	if ($anyParts -eq 0) {
		Write-Host "Scenario '$Scenario' lists no parts to switch off ('switches')." -ForegroundColor Red
		exit 1
	}
	# "switches" are separate parts; "detail_switches" are pieces of them
	# (the trees' shadows are part of the trees), measured one by one but
	# left out of "all off" and of adding the parts up.
	# -Kind gpu runs only the drawing switches, -Kind cpu only the processor ones.
	if ($Kind -ne "cpu") {
		foreach ($part in $parts) { $variants += [ordered]@{ name = "$($part)_off"; off = @($part); detail = $false } }
		foreach ($part in @($plan.detail_switches)) {
			if ($part) { $variants += [ordered]@{ name = "$($part)_off"; off = @($part); detail = $true } }
		}
	}
	# "cpu_switches" stop processor or physics work; they are judged on the
	# processor's time, not the frame's, and also left out of "all off".
	if ($Kind -ne "gpu") {
		foreach ($part in @($plan.cpu_switches)) {
			if ($part) { $variants += [ordered]@{ name = "$($part)_off"; off = @($part); detail = $true; cpu = $true } }
		}
	}
	if ($Kind -ne "cpu" -and $parts.Count -gt 0) { $variants += [ordered]@{ name = "all_off"; off = $parts; detail = $false } }
	# -Only <switch>[,<switch>]: measure only these parts (CLAUDE.md, testing
	# rule 4: -Ablate only with the new part's own switch); no "all off".
	$Only = @($Only | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
	if ($Only.Count -gt 0) {
		$unknown = @($Only | Where-Object { $o = $_; -not ($variants | Where-Object { $_.name -eq "$($o)_off" }) })
		if ($unknown.Count -gt 0) {
			Write-Host "-Only: scenario '$Scenario' has no switch $($unknown -join ', ') (for this -Kind)." -ForegroundColor Red
			exit 1
		}
		$variants = @($variants | Where-Object { $_.name -eq "all_on" -or ($Only -contains ($_.name -replace '_off$', '') -and $_.name -ne "all_off") })
	}
} elseif ($plan.variants) {
	# A sweep: the same scene with more and more of something (for example
	# 8, 16, 32, 64 NPCs). Each variant has its own game options and a
	# number "x" (how many); the tool fits a straight line through the costs.
	$variants = @()
	foreach ($v in $plan.variants) {
		$variants += [ordered]@{ name = $v.name; off = @(); extra = @($v.extra); x = [double]$v.x }
	}
}

# --- The PC ---
$machine = Get-MachineInfo $Game
$commit = $machine.game_commit
$short = if ($commit.Length -ge 7) { $commit.Substring(0, 7) } else { $commit }
$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$label = if ($Ablate) { "$($Scenario)_ablate" } else { $Scenario }
if ($ColdCache) { $label += "_cold" }
# More than one variant: each run goes into <variant>\r<round>.
$multi = $variants.Count -gt 1
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
if ($multi) { Write-Host "Variants: $(($variants | ForEach-Object { $_.name }) -join ', ')" }
if ($ColdCache) {
	# Check now that every cache folder looks like one, before any run.
	try {
		foreach ($cacheEntry in (Get-GameCaches $Game)) {
			$problem = Get-CacheProblem $cacheEntry
			if ($problem) { throw "Not deleting the caches: $problem." }
		}
	} catch {
		Write-Host "STOPPED: $($_.Exception.Message)" -ForegroundColor Red
		exit 1
	}
	Write-Host "Cold start: Godot's caches for the game (compiled shaders, pipelines, tree pictures) are deleted before every run."
}
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
	cold_cache = [bool]$ColdCache
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
		$folder = if ($multi) { "$($variant.name)\r$r" } else { "r$r" }
		$out = Join-Path $session $folder
		Write-Host ""
		Write-Host "Run $done of $total$(if ($multi) { ": $($variant.name), round $r" })" -ForegroundColor Cyan
		$extra = @($plan.extra) + $GameOptions
		if ($variant.off.Count -gt 0) { $extra += "--off=$($variant.off -join ',')" }
		if ($variant.extra) { $extra += @($variant.extra) }
		$options = @{
			Test = $plan.test; Preset = $Preset; Renderer = $Renderer; Gpu = $Gpu
			Record = $true; OutDir = $out; Extra = $extra
		}
		if ($plan.only) { $options.Only = $plan.only }
		if ($GpuProfile) { $options.GpuProfile = $true }
		$clearedCaches = $null
		if ($ColdCache) {
			try {
				$clearedCaches = Clear-GameCaches $Game
			} catch {
				$sessionInfo.runs += [ordered]@{ variant = $variant.name; repeat = $r; folder = $folder; ok = $false; problem = $_.Exception.Message }
				$failed = $_.Exception.Message
				Save-Json $sessionInfo (Join-Path $session "session.json")
				break
			}
		}
		$started = Get-Date
		& $launcher @options
		$code = $LASTEXITCODE
		$runInfo = [ordered]@{
			variant = $variant.name; repeat = $r; folder = $folder
			seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1); ok = $false
			started_at = $started.ToString("o")
		}
		if ($ColdCache) { $runInfo.caches_deleted = $clearedCaches }
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
}  # end of: not -Reanalyse

# --- Combine the repeats of each variant ---
$byVariant = [ordered]@{}
$firstRun = $null
foreach ($variant in $variants) {
	$runList = @()
	for ($r = 1; $r -le $Repeats; $r++) {
		$folder = if ($multi) { "$($variant.name)\r$r" } else { "r$r" }
		$runList += , (Get-Content -Raw (Join-Path $session "$folder\run.json") | ConvertFrom-Json)
	}
	if ($null -eq $firstRun) { $firstRun = $runList[0] }
	$byVariant[$variant.name] = Join-Repeats $runList
}
$outsideWarnings = @(Get-OutsideWaitWarnings $byVariant)
$warnings = @($warnings) + $outsideWarnings
# The main numbers: everything on, or in a sweep the first (smallest) variant.
# (@() keeps a single view a list: PowerShell would unroll it.)
$segments = @(if ($byVariant.Contains("all_on")) { $byVariant["all_on"] } else { $byVariant[$variants[0].name] })

# --- A sweep: how the cost grows with the count (a straight line through it) ---
function Get-LineFit([double[]] $X, [double[]] $Y) {
	$n = $X.Count
	if ($n -lt 2) { return $null }
	$mx = ($X | Measure-Object -Average).Average
	$my = ($Y | Measure-Object -Average).Average
	$sxy = 0.0; $sxx = 0.0; $syy = 0.0
	for ($i = 0; $i -lt $n; $i++) {
		$sxy += ($X[$i] - $mx) * ($Y[$i] - $my)
		$sxx += ($X[$i] - $mx) * ($X[$i] - $mx)
		$syy += ($Y[$i] - $my) * ($Y[$i] - $my)
	}
	if ($sxx -eq 0) { return $null }
	$slope = $sxy / $sxx
	# How well the line fits: 1 = all points on it, 0 = no straight-line link.
	$r2 = if ($syy -gt 0) { ($sxy * $sxy) / ($sxx * $syy) } else { 1.0 }
	return [ordered]@{ slope = $slope; intercept = $my - $slope * $mx; r2 = $r2 }
}
$scaling = @()
$sweepVariants = @($variants | Where-Object { $null -ne $_.x })
if ($sweepVariants.Count -ge 2) {
	foreach ($first in $segments) {
		$xs = @(); $frames = @(); $cpus = @(); $physics = @(); $rows = @()
		foreach ($variant in $sweepVariants) {
			$seg = $byVariant[$variant.name] | Where-Object { $_.name -eq $first.name } | Select-Object -First 1
			if ($null -eq $seg) { continue }
			$xs += [double]$variant.x
			$frames += [double]$seg.mean_frame_ms
			$cpus += [double]$seg.cpu_ms
			$physics += [double]$seg.physics_mean_ms
			$rows += [ordered]@{ variant = $variant.name; x = [double]$variant.x; frame_ms = $seg.mean_frame_ms; p99_ms = $seg.p99_frame_ms; cpu_ms = $seg.cpu_ms; physics_ms = $seg.physics_mean_ms; process_ms = $seg.process_mean_ms; gpu_ms = $seg.gpu_ms; hitches = (Get-Median ([double[]]@($seg.hitches))) }
		}
		$scaling += [ordered]@{
			view = $first.name
			rows = $rows
			cpu_fit = Get-LineFit ([double[]]$xs) ([double[]]$cpus)
			frame_fit = Get-LineFit ([double[]]$xs) ([double[]]$frames)
		}
	}
}

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
			# Processor time saved: scripts plus physics, per frame on average.
			$cpuSaving = [double]$on.cpu_ms - [double]$off.cpu_ms
			$cpuNoise = [math]::Max([double]$on.cpu_noise_band_share, [double]$off.cpu_noise_band_share) * [double]$on.cpu_ms
			$views += [ordered]@{
				view = $on.name
				frame_saving_ms = $frameSaving
				gpu_saving_ms = $gpuSaving
				cpu_saving_ms = $cpuSaving
				share_of_frame = if ($on.mean_frame_ms -gt 0) { $frameSaving / $on.mean_frame_ms } else { 0 }
				outside_noise = ([math]::Abs($frameSaving) -gt $noise)
				cpu_outside_noise = ([math]::Abs($cpuSaving) -gt $cpuNoise)
				fewer_draw_calls = $fewerCalls
				fewer_primitives = $fewerPrimitives
			}
		}
		$meanFrame = ($views | ForEach-Object { $_.frame_saving_ms } | Measure-Object -Average).Average
		$meanGpu = ($views | ForEach-Object { $_.gpu_saving_ms } | Measure-Object -Average).Average
		$meanCpu = ($views | ForEach-Object { $_.cpu_saving_ms } | Measure-Object -Average).Average
		# What the game says about each switch, in every round: what it takes
		# away, how to check it, whether it was still off at the end, and for
		# processor switches whether its counter showed the work stopped.
		$removes = @()
		$method = "counts"
		$held = $true
		$stoppedAll = $true
		$evidence = @()
		$alreadyOff = $false
		for ($r = 1; $r -le $Repeats; $r++) {
			$offRun = Get-Content -Raw (Join-Path $session "$($variant.name)\r$r\run.json") | ConvertFrom-Json
			foreach ($property in @($offRun.off.PSObject.Properties)) {
				# Sessions from step 5a kept only the text: checked by counts.
				if ($property.Value -is [string]) {
					if ($r -eq 1) { $removes += $property.Value }
					continue
				}
				if ($r -eq 1) { $removes += $property.Value.removes }
				if ($property.Value.check -eq "setting" -and $variant.off.Count -eq 1) { $method = "setting" }
				# "adds": switching it off puts work back (it undoes a saving of the
				# low preset), so the frame should get slower, not faster.
				if ($property.Value.check -eq "adds" -and $variant.off.Count -eq 1) { $method = "adds" }
				# The part was already off in this preset (for example no shadows on
				# the water on low): no saving is expected.
				if ($property.Value.already_off -and $variant.off.Count -eq 1) { $alreadyOff = $true }
				if ($property.Value.check -eq "counter" -and $variant.off.Count -eq 1) {
					$method = "counter"
					if (-not $property.Value.work_stopped) { $stoppedAll = $false }
					if ($r -eq 1) { $evidence += $property.Value.evidence }
				}
				if (-not $property.Value.still_off) { $held = $false }
			}
		}
		$faster = @($views | Where-Object { $_.outside_noise -and $_.frame_saving_ms -gt 0 }).Count -gt 0
		$slower = @($views | Where-Object { $_.outside_noise -and $_.frame_saving_ms -lt 0 }).Count -gt 0
		# Processor switches must not change the picture: compare each view's
		# screenshot with everything on (first round of each).
		$changedViews = @()
		# A processor switch that takes away something visible (an NPC) may
		# change the picture: the scenario lists it in "visible_switches".
		$mayChangePicture = @($plan.visible_switches | Where-Object { $variant.off -contains $_ }).Count -gt 0
		if ($variant.cpu -and -not $mayChangePicture) {
			foreach ($v in $views) {
				$difference = Compare-Pictures (Join-Path $session "all_on\r1\$($v.view).png") (Join-Path $session "$($variant.name)\r1\$($v.view).png")
				$v.picture_difference = $difference
				if ($null -ne $difference -and $difference -gt $PictureLimit) { $changedViews += $v.view }
			}
		}
		if (-not $held) {
			$verified = $false
			$check = "NO: something switched it back on during the run"
		} elseif ($changedViews.Count -gt 0) {
			$verified = $false
			$check = "NO: the picture changed in $($changedViews -join ', '), so the saving is not only processor work"
		} elseif ($alreadyOff) {
			$verified = $true
			$check = "already off in this preset (nothing to save)"
		} elseif ($method -eq "adds") {
			$verified = $slower
			$check = if ($slower) { "yes (frame slower with it off: what the preset saves)" } else { "no measurable change (it only acts on the low preset)" }
		} elseif ($method -eq "counter") {
			$verified = $stoppedAll
			$pictureNote = if ($mayChangePicture) { "a visible part, picture not compared" } else { "picture unchanged" }
			$check = if ($stoppedAll) { "yes (counter: $($evidence -join '; '); $pictureNote)" } else { "NO: the work went on ($($evidence -join '; '))" }
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
			cpu = [bool]$variant.cpu
			removes = $removes -join "; "
			check_method = $method
			verified = $verified
			check = $check
			mean_frame_saving_ms = $meanFrame
			mean_gpu_saving_ms = $meanGpu
			mean_cpu_saving_ms = $meanCpu
			views = $views
		}
	}
}

# Do the parts' costs add up to everything off? If not, they affect each other.
$interaction = @()
if ($Ablate -and @($costs | Where-Object { $_.variant -eq "all_off" }).Count -gt 0) {
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
if ($scaling.Count -gt 0) {
	$summary.variants = $byVariant
	$summary.scaling = $scaling
}

# --- Start-up: from the game's start to the first measured frame ---
# For the "load" scenario (its plan says "startup": true) and any session
# with -ColdCache: per run and the middle value over the runs.
$startup = $null
if ($plan.startup -or $ColdCache) {
	# The benchmark's own waits before the first view is measured: 0.5 s at
	# its start, then SETTLE_S at the view (terrain_benchmark.gd).
	$settleS = 1.5
	$benchmarkScript = Join-Path $Game "game\prototypes\terrain\terrain_benchmark.gd"
	if ((Test-Path $benchmarkScript) -and ((Get-Content -Raw $benchmarkScript) -match 'const SETTLE_S: float = ([\d.]+)')) {
		$settleS = [double]::Parse($Matches[1], [cultureinfo]::InvariantCulture)
	}
	$startupRuns = @()
	foreach ($entry in @($sessionInfo.runs | Where-Object { $_.ok })) {
		$one = Get-StartupOfRun $session $entry ([bool]$ColdCache) (0.5 + $settleS)
		if ($one) { $startupRuns += $one }
	}
	$combinedStartup = [ordered]@{ cache = if ($ColdCache) { "cold" } else { "warm" }; runs = $startupRuns.Count }
	foreach ($field in @("to_first_frame_s", "landscape_build_ms", "forest_setup_ms", "benchmark_waits_s", "other_s", "after_first_view_s", "run_seconds",
			"tree_picture_rows_from_cache", "tree_picture_rows_photographed", "shader_compiles_first_view", "first_frame_ms",
			"unsteady_frames", "first_view_max_frame_ms", "first_view_hitches")) {
		$values = @($startupRuns | Where-Object { $null -ne $_[$field] } | ForEach-Object { [double]$_[$field] })
		$combinedStartup[$field] = if ($values.Count -gt 0) { Get-Median ([double[]]$values) } else { $null }
	}
	$startup = [ordered]@{
		cache = $combinedStartup.cache
		how = "to_first_frame_s: from zbench starting the game's launcher to the first measured frame of the first view (its screenshot's time minus its measured seconds). other_s: what is left after the landscape, the forest (with the tree pictures) and the benchmark's waits: Godot starting, loading the scene, houses and rocks, grass, shaders."
		runs = $startupRuns
		combined = $combinedStartup
	}
	$summary.load = $startup
}

# --- Compare with the baseline ---
$kindLabel = if ($Ablate) { "$($Scenario)_ablate" } else { $Scenario }
if ($ColdCache) { $kindLabel += "_cold" }
$profileLabel = if ($GpuProfile) { "_gpuprofile" } else { "" }
$baselineFile = Join-Path $PSScriptRoot "baselines\$($machine.pc)\$($kindLabel)_$($Preset)_$($Renderer)_$($Gpu)$profileLabel.json"
$compareWith = if ($Baseline) { $Baseline } else { $baselineFile }
$comparison = $null
$base = $null
$rowsOut = @()
if ((Test-Path $compareWith) -and -not ($SaveBaseline -and -not $Baseline)) {
	$base = Get-Content -Raw $compareWith | ConvertFrom-Json
	if ($base.graphics_card_used -and $base.graphics_card_used -ne $firstRun.meta.graphics_card) {
		Write-Host "Not compared: the baseline was measured on $($base.graphics_card_used), this session on $($firstRun.meta.graphics_card)." -ForegroundColor Yellow
		$base = $null
	}
}
if ($base) {
	foreach ($now in $segments) {
		$then = $base.segments | Where-Object { $_.name -eq $now.name } | Select-Object -First 1
		if ($null -eq $then) { continue }
		$entry = [ordered]@{ view = $now.name }
		# Each number has its own noise (p99 varies far more than the mean):
		# the larger of the two sessions' bands, never under the floor.
		$bandOf = @{ mean_frame_ms = "noise_band_share"; p99_frame_ms = "p99_noise_band_share"; gpu_ms = "gpu_noise_band_share"; cpu_ms = "cpu_noise_band_share" }
		foreach ($metric in @("mean_frame_ms", "p99_frame_ms", "gpu_ms", "cpu_ms")) {
			$old = [double]$then.$metric
			$new = [double]$now.$metric
			if ($old -le 0) { continue }
			$bandName = $bandOf[$metric]
			$band = [math]::Max([math]::Max([double]$now.$bandName, [double]$then.$bandName), $MinNoiseShare)
			$limit = [math]::Max(0.05, $band)
			$change = ($new - $old) / $old
			$verdict = if ([math]::Abs($change) -le $limit) { "no change" } elseif ($change -gt 0) { "slower" } else { "faster" }
			$entry[$metric] = [ordered]@{ before = $old; now = $new; change_share = $change; verdict = $verdict }
		}
		$rowsOut += $entry
	}
	$comparison = [ordered]@{
		baseline_file = (Resolve-Path $compareWith).Path
		baseline_commit = $base.machine.game_commit
		baseline_date = $base.analysed
		rows = $rowsOut
	}
	$summary.comparison = $comparison
}
$summaryFile = Join-Path $session "summary.json"
if ($Reanalyse -and (Test-Path $summaryFile)) {
	# Keep the earlier analysis next to the new one.
	Copy-Item $summaryFile (Join-Path $session "summary.previous.json") -Force
}
$summary.analysed = (Get-Date -Format "s")
$summary.min_noise_share = $MinNoiseShare
Save-Json $summary $summaryFile

# --- Print ---
Write-Host ""
Write-Host "Summary ($Repeats runs$(if ($Ablate) { ' of everything on' }), middle value of each):" -ForegroundColor Cyan
Write-Host ("{0,-24} {1,9} {2,8} {3,9} {4,8} {5,8} {6,9}  {7}" -f "view", "frame ms", "spread", "p99 ms", "gpu ms", "gpu-bnd", "stutters/run", "each run (ms)")
foreach ($s in $segments) {
	$each = ($s.per_repeat_mean_ms | ForEach-Object { "{0:N2}" -f $_ }) -join " / "
	Write-Host ("{0,-24} {1,9:N2} {2,7:N1}% {3,9:N2} {4,8:N2} {5,7:N0}% {6,9}  {7}" -f $s.name, $s.mean_frame_ms,
		($s.frame_spread_share * 100), $s.p99_frame_ms, $s.gpu_ms, ($s.gpu_bound_share * 100),
		(Get-Median ([double[]]@($s.hitches))), $each)
}
$worst = 0.0
foreach ($s in $segments) { $worst = [math]::Max($worst, $s.frame_spread_share) }
$band = [math]::Max($MinNoiseShare, $worst)
Write-Host ("Repeats differ by up to {0:N1}%: on this PC a part's saving counts if it is over {1:N1}% (the noise); a change against a baseline must be over 5% and outside the noise." -f ($worst * 100), ($band * 100))
foreach ($w in $outsideWarnings) { Write-Host "WARNING: $w" -ForegroundColor Yellow }
foreach ($s in $segments) {
	if (-not $s.zones) { continue }
	Write-Host ""
	Write-Host "Where the processor time goes in $($s.name) (stopwatches; ms per frame on average, and the slowest frame):" -ForegroundColor Cyan
	Write-Host ("  {0,-22} {1,9:N3}   (all scripts {2:N3}, physics {3:N3})" -f "scripts and physics", ($s.process_mean_ms + $s.physics_mean_ms), $s.process_mean_ms, $s.physics_mean_ms)
	$ordered = @($s.zones.Keys | Sort-Object { $s.zones[$_].mean_ms } -Descending)
	foreach ($zoneName in $ordered) {
		$label = if ($zoneName.Contains(".")) { "  - $zoneName" } else { $zoneName }
		Write-Host ("  {0,-22} {1,9:N3}   slowest frame {2,7:N2}" -f $label, $s.zones[$zoneName].mean_ms, $s.zones[$zoneName].max_ms)
	}
	Write-Host ("  {0,-22} {1,9:N3}   (scripts without a stopwatch)" -f "unattributed scripts", $s.unattributed_process_ms)
	Write-Host ("  {0,-22} {1,9:N3}   (mostly Jolt's own step)" -f "unattributed physics", $s.unattributed_physics_ms)
}
foreach ($s in $segments) {
	if (-not $s.hitch_causes) { continue }
	Write-Host ""
	Write-Host "Stutters in $($s.name) by main cause (middle count of the runs, slowest, where in the first run):" -ForegroundColor Cyan
	foreach ($causeName in $s.hitch_causes.Keys) {
		$entry = $s.hitch_causes[$causeName]
		# One entry per stutter: show each place once, and at most eight.
		$places = @($entry.at_x | ForEach-Object { [string]::Format([cultureinfo]::InvariantCulture, "{0:F0}", $_) } | Select-Object -Unique)
		$where = ($places | Select-Object -First 8) -join ", "
		if ($places.Count -gt 8) { $where += " and $($places.Count - 8) more places" }
		$count = if ($entry.count -gt 0) { "{0,4} stutters" -f $entry.count } else { "  in some runs only" }
		Write-Host ("  {0,-18} {1}, slowest {2,7:N1} ms, at world x {3}" -f $causeName, $count, $entry.worst_ms, $where)
	}
}

if ($startup) {
	Write-Host ""
	Write-Host "Start-up ($($startup.cache): $(if ($startup.cache -eq 'cold') { 'caches deleted before each run' } else { 'caches as they were' }); seconds from the game's start):" -ForegroundColor Cyan
	Write-Host ("  {0,-8} {1,-5} {2,9} {3,10} {4,7} {5,6} {6,6} {7,15} {8,8} {9,10} {10,8}" -f "run", "cache", "to view", "landscape", "forest", "waits", "other", "pictures (c/n)", "shaders", "1st frame", "unsteady")
	Write-Host ("  {0,-8} {1,-5} {2,9} {3,10} {4,7} {5,6} {6,6} {7,15} {8,8} {9,10} {10,8}" -f "", "", "s", "s", "s", "s", "s", "cached/new", "compiled", "ms", "frames")
	$rowsToPrint = @($startup.runs | ForEach-Object { $_ })
	if ($startup.runs.Count -gt 1) { $rowsToPrint += [ordered]@{ folder = "median"; cache = $startup.cache } }
	foreach ($row in $rowsToPrint) {
		$src = if ($row.folder -eq "median") { $startup.combined } else { $row }
		$num = { param($v, $scale, $fmt) if ($null -eq $v) { "-" } else { ("{0:$fmt}" -f ([double]$v * $scale)) } }
		Write-Host ("  {0,-8} {1,-5} {2,9} {3,10} {4,7} {5,6} {6,6} {7,15} {8,8} {9,10} {10,8}" -f $row.folder, $row.cache,
			(& $num $src.to_first_frame_s 1 "N2"), (& $num $src.landscape_build_ms 0.001 "N2"), (& $num $src.forest_setup_ms 0.001 "N2"),
			(& $num $src.benchmark_waits_s 1 "N1"), (& $num $src.other_s 1 "N2"),
			("{0}/{1}" -f (& $num $src.tree_picture_rows_from_cache 1 "N0"), (& $num $src.tree_picture_rows_photographed 1 "N0")),
			(& $num $src.shader_compiles_first_view 1 "N0"), (& $num $src.first_frame_ms 1 "N1"), (& $num $src.unsteady_frames 1 "N0"))
	}
	Write-Host "  (other = Godot starting, loading the scene, houses and rocks, grass, shaders; 1st frame includes writing the first screenshot, about 0.1-0.3 s)"
}
if ($Ablate) {
	$ranked = @($costs | Where-Object { $_.variant -ne "all_off" -and -not $_.detail } | Sort-Object { $_.mean_frame_saving_ms } -Descending)
	$ranked += @($costs | Where-Object { $_.detail -and -not $_.cpu } | Sort-Object { $_.mean_frame_saving_ms } -Descending)
	$ranked += @($costs | Where-Object { $_.variant -eq "all_off" })
	if ($ranked.Count -gt 0) {
		Write-Host ""
		Write-Host "What each part costs (frame time saved when it is off, ms; * = inside the noise):" -ForegroundColor Cyan
		Write-Host "(Lines starting with '-' are pieces of a part above, such as the trees' shadows.)"
		$header = "{0,-22}" -f "part"
		foreach ($s in $segments) { $header += " {0,14}" -f ($s.name.Substring(0, [math]::Min(14, $s.name.Length))) }
		$header += " {0,8} {1,8}  {2}" -f "average", "gpu avg", "switch worked?"
		Write-Host $header
	}
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
	$cpuCosts = @($costs | Where-Object { $_.cpu } | Sort-Object { $_.mean_cpu_saving_ms } -Descending)
	if ($cpuCosts.Count -gt 0) {
		Write-Host ""
		Write-Host "Processor and physics: processor time saved per frame (scripts + physics, ms; * = inside the noise)" -ForegroundColor Cyan
		$header = "{0,-22}" -f "part"
		foreach ($s in $segments) { $header += " {0,14}" -f ($s.name.Substring(0, [math]::Min(14, $s.name.Length))) }
		$header += " {0,8} {1,9}  {2}" -f "average", "frame avg", "work stopped?"
		Write-Host $header
		$line = "{0,-22}" -f "(processor time, all on)"
		foreach ($s in $segments) { $line += " {0,13:N3} " -f $s.cpu_ms }
		Write-Host $line
		foreach ($c in $cpuCosts) {
			$line = "{0,-22}" -f $c.variant
			foreach ($v in $c.views) {
				$mark = if ($v.cpu_outside_noise) { " " } else { "*" }
				$line += " {0,13:N3}{1}" -f $v.cpu_saving_ms, $mark
			}
			$line += " {0,8:N3} {1,9:N2}  {2}" -f $c.mean_cpu_saving_ms, $c.mean_frame_saving_ms, $c.check
			Write-Host $line
		}
	}
	if ($interaction.Count -gt 0) {
		Write-Host ""
		Write-Host "Do the parts add up to everything off? (if not, they affect each other)"
		foreach ($i in $interaction) {
			Write-Host ("  {0,-24} parts together {1,6:N2} ms, everything off {2,6:N2} ms, frame with everything off {3,6:N2} ms" -f $i.view,
				$i.sum_of_parts_ms, $i.all_off_saving_ms, $i.floor_frame_ms)
		}
	}
}
foreach ($sc in $scaling) {
	Write-Host ""
	Write-Host "How $($sc.view) grows (middle value of each variant):" -ForegroundColor Cyan
	Write-Host ("  {0,-14} {1,6} {2,9} {3,9} {4,10} {5,10} {6,8}" -f "variant", "count", "frame ms", "p99 ms", "processor", "physics", "stutters")
	foreach ($row in $sc.rows) {
		Write-Host ("  {0,-14} {1,6} {2,9:N2} {3,9:N2} {4,10:N3} {5,10:N3} {6,8}" -f $row.variant, $row.x, $row.frame_ms, $row.p99_ms, $row.cpu_ms, $row.physics_ms, $row.hitches)
	}
	if ($sc.cpu_fit) {
		$steady = if ($sc.cpu_fit.r2 -ge 0.9) { "grows steadily" } else { "does NOT grow along a straight line" }
		Write-Host ("  Processor time: {0:N4} ms more per extra one; the line fits {1:N0} % ({2})." -f $sc.cpu_fit.slope, ($sc.cpu_fit.r2 * 100), $steady)
	}
	if ($sc.frame_fit) {
		Write-Host ("  Frame time: {0:N4} ms more per extra one (fit {1:N0} %)." -f $sc.frame_fit.slope, ($sc.frame_fit.r2 * 100))
	}
}
if ($comparison) {
	Write-Host ""
	Write-Host "Compared with the baseline ($($comparison.baseline_file)):" -ForegroundColor Cyan
	foreach ($row in $comparison.rows) {
		$parts = @()
		foreach ($metric in @("mean_frame_ms", "p99_frame_ms", "gpu_ms", "cpu_ms")) {
			if (-not $row.Contains($metric)) { continue }
			$m = $row[$metric]
			$parts += ("{0} {1:N2} -> {2:N2} ({3:+0.0;-0.0}%, {4})" -f $metric.Replace("_ms", "").Replace("mean_", ""), $m.before, $m.now, ($m.change_share * 100), $m.verdict)
		}
		$colour = if (($parts -join " ") -match "slower") { "Red" } elseif (($parts -join " ") -match "faster") { "Green" } else { "Gray" }
		Write-Host ("  {0,-22} {1}" -f $row.view, ($parts -join "; ")) -ForegroundColor $colour
	}
}
if ($SaveBaseline -and $outsideWarnings.Count -gt 0) {
	# A disturbed baseline would make every later clean run look "faster".
	Write-Host ""
	Write-Host "NOT saved as this PC's baseline: a run waited for something outside the game (see the warning above). Close other programs and run again with -SaveBaseline." -ForegroundColor Red
} elseif ($SaveBaseline) {
	New-Item -ItemType Directory -Force (Split-Path $baselineFile) | Out-Null
	Copy-Item $summaryFile $baselineFile -Force
	Write-Host ""
	Write-Host "Saved as this PC's baseline: $baselineFile" -ForegroundColor Green
}
Write-Host "Results: $session" -ForegroundColor Green
# The report page (report.html): opens in any web browser, also offline.
try {
	$page = New-BenchReport -Session $session
	Write-Host "Report page: $page" -ForegroundColor Green
} catch {
	Write-Host "Could not make the report page: $($_.Exception.Message)" -ForegroundColor Yellow
}
