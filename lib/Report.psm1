# SPDX-License-Identifier: GPL-3.0-or-later
# The report page: one HTML file per session (report.html) that opens
# offline, with no outside scripts or fonts. It reads the session's
# summary.json, session.json and the first all-on run (run.json and
# frames.csv), and explains them in plain words:
#   the PC, a verdict, the top costs, a frame-time chart per view, where
#   the frame goes, whether the parts add up, and how much the repeats differed.
#
#   New-BenchReport -Session <session folder> [-OutFile <path>]
#
# Note: PowerShell doesn't tell upper and lower case apart in names, so no
# variable here may be called $session or $outFile (those are the options).

$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$BudgetMs = 1000.0 / 60.0
$DefaultNoiseShare = 0.015

# Plain names for the switches (the ids the game uses after --off=).
$PartNames = @{
	shadows = "Shadows (all)"
	grass = "Grass"
	objects = "Houses and rocks"
	trees = "Trees"
	terrain = "Ground (Terrain3D)"
	sky = "Sky"
	fog = "Fog"
	pictures = "Far tree pictures"
	terrain_shadows = "Ground's shadows"
	tree_shadows = "Near trees' shadows"
	object_shadows = "Houses' and rocks' shadows"
	world_updates = "Tree, grass and far-object updates"
	daynight = "Day, night and weather updates"
	overlay = "Information panel"
	physics_engine = "Physics step (Jolt)"
	recentre = "Re-centring the world"
	terrain_collision = "Ground collision"
	trunk_collision = "Tree trunk collision"
	imgui = "ImGui layer (debug menus)"
	water = "Water"
	lamps = "House lamps"
	all = "Everything off together"
}

# Pieces and the bigger part they belong to.
$PieceOf = @{
	pictures = "Trees"
	terrain_shadows = "Shadows (all)"
	tree_shadows = "Shadows (all)"
	object_shadows = "Shadows (all)"
}

function Fmt($Value, [int] $Digits = 2) {
	if ($null -eq $Value) { return "-" }
	return [string]::Format($Inv, "{0:F$Digits}", [double]$Value)
}

function Esc($Text) {
	if ($null -eq $Text) { return "" }
	return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

# A field of a JSON object, or $null when an older session doesn't have it.
function Get-Field($Object, [string] $Name) {
	if ($null -eq $Object) { return $null }
	$property = $Object.PSObject.Properties[$Name]
	if ($null -eq $property) { return $null }
	return $property.Value
}

function Read-Json([string] $Path) {
	if (-not (Test-Path -LiteralPath $Path)) { return $null }
	return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json)
}

function Get-MiddleValue([double[]] $Values) {
	if ($Values.Count -eq 0) { return $null }
	$sorted = @($Values | Sort-Object)
	$middle = [math]::Floor(($sorted.Count - 1) / 2)
	if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$middle] }
	return ([double]$sorted[$middle] + [double]$sorted[$middle + 1]) / 2.0
}

function ConvertTo-Num($Text) {
	$number = 0.0
	if ([double]::TryParse([string]$Text, [System.Globalization.NumberStyles]::Float, $Inv, [ref]$number)) { return $number }
	return $null
}

function Get-PartName([string] $Variant) {
	$id = $Variant
	if ($id.EndsWith("_off")) { $id = $id.Substring(0, $id.Length - 4) }
	if ($PartNames.ContainsKey($id)) { return $PartNames[$id] }
	return $Variant
}

# Plain names for what was happening in a stutter frame (newer sessions):
# the game's events, plus physics catch-up and shader compiles.
$CauseNames = @{
	recentre = "Re-centring the world"
	tree_blocks = "New near trees"
	trunk_bodies = "New tree-trunk collision"
	grass_tiles = "New grass tiles"
	object_tiles = "New far houses and rocks"
	screenshot = "The benchmark's own screenshot (not the game's fault)"
	shader_compiles = "Shaders compiled for the first time"
	physics_catch_up = "Physics catching up after a slow frame"
	unknown = "Unknown"
	npc_level_changes = "NPCs switching how closely they are simulated"
	new_hour = "A new hour (NPCs change what they do)"
	route_searches = "NPC route searches"
	bodies_made = "New NPC bodies"
	items_spawned = "New loose items"
	items_woke = "Loose items waking up (physics)"
	cargo_stowed = "Cargo stowed on the boat"
	cargo_released = "Cargo released from the boat"
	trip_saved = "Saving the trip"
	trip_loaded = "Loading the trip"
}

function Get-CauseName([string] $Id) {
	if ($CauseNames.ContainsKey($Id)) { return $CauseNames[$Id] }
	return $Id
}

# Plain names for the stopwatch zones. A name with a dot is a piece of the
# zone before the dot (shown indented under it).
$ZoneNames = @{
	forest = "Near trees (building after moving)"
	"forest.blocks" = "tree blocks"
	"forest.collision" = "trunk collision"
	objects = "Far houses and rocks"
	grass = "Grass tiles"
	daynight = "Day, night and weather"
	recentre = "Re-centring (physics)"
	"recentre.regions" = "moving the ground's regions"
	"recentre.shift" = "moving every node"
	"recentre.collision" = "the ground's collision"
	"recentre.signals" = "the systems that follow"
	npc = "NPCs (each frame)"
	"npc.schedule" = "following their day plans"
	"npc.level_change" = "switching how closely they are simulated"
	"npc.route" = "route searches"
	npc_bodies = "NPC bodies (physics)"
	"npc_bodies.steer" = "steering"
	"npc_bodies.move" = "moving"
	items = "Loose items (physics)"
	"items.water" = "checking for water"
	"items.buoyancy" = "floating"
	spawn = "Adding items"
	player = "The player (physics)"
	"player.grabber" = "grabbing and carrying"
	boat = "The boat (physics)"
	"boat.holding" = "holding the cargo in place"
	"boat.stowing" = "stowing cargo"
	"boat.buoyancy" = "floating"
	trip_saving = "Saving the trip"
	trip_loading = "Loading the trip"
	"trip_loading.unstow" = "taking the cargo off"
	"trip_loading.restow" = "stowing the cargo again"
	_overhead = "The stopwatches' own cost"
}

function Get-ZoneName([string] $Id) {
	if ($ZoneNames.ContainsKey($Id)) { return $ZoneNames[$Id] }
	return $Id
}

function Get-LowerFirst([string] $Text) {
	if ($Text.Length -lt 2) { return $Text }
	# Keep short words in capitals (NPC) as they are.
	if ([char]::IsUpper($Text[1])) { return $Text }
	return $Text.Substring(0, 1).ToLower() + $Text.Substring(1)
}

# The name/value pairs of a JSON object (empty for $null).
function Get-Pairs($Object) {
	if ($null -eq $Object) { return @() }
	if ($Object -is [System.Collections.IDictionary]) { return @($Object.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Key; Value = $_.Value } }) }
	return @($Object.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
}

# Small milliseconds: more digits when the number is tiny.
function Fmt-Ms($Value) {
	if ($null -eq $Value) { return "-" }
	$abs = [math]::Abs([double]$Value)
	if ($abs -gt 0 -and $abs -lt 0.01) { return (Fmt $Value 4) }
	if ($abs -lt 1) { return (Fmt $Value 3) }
	return (Fmt $Value 2)
}

# A round step for an axis that should have about four lines.
function Get-NiceStep([double] $Span) {
	if ($Span -le 0) { return 1.0 }
	$raw = $Span / 4.0
	$magnitude = [math]::Pow(10, [math]::Floor([math]::Log10($raw)))
	foreach ($m in @(1.0, 2.0, 2.5, 5.0, 10.0)) { if ($m * $magnitude -ge $raw) { return $m * $magnitude } }
	return 10.0 * $magnitude
}

# What a sweep counts, for its sentences ("per extra NPC").
function Get-SweepUnit([string] $Scenario, [string] $FirstVariant) {
	$key = "$Scenario $FirstVariant"
	if ($key -match "npc") { return @{ one = "NPC"; many = "NPCs" } }
	if ($key -match "cargo") { return @{ one = "crate of cargo"; many = "crates of cargo" } }
	if ($key -match "item") { return @{ one = "item"; many = "items" } }
	return @{ one = "one"; many = "count" }
}

# One small chart for a sweep: points (x, ms) and the fitted straight line.
function New-GrowthChart([string] $Caption, $Points, $Fit, [string] $Cls, [string] $XLabel) {
	$width = 360.0; $height = 210.0
	$left = 48.0; $right = 14.0; $top = 12.0; $bottom = 36.0
	$plotW = $width - $left - $right
	$plotH = $height - $top - $bottom
	$pts = @($Points | Where-Object { $null -ne $_.y })
	if ($pts.Count -lt 1) { return "<p class=""muted small"">$(Esc "$Caption`: not recorded.")</p>" }
	$xMin = [double]::MaxValue; $xMax = [double]::MinValue; $yTop = 0.0
	foreach ($p in $pts) {
		if ($p.x -lt $xMin) { $xMin = $p.x }
		if ($p.x -gt $xMax) { $xMax = $p.x }
		if ($p.y -gt $yTop) { $yTop = $p.y }
	}
	if ($xMax -le $xMin) { $xMax = $xMin + 1.0 }
	if ($null -ne $Fit) {
		foreach ($xEnd in @($xMin, $xMax)) {
			$yEnd = [double]$Fit.intercept + [double]$Fit.slope * $xEnd
			if ($yEnd -gt $yTop) { $yTop = $yEnd }
		}
	}
	if ($yTop -le 0) { $yTop = 1.0 }
	$step = Get-NiceStep ($yTop * 1.1)
	$yMax = [math]::Ceiling(($yTop * 1.1) / $step) * $step
	# Enough digits to show the step exactly (0.25 needs two).
	$digits = 0
	while ($digits -lt 4 -and [math]::Abs($step * [math]::Pow(10, $digits) - [math]::Round($step * [math]::Pow(10, $digits))) -gt 1e-6) { $digits++ }
	$sb = New-Object System.Text.StringBuilder
	[void]$sb.Append("<svg class=""chart"" viewBox=""0 0 $(Fmt $width 0) $(Fmt $height 0)"" role=""img"" aria-label=""$(Esc $Caption)"">")
	for ($g = 0.0; $g -le $yMax + $step / 1000.0; $g += $step) {
		$y = $top + (1.0 - $g / $yMax) * $plotH
		[void]$sb.Append("<line class=""grid"" x1=""$(Fmt $left 1)"" x2=""$(Fmt ($width - $right) 1)"" y1=""$(Fmt $y 1)"" y2=""$(Fmt $y 1)""/>")
		[void]$sb.Append("<text class=""axis"" x=""$(Fmt ($left - 6) 1)"" y=""$(Fmt ($y + 4) 1)"" text-anchor=""end"">$(Fmt $g $digits)</text>")
	}
	[void]$sb.Append("<text class=""axis"" x=""4"" y=""$(Fmt ($top + 2) 1)"" transform=""rotate(-90 4,$(Fmt ($top + 2) 1))"" text-anchor=""end"" dy=""8"">ms</text>")
	$xs = @($pts | ForEach-Object { $_.x } | Sort-Object -Unique)
	foreach ($xv in $xs) {
		$x = $left + (($xv - $xMin) / ($xMax - $xMin)) * $plotW
		[void]$sb.Append("<text class=""axis"" x=""$(Fmt $x 1)"" y=""$(Fmt ($height - $bottom + 15) 1)"" text-anchor=""middle"">$(Esc ([string]::Format($Inv, '{0:0.##}', $xv)))</text>")
	}
	[void]$sb.Append("<text class=""axis"" x=""$(Fmt ($left + $plotW / 2) 1)"" y=""$(Fmt ($height - 4) 1)"" text-anchor=""middle"">$(Esc $XLabel)</text>")
	if ($null -ne $Fit) {
		$y1 = $top + (1.0 - [math]::Max(0.0, [double]$Fit.intercept + [double]$Fit.slope * $xMin) / $yMax) * $plotH
		$y2 = $top + (1.0 - [math]::Max(0.0, [double]$Fit.intercept + [double]$Fit.slope * $xMax) / $yMax) * $plotH
		[void]$sb.Append("<line class=""fit $Cls"" x1=""$(Fmt $left 1)"" x2=""$(Fmt ($width - $right) 1)"" y1=""$(Fmt $y1 1)"" y2=""$(Fmt $y2 1)""><title>The straight line that fits best</title></line>")
	}
	foreach ($p in $pts) {
		$x = $left + (($p.x - $xMin) / ($xMax - $xMin)) * $plotW
		$y = $top + (1.0 - [math]::Min([double]$p.y, $yMax) / $yMax) * $plotH
		$tip = [string]::Format($Inv, "{0}: {1} ms", $p.label, (Fmt-Ms $p.y))
		[void]$sb.Append("<circle class=""pt $Cls"" cx=""$(Fmt $x 1)"" cy=""$(Fmt $y 1)"" r=""4""><title>$(Esc $tip)</title></circle>")
	}
	[void]$sb.Append("</svg>")
	return "<figure class=""growth"">$($sb.ToString())<figcaption class=""small muted"">$(Esc $Caption)</figcaption></figure>"
}

function Get-PartId([string] $Variant) {
	if ($Variant.EndsWith("_off")) { return $Variant.Substring(0, $Variant.Length - 4) }
	return $Variant
}

# Processor time per frame (scripts plus physics) for one view. Newer
# sessions have it in summary.json; older ones are worked out from the runs.
function Get-ProcessorMs($Segment, $Runs) {
	$cpu = Get-Field $Segment "cpu_ms"
	if ($null -ne $cpu) { return @{ ms = [double]$cpu; physics = $true } }
	$processMean = Get-Field $Segment "process_mean_ms"
	if ($null -ne $processMean) {
		$physicsMean = Get-Field $Segment "physics_mean_ms"
		return @{ ms = [double]$processMean + [double]$physicsMean; physics = ($null -ne $physicsMean) }
	}
	$values = @()
	$hasPhysics = $false
	foreach ($run in $Runs) {
		$runSegment = @($run.segments | Where-Object { $_.name -eq $Segment.name }) | Select-Object -First 1
		if ($null -eq $runSegment) { continue }
		$block = Get-Field $runSegment "mean"
		if ($null -eq $block) { $block = Get-Field $runSegment "p50" }
		if ($null -eq $block) { continue }
		$physics = Get-Field $block "physics_ms"
		if ($null -ne $physics) { $hasPhysics = $true }
		$values += [double](Get-Field $block "process_ms") + [double]$physics
	}
	if ($values.Count -gt 0) { return @{ ms = (Get-MiddleValue ([double[]]$values)); physics = $hasPhysics } }
	$p50 = Get-Field $Segment "process_ms"
	if ($null -ne $p50) { return @{ ms = [double]$p50; physics = $false } }
	return @{ ms = $null; physics = $false }
}

# One view's frame-time chart (inline SVG) from frames.csv rows.
function New-FrameChart([string] $View, $Rows, $Hitches) {
	$width = 720.0; $height = 230.0
	$left = 44.0; $right = 12.0; $top = 10.0; $bottom = 30.0
	$plotW = $width - $left - $right
	$plotH = $height - $top - $bottom
	$times = New-Object System.Collections.Generic.List[double]
	$frames = New-Object System.Collections.Generic.List[double]
	$gpus = New-Object System.Collections.Generic.List[double]
	# t_ms in frames.csv is when the frame ENDED (each t minus the one before
	# is that frame's time). Each frame is drawn as a flat step from its start
	# to its end, so a long frame shows as a long flat top, not a slope.
	$clock = 0.0
	foreach ($row in $Rows) {
		$frame = ConvertTo-Num $row.frame_ms
		if ($null -eq $frame) { continue }
		$t = ConvertTo-Num (Get-Field $row "t_ms")
		if ($null -eq $t) { $t = $clock + $frame }
		$clock = $t
		$times.Add($t)
		$frames.Add($frame)
		$gpu = ConvertTo-Num (Get-Field $row "gpu_ms")
		if ($null -eq $gpu) { $gpu = [double]::NaN }
		$gpus.Add($gpu)
	}
	if ($frames.Count -lt 2) { return "<p class=""muted"">No frame rows for this view.</p>" }
	$tStart = [math]::Max(0.0, $times[0] - $frames[0])
	$tEnd = [math]::Max($tStart + 1.0, $times[$times.Count - 1])
	$tSpan = $tEnd - $tStart
	$maxFrame = 0.0
	foreach ($v in $frames) { if ($v -gt $maxFrame) { $maxFrame = $v } }
	$typical = Get-MiddleValue ([double[]]$frames.ToArray())
	# Keep the line readable: a single huge stutter would squash everything,
	# so the scale stops at 3 times the typical frame (stutters go to the top).
	$yMax = [math]::Max($BudgetMs * 1.2, [math]::Min($maxFrame * 1.08, $typical * 3.0))
	$step = if ($yMax -le 40) { 5.0 } elseif ($yMax -le 100) { 10.0 } else { 25.0 }
	$yMax = [math]::Ceiling($yMax / $step) * $step
	$clipped = $maxFrame -gt $yMax

	$sb = New-Object System.Text.StringBuilder
	$label = Esc "Frame time over time in $View"
	[void]$sb.Append("<svg class=""chart"" viewBox=""0 0 $(Fmt $width 0) $(Fmt $height 0)"" role=""img"" aria-label=""$label"">")
	# Grid and axis labels.
	for ($g = 0.0; $g -le $yMax + 0.001; $g += $step) {
		$y = $top + (1.0 - $g / $yMax) * $plotH
		[void]$sb.Append("<line class=""grid"" x1=""$(Fmt $left 1)"" x2=""$(Fmt ($width - $right) 1)"" y1=""$(Fmt $y 1)"" y2=""$(Fmt $y 1)""/>")
		[void]$sb.Append("<text class=""axis"" x=""$(Fmt ($left - 6) 1)"" y=""$(Fmt ($y + 4) 1)"" text-anchor=""end"">$(Fmt $g 0)</text>")
	}
	$seconds = $tSpan / 1000.0
	$tick = if ($seconds -le 6) { 0.5 } elseif ($seconds -le 15) { 1.0 } elseif ($seconds -le 60) { 5.0 } elseif ($seconds -le 180) { 15.0 } else { 60.0 }
	for ($s = 0.0; $s -le $seconds + 0.0001; $s += $tick) {
		$x = $left + ($s * 1000.0 / $tSpan) * $plotW
		$text = if ($tick -lt 1) { (Fmt $s 1) } else { (Fmt $s 0) }
		[void]$sb.Append("<text class=""axis"" x=""$(Fmt $x 1)"" y=""$(Fmt ($height - $bottom + 16) 1)"" text-anchor=""middle"">$text s</text>")
	}
	[void]$sb.Append("<text class=""axis"" x=""4"" y=""$(Fmt ($top + 2) 1)"" transform=""rotate(-90 4,$(Fmt ($top + 2) 1))"" text-anchor=""end"" dy=""8"">ms</text>")
	# The 60 fps line.
	$yBudget = $top + (1.0 - $BudgetMs / $yMax) * $plotH
	[void]$sb.Append("<line class=""budget"" x1=""$(Fmt $left 1)"" x2=""$(Fmt ($width - $right) 1)"" y1=""$(Fmt $yBudget 1)"" y2=""$(Fmt $yBudget 1)""><title>Target: 16.7 ms per frame = 60 fps</title></line>")
	# The two lines.
	foreach ($series in @(@{ values = $gpus; cls = "ln-gpu" }, @{ values = $frames; cls = "ln-frame" })) {
		$points = New-Object System.Text.StringBuilder
		$open = $false
		for ($i = 0; $i -lt $frames.Count; $i++) {
			$v = $series.values[$i]
			if ([double]::IsNaN($v) -or $v -le 0) {
				if ($open) { [void]$sb.Append("<polyline class=""$($series.cls)"" points=""$($points.ToString())""/>"); [void]$points.Clear(); $open = $false }
				continue
			}
			$x1 = $left + (($times[$i] - $frames[$i] - $tStart) / $tSpan) * $plotW
			$x2 = $left + (($times[$i] - $tStart) / $tSpan) * $plotW
			$y = $top + (1.0 - [math]::Min($v, $yMax) / $yMax) * $plotH
			[void]$points.Append("$(Fmt ([math]::Max($left, $x1)) 1),$(Fmt $y 1) $(Fmt $x2 1),$(Fmt $y 1) ")
			$open = $true
		}
		if ($open) { [void]$sb.Append("<polyline class=""$($series.cls)"" points=""$($points.ToString())""/>") }
	}
	[void]$sb.Append("<text class=""budget-label"" x=""$(Fmt ($width - $right - 4) 1)"" y=""$(Fmt ($yBudget - 4) 1)"" text-anchor=""end"">16.7 ms = 60 fps</text>")
	# Stutters.
	foreach ($h in @($Hitches)) {
		if ($null -eq $h) { continue }
		$t = ConvertTo-Num (Get-Field $h "t_ms")
		$worst = ConvertTo-Num (Get-Field $h "worst_ms")
		if ($null -eq $t -or $null -eq $worst) { continue }
		# t_ms is the end of the slow frame; the mark sits in its middle.
		$x = $left + ((($t - $worst / 2.0) - $tStart) / $tSpan) * $plotW
		$x = [math]::Min($width - $right, [math]::Max($left, $x))
		$y = $top + (1.0 - [math]::Min($worst, $yMax) / $yMax) * $plotH
		$tip = [string]::Format($Inv, "Stutter at {0:F2} s: {1:F1} ms", ($t - $tStart) / 1000.0, $worst)
		$causes = @(Get-Field $h "causes" | Where-Object { $_ })
		$mainCause = [string](Get-Field $h "cause")
		if ($mainCause) {
			$tip += "; main cause: " + (Get-LowerFirst (Get-CauseName $mainCause))
			$others = @($causes | Where-Object { $_ -ne $mainCause })
			if ($others.Count -gt 0) { $tip += "; also happening: " + (($others | ForEach-Object { Get-LowerFirst (Get-CauseName $_) }) -join ", ") }
		} elseif ($causes.Count -gt 0) { $tip += "; happening in that frame: " + (($causes | ForEach-Object { Get-LowerFirst (Get-CauseName $_) }) -join ", ") }
		$count = Get-Field $h "frames"
		if ($null -ne $count -and [int]$count -gt 1) { $tip += " ($count slow frames in a row)" }
		$steps = Get-Field $h "physics_steps"
		if ($null -ne $steps) { $tip += "; physics steps: $steps" }
		$compiles = Get-Field $h "shader_compiles"
		if ($null -ne $compiles) { $tip += "; shader compiles: $compiles" }
		if ($null -ne $compiles -and [int]$compiles -gt 0) { $tip += " (likely cause: a new shader being prepared)" }
		[void]$sb.Append("<circle class=""hitch"" cx=""$(Fmt $x 1)"" cy=""$(Fmt $y 1)"" r=""4.5""><title>$(Esc $tip)</title></circle>")
	}
	[void]$sb.Append("</svg>")
	if ($clipped) {
		[void]$sb.Append("<p class=""muted small"">The slowest frame ($(Fmt $maxFrame 1) ms) is above the top of the chart; it is drawn at the top edge.</p>")
	}
	return $sb.ToString()
}

function New-BenchReport {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)] [string] $Session,
		[string] $OutFile = ""
	)
	$dir = (Resolve-Path -LiteralPath $Session).Path
	$summary = Read-Json (Join-Path $dir "summary.json")
	if ($null -eq $summary) { throw "No summary.json in $dir (the session did not finish, or was not combined yet)." }
	$info = Read-Json (Join-Path $dir "session.json")
	if (-not $OutFile) { $OutFile = Join-Path $dir "report.html" }

	$segments = @($summary.segments)
	$repeats = [int](Get-Field $summary "repeats")
	if ($repeats -lt 1) { $repeats = @($segments[0].per_repeat_mean_ms).Count }
	$noiseFloor = Get-Field $summary "min_noise_share"
	if ($null -eq $noiseFloor) {
		# Older sessions don't say; their noise band (never below the floor
		# they used, 3 % before the change) tells it. Else the default.
		$bandShares = @($segments | ForEach-Object { Get-Field $_ "noise_band_share" } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
		$noiseFloor = if ($bandShares.Count -gt 0) { ($bandShares | Measure-Object -Minimum).Minimum } else { $DefaultNoiseShare }
	}
	$noiseFloor = [double]$noiseFloor
	$machine = Get-Field $summary "machine"
	if ($null -eq $machine) { $machine = Get-Field $info "machine" }
	$costs = @(Get-Field $summary "costs" | Where-Object { $null -ne $_ })
	$interaction = @(Get-Field $summary "interaction" | Where-Object { $null -ne $_ })
	$notShown = @()

	# The all-on runs: <session>\r1 for plain sessions, all_on\r1 with -Ablate.
	# A sweep keeps each variant in its own folder (<variant>\r1); its main
	# numbers are the first (smallest) variant's, so its runs are used.
	$scaling = @(Get-Field $summary "scaling" | Where-Object { $null -ne $_ })
	$comparison = Get-Field $summary "comparison"
	$runVariant = $null
	$runRoot = if (Test-Path -LiteralPath (Join-Path $dir "all_on")) { Join-Path $dir "all_on" } else { $dir }
	if (-not (Test-Path -LiteralPath (Join-Path $runRoot "r1"))) {
		$candidates = @()
		if ($scaling.Count -gt 0) { $candidates += @(@($scaling[0].rows) | ForEach-Object { [string]$_.variant }) }
		$candidates += @(Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name | ForEach-Object { $_.Name })
		foreach ($candidate in $candidates) {
			if ($candidate -and (Test-Path -LiteralPath (Join-Path $dir "$candidate\r1\run.json"))) { $runVariant = $candidate; $runRoot = Join-Path $dir $candidate; break }
		}
	}
	$runs = @()
	for ($r = 1; $r -le [math]::Max(1, $repeats); $r++) {
		$run = Read-Json (Join-Path $runRoot "r$r\run.json")
		if ($null -ne $run) { $runs += , $run }
	}
	$firstRun = if ($runs.Count -gt 0) { $runs[0] } else { $null }
	$csvPath = Join-Path $runRoot "r1\frames.csv"
	$rowsByView = @{}
	if (Test-Path -LiteralPath $csvPath) {
		foreach ($row in (Import-Csv -LiteralPath $csvPath)) {
			if (-not $rowsByView.ContainsKey($row.segment)) { $rowsByView[$row.segment] = New-Object System.Collections.Generic.List[object] }
			$rowsByView[$row.segment].Add($row)
		}
	} else {
		$notShown += "The frame-time charts: the first run's frames.csv is missing."
	}

	# Per view: processor time and the other numbers used below.
	$views = @()
	$physicsMissing = $false
	foreach ($seg in $segments) {
		$cpu = Get-ProcessorMs $seg $runs
		if (-not $cpu.physics) { $physicsMissing = $true }
		# The oldest sessions left the graphics card's time out of summary.json;
		# the runs have it (middle frame), so use the middle of the repeats.
		$gpuMs = Get-Field $seg "gpu_ms"
		if ($null -eq $gpuMs) {
			$runGpu = @()
			foreach ($run in $runs) {
				$runSegment = @($run.segments | Where-Object { $_.name -eq $seg.name }) | Select-Object -First 1
				$value = Get-Field (Get-Field $runSegment "p50") "gpu_ms"
				if ($null -ne $value -and [double]$value -gt 0) { $runGpu += [double]$value }
			}
			if ($runGpu.Count -gt 0) { $gpuMs = Get-MiddleValue ([double[]]$runGpu) }
		}
		$band = Get-Field $seg "noise_band_share"
		$spreadShare = [double](Get-Field $seg "frame_spread_share")
		$band = if ($null -ne $band) { [double]$band } else { [math]::Max($noiseFloor, $spreadShare) }
		$views += [pscustomobject]@{
			name = [string]$seg.name
			frame = [double](Get-Field $seg "mean_frame_ms")
			gpu = $gpuMs
			render = Get-Field $seg "render_cpu_ms"
			cpu = $cpu.ms
			cpuHasPhysics = [bool]$cpu.physics
			bound = Get-Field $seg "gpu_bound_share"
			p99 = Get-Field $seg "p99_frame_ms"
			spread = $spreadShare
			band = $band
			repeatsMs = @(Get-Field $seg "per_repeat_mean_ms")
			hitches = @(Get-Field $seg "hitches")
			causes = Get-Field $seg "hitch_causes"
			zones = Get-Field $seg "zones"
			processMean = Get-Field $seg "process_mean_ms"
			physicsMean = Get-Field $seg "physics_mean_ms"
			unattributedProcess = Get-Field $seg "unattributed_process_ms"
			unattributedPhysics = Get-Field $seg "unattributed_physics_ms"
		}
	}

	$html = New-Object System.Text.StringBuilder
	function Add([string] $Text) { [void]$html.Append($Text); [void]$html.Append("`n") }

	# ---------- Header ----------
	$scenario = [string](Get-Field $summary "scenario")
	$started = Get-Field $info "started"
	if (-not $started) { $started = Get-Field $summary "analysed" }
	$dateText = if ($started) { ([string]$started).Replace("T", " ") } else { (Split-Path $dir -Leaf).Substring(0, 10) }
	$cardUsed = Get-Field $summary "graphics_card_used"
	if (-not $cardUsed -and $firstRun) { $cardUsed = Get-Field $firstRun.meta "graphics_card" }
	$driver = $null
	foreach ($card in @(Get-Field $machine "graphics_cards")) {
		if ($card -and $cardUsed -and $card.name -eq $cardUsed) { $driver = $card.driver }
	}
	$commit = [string](Get-Field $machine "game_commit")
	$shortCommit = if ($commit.Length -ge 7) { $commit.Substring(0, 7) } else { $commit }
	$renderer = Get-Field $summary "renderer"
	$renderSize = @(Get-Field $summary "render_3d")
	$godot = Get-Field $summary "godot"
	$debug = Get-Field $summary "debug_build"
	$kindText = if ([bool](Get-Field $summary "ablate")) { "with parts switched off" } else { "everything on" }
	$title = "Zobolin benchmark: $scenario, $dateText"

	Add "<!doctype html>"
	Add "<html lang=""en""><head><meta charset=""utf-8""><meta name=""viewport"" content=""width=device-width, initial-scale=1"">"
	Add "<title>$(Esc $title)</title>"
	Add "<style>"
	Add @'
:root { --bg:#fbfbf8; --card:#ffffff; --text:#1d1d1b; --muted:#66665f; --line:#dcdcd6; --grid:#ececE6;
  --frame:#2f6fd6; --gpu:#d97b1f; --cpu:#3d9a5f; --render:#8a5cc7; --bad:#cc3a2b; --good:#2f8f4e; --mark:#fff4d6; }
@media (prefers-color-scheme: dark) { :root { --bg:#17181a; --card:#202225; --text:#e8e8e3; --muted:#a3a39b; --line:#3a3c40; --grid:#2c2e32;
  --frame:#6fa0f0; --gpu:#f0a050; --cpu:#6cc58c; --render:#b08ce6; --bad:#f06a5a; --good:#6cc58c; --mark:#3a3420; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text); font:16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
main { max-width:960px; margin:0 auto; padding:16px; }
h1 { font-size:1.5rem; margin:.4rem 0 .2rem; } h2 { font-size:1.2rem; margin:2rem 0 .5rem; } h3 { font-size:1rem; margin:1.2rem 0 .3rem; }
p { margin:.4rem 0; } .muted { color:var(--muted); } .small { font-size:.85rem; }
.card { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:12px 14px; margin:.6rem 0; }
.verdict { font-size:1.05rem; border-left:4px solid var(--frame); }
.warn { border-left:4px solid var(--bad); }
dl.facts { display:grid; grid-template-columns:max-content 1fr; gap:2px 14px; margin:0; }
dl.facts dt { color:var(--muted); } dl.facts dd { margin:0; overflow-wrap:anywhere; }
.scroll { overflow-x:auto; -webkit-overflow-scrolling:touch; }
table { border-collapse:collapse; width:100%; font-size:.9rem; }
th, td { padding:5px 8px; border-bottom:1px solid var(--line); text-align:left; vertical-align:top; }
th { color:var(--muted); font-weight:600; white-space:nowrap; }
td.n, th.n { text-align:right; white-space:nowrap; font-variant-numeric:tabular-nums; }
tr.total td { font-weight:600; border-top:2px solid var(--line); }
.neg { color:var(--bad); } td.part { min-width:11rem; } td.res { white-space:nowrap; } td.chk { min-width:10rem; } td.note { min-width:13rem; } .noise { color:var(--muted); }
.tag { display:inline-block; font-size:.75rem; padding:0 6px; border-radius:9px; border:1px solid var(--line); color:var(--muted); white-space:nowrap; }
svg.chart { width:100%; height:auto; display:block; }
svg .grid { stroke:var(--grid); stroke-width:1; } svg .axis { fill:var(--muted); font-size:11px; }
svg .budget { stroke:var(--muted); stroke-width:1.2; stroke-dasharray:6 4; } svg .budget-label { fill:var(--muted); font-size:11px; paint-order:stroke; stroke:var(--card); stroke-width:4px; stroke-linejoin:round; }
svg .ln-frame { fill:none; stroke:var(--frame); stroke-width:1.6; } svg .ln-gpu { fill:none; stroke:var(--gpu); stroke-width:1.2; opacity:.85; }
svg .hitch { fill:var(--bad); stroke:var(--card); stroke-width:1.5; cursor:help; }
.legend { display:flex; flex-wrap:wrap; gap:4px 16px; font-size:.85rem; color:var(--muted); margin:.2rem 0; }
.key { display:inline-block; width:18px; height:3px; vertical-align:middle; margin-right:5px; }
.key.dot { width:9px; height:9px; border-radius:50%; }
.bars { display:grid; grid-template-columns:minmax(110px, 13rem) 1fr 5.2rem; gap:4px 10px; align-items:center; font-size:.9rem; }
.bar { height:14px; border-radius:3px; min-width:2px; }
.bar-wrap { position:relative; background:var(--grid); border-radius:3px; }
.bar-wrap .goal { position:absolute; top:-3px; bottom:-3px; border-left:2px dashed var(--muted); }
.v { text-align:right; font-variant-numeric:tabular-nums; }
.good { color:var(--good); } .same { color:var(--muted); } .bad { color:var(--bad); }
td.piece { padding-left:1.6rem; color:var(--muted); } tr.own td { color:var(--muted); }
.growths { display:grid; grid-template-columns:1fr 1fr; gap:8px 16px; } figure.growth { margin:0; }
svg .fit { stroke-width:1.6; stroke-dasharray:5 3; } svg .pt { stroke:var(--card); stroke-width:1.5; cursor:help; }
svg .fit.s-cpu { stroke:var(--cpu); } svg .pt.s-cpu { fill:var(--cpu); } svg .fit.s-frame { stroke:var(--frame); } svg .pt.s-frame { fill:var(--frame); }
@media (max-width: 560px) { .growths { grid-template-columns:1fr; } }
@media (max-width: 560px) { dl.facts { grid-template-columns:1fr; } dl.facts dd { margin-bottom:6px; } .bars { grid-template-columns:1fr 4.6rem; } .bars > span:nth-child(3n+1) { grid-column:1 / -1; margin-top:4px; } }
'@
	Add "</style></head><body><main>"
	Add "<h1>Zobolin benchmark report</h1>"
	Add "<p class=""muted"">$(Esc "Scenario: $scenario ($kindText), $repeats repeat$(if ($repeats -ne 1) { 's' }), $dateText")</p>"

	Add "<div class=""card""><dl class=""facts"">"
	Add "<dt>PC</dt><dd>$(Esc "$(Get-Field $machine 'pc'): $(Get-Field $machine 'processor')$(if (Get-Field $machine 'ram_gb') { ", $(Fmt (Get-Field $machine 'ram_gb') 0) GB memory" })")</dd>"
	$cardText = if ($cardUsed) { [string]$cardUsed } else { "unknown" }
	if ($driver) { $cardText += ", driver $driver" }
	Add "<dt>Graphics card used</dt><dd>$(Esc $cardText)</dd>"
	$commitHtml = if ($commit) { "<span title=""$(Esc $commit)"">$(Esc $shortCommit)</span>" } else { "unknown" }
	if ([bool](Get-Field $machine "game_uncommitted_changes")) { $commitHtml += " <span class=""tag"">with uncommitted changes</span>" }
	Add "<dt>Game version</dt><dd>commit $commitHtml</dd>"
	$presetText = "$(Get-Field $summary 'preset')"
	if ($renderSize.Count -ge 2) { $presetText += " (pictures drawn at $(Fmt $renderSize[0] 0) &times; $(Fmt $renderSize[1] 0))" }
	Add "<dt>Graphics preset</dt><dd>$presetText</dd>"
	Add "<dt>Renderer</dt><dd>$(Esc $renderer)$(if ($godot) { Esc ", Godot $godot" })</dd>"
	Add "<dt>Date</dt><dd>$(Esc $dateText)</dd>"
	if ($null -ne $debug) {
		$debugText = if ([bool]$debug) { "Debug build (the editor's version of Godot): scripts run slower than in a finished game, so processor times are on the high side." } else { "Release build." }
		Add "<dt>Build</dt><dd>$(Esc $debugText)</dd>"
	}
	Add "</dl></div>"

	$warnings = @(Get-Field $summary "warnings" | Where-Object { $_ })
	if ($warnings.Count -eq 0) { $warnings = @(Get-Field $info "warnings" | Where-Object { $_ }) }
	$badRuns = @(Get-Field $info "runs" | Where-Object { $_ -and -not $_.ok })
	foreach ($bad in $badRuns) { $warnings += "Run $($bad.folder) did not count: $($bad.problem)" }
	if ($warnings.Count -gt 0) {
		Add "<div class=""card warn""><strong>Warnings</strong><ul>"
		foreach ($w in $warnings) { Add "<li>$(Esc $w)</li>" }
		Add "</ul></div>"
	}

	# ---------- Verdict ----------
	$verdict = @()
	$bounds = @($views | Where-Object { $null -ne $_.bound } | ForEach-Object { [double]$_.bound })
	if ($bounds.Count -gt 0) {
		$share = 0.0
		foreach ($b in $bounds) { $share += $b }
		$share /= $bounds.Count
		if ($share -ge 0.5) {
			$verdict += [string]::Format($Inv, "This PC is held back by the graphics card in {0:F0} % of frames (the frame waits for it to finish drawing).", $share * 100)
		} else {
			$verdict += [string]::Format($Inv, "This PC is held back by the processor in {0:F0} % of frames (the graphics card waits for it).", (1 - $share) * 100)
		}
	}
	$reach = @($views | Where-Object { $_.frame -le $BudgetMs }).Count
	$slowest = $views | Sort-Object frame -Descending | Select-Object -First 1
	$fastest = $views | Sort-Object frame | Select-Object -First 1
	if ($views.Count -eq 1) {
		$only = $views[0]
		$verdict += [string]::Format($Inv, "Target: 16.7 ms per frame = 60 fps. {0} takes {1:F1} ms per frame ({2:F0} fps), so it {3}.",
			$only.name, $only.frame, 1000.0 / [math]::Max(0.001, $only.frame), $(if ($reach -eq 1) { "reaches it" } else { "doesn't reach it" }))
	} elseif ($views.Count -gt 1) {
		$verdict += [string]::Format($Inv, "Target: 16.7 ms per frame = 60 fps. {0} of {1} views {7} it; frames take {2:F1} ms ({3}) to {4:F1} ms ({5}, {6:F0} fps).",
			$reach, $views.Count, $fastest.frame, $fastest.name, $slowest.frame, $slowest.name, 1000.0 / [math]::Max(0.001, $slowest.frame), $(if ($reach -eq 1) { "reaches" } else { "reach" }))
	}
	$drawParts = @($costs | Where-Object { $_.variant -ne "all_off" -and -not [bool](Get-Field $_ "cpu") -and -not [bool](Get-Field $_ "detail") -and -not ([string](Get-Field $_ "check")).StartsWith("NO") -and [double]$_.mean_frame_saving_ms -gt 0 } |
		Sort-Object { [double]$_.mean_frame_saving_ms } -Descending)
	if ($drawParts.Count -gt 0) {
		$list = ($drawParts | Select-Object -First 4 | ForEach-Object { "$((Get-LowerFirst (Get-PartName $_.variant))) $(Fmt $_.mean_frame_saving_ms 1) ms" }) -join ", "
		$verdict += "Biggest costs on the graphics card (frame time saved when switched off, average of the views): $list."
	}
	$cpuParts = @($costs | Where-Object { [bool](Get-Field $_ "cpu") -and -not ([string](Get-Field $_ "check")).StartsWith("NO") } | Sort-Object { [double](Get-Field $_ "mean_cpu_saving_ms") } -Descending)
	# Sessions from before step 5c recorded no processor time (0): left out.
	$cpuValues = @($views | Where-Object { $null -ne $_.cpu -and [double]$_.cpu -gt 0 } | ForEach-Object { [double]$_.cpu })
	if ($cpuValues.Count -gt 0) {
		$cpuMean = 0.0
		foreach ($c in $cpuValues) { $cpuMean += $c }
		$cpuMean /= $cpuValues.Count
		$what = if ($physicsMissing) { "(scripts; this older session didn't record physics time)" } else { "(scripts and physics)" }
		$sentence = [string]::Format($Inv, "The processor's own work {0} takes {1:F2} ms per frame on average", $what, $cpuMean)
		if ($cpuParts.Count -gt 0) {
			$top = $cpuParts[0]
			$sentence += [string]::Format($Inv, "; the biggest part of it is {0}: {1:F3} ms", (Get-LowerFirst (Get-PartName $top.variant)), [double](Get-Field $top "mean_cpu_saving_ms"))
		}
		$verdict += "$sentence."
	}
	# Stutters per run: each view's hitches hold one count per repeat.
	$totalHitches = 0
	$repeatCount = 1
	foreach ($v in $views) {
		$counts = @($v.hitches | Where-Object { $null -ne $_ })
		$repeatCount = [math]::Max($repeatCount, $counts.Count)
		foreach ($h in $counts) { $totalHitches += [int]$h }
	}
	$perRun = [math]::Round($totalHitches / $repeatCount)
	if ($totalHitches -eq 0) { $verdict += "No stutters in the measured views." }
	else {
		$stutterLine = "About $perRun stutter$(if ($perRun -ne 1) { 's' }) per run (frames much slower than the ones around them; $totalHitches over all $repeatCount runs); see the red marks in the charts."
		# Newer sessions say what was happening; the benchmark's own screenshots aren't the game's fault.
		$shots = 0
		foreach ($run in $runs) { foreach ($rs in @($run.segments)) { foreach ($h in @(Get-Field $rs "hitches")) { if ($h -and (Get-Field $h "cause") -eq "screenshot") { $shots++ } } } }
		if ($shots -gt 0) { $shotsPerRun = [math]::Round($shots / [math]::Max(1, @($runs).Count)); $stutterLine += " $shotsPerRun of them per run happened while the benchmark took its own screenshot, so they are not the game's." }
		$verdict += $stutterLine
	}
	# The biggest cause of the game's own stutters (newer sessions).
	$causeTotals = @{}
	foreach ($v in $views) {
		foreach ($pair in (Get-Pairs $v.causes)) {
			if ($pair.Name -eq "screenshot") { continue }
			if (-not $causeTotals.ContainsKey($pair.Name)) { $causeTotals[$pair.Name] = @{ count = 0.0; worst = 0.0; views = @() } }
			$entry = $causeTotals[$pair.Name]
			$entry.count += [double](Get-Field $pair.Value "count")
			$entry.worst = [math]::Max($entry.worst, [double](Get-Field $pair.Value "worst_ms"))
			$entry.views += $v.name
		}
	}
	if ($causeTotals.Count -gt 0) {
		$topCause = @($causeTotals.Keys | Sort-Object @{ Expression = { $causeTotals[$_].count }; Descending = $true }, @{ Expression = { $causeTotals[$_].worst }; Descending = $true }) | Select-Object -First 1
		$entry = $causeTotals[$topCause]
		$where = if ($views.Count -eq 1) { "in $($views[0].name)" } else { "over all the views" }
		$howMany = if ($entry.count -gt 0) { [string]::Format($Inv, "{0:0.#} per run {1}", $entry.count, $where) } else { "in some runs only" }
		$verdict += [string]::Format($Inv, "The biggest cause of the game's own stutters: {0} ({1}, the slowest {2:F1} ms).", (Get-LowerFirst (Get-CauseName $topCause)), $howMany, $entry.worst)
	}
	# A sweep: how the processor's cost grows with the count.
	$fitted = @($scaling | Where-Object { $null -ne (Get-Field $_ "cpu_fit") })
	if ($fitted.Count -gt 0) {
		$unit = Get-SweepUnit $scenario ([string](@($fitted[0].rows) | Select-Object -First 1).variant)
		$steep = @($fitted | Sort-Object { [double]$_.cpu_fit.slope } -Descending) | Select-Object -First 1
		$steadyCount = @($fitted | Where-Object { [double]$_.cpu_fit.r2 -ge 0.9 }).Count
		$grows = if ([double]$steep.cpu_fit.slope -ge 0) { "grows" } else { "shrinks" }
		$line = "Processor time $grows by $(Fmt-Ms ([math]::Abs([double]$steep.cpu_fit.slope))) ms per extra $($unit.one)"
		if ($fitted.Count -gt 1) { $line += " in $($steep.view) (the view where it grows fastest); it grows along a straight line in $steadyCount of $($fitted.Count) views." }
		elseif ($steadyCount -eq 1) { $line += ", steadily (along a straight line)." }
		else { $line += ", but not along a straight line." }
		$verdict += $line
	}
	if ($costs.Count -eq 0) { $verdict += "This session didn't switch parts off, so it can't say what each part costs (run zbench.ps1 with -Ablate for that)." }
	Add "<h2>Verdict</h2>"
	Add "<div class=""card verdict"">"
	foreach ($line in $verdict) { Add "<p>$(Esc $line)</p>" }
	Add "</div>"
	Add "<p class=""muted small"">ms = millisecond, a thousandth of a second. fps = frames per second. A view is one part of the test that is measured on its own (usually one fixed camera position).</p>"

	# ---------- Compared with the baseline ----------
	$compareRows = @(Get-Field $comparison "rows" | Where-Object { $null -ne $_ })
	if ($compareRows.Count -gt 0) {
		$metrics = @(
			@{ id = "mean_frame_ms"; label = "Average frame" },
			@{ id = "p99_frame_ms"; label = "Slowest 1 in 100 frames" },
			@{ id = "gpu_ms"; label = "Graphics card" },
			@{ id = "cpu_ms"; label = "Processor" }
		)
		Add "<h2>Compared with the baseline</h2>"
		$baseCommit = [string](Get-Field $comparison "baseline_commit")
		$baseShort = if ($baseCommit.Length -ge 7) { $baseCommit.Substring(0, 7) } else { $baseCommit }
		$baseDate = [string](Get-Field $comparison "baseline_date")
		$baseFile = [string](Get-Field $comparison "baseline_file")
		$baseText = "The baseline is an earlier session on this PC"
		if ($baseShort) { $baseText += ", game commit $baseShort" }
		if ($baseDate) { $baseText += ", worked out $($baseDate.Replace('T', ' '))" }
		$baseText += "."
		$fileHtml = ""
		if ($baseFile) { $fileHtml = ' <span class="muted small" style="overflow-wrap:anywhere">(' + (Esc $baseFile) + ')</span>' }
		Add "<p>$(Esc $baseText)$fileHtml</p>"
		$faster = 0; $slower = 0
		Add "<div class=""scroll""><table><thead><tr><th>View</th>"
		foreach ($m in $metrics) { Add "<th class=""n"">$(Esc $m.label) (ms)</th>" }
		Add "</tr></thead><tbody>"
		foreach ($row in $compareRows) {
			$cells = ""
			foreach ($m in $metrics) {
				$cell = Get-Field $row $m.id
				if ($null -eq $cell) { $cells += "<td class=""n muted"">-</td>"; continue }
				$verdictWord = [string](Get-Field $cell "verdict")
				$cls = if ($verdictWord -eq "faster") { "good" } elseif ($verdictWord -eq "slower") { "bad" } else { "same" }
				if ($verdictWord -eq "faster") { $faster++ } elseif ($verdictWord -eq "slower") { $slower++ }
				$changePct = [double](Get-Field $cell "change_share") * 100
				$sign = if ($changePct -gt 0) { "+" } else { "" }
				$cells += "<td class=""n $cls"">$(Fmt (Get-Field $cell 'before') 2) &rarr; $(Fmt (Get-Field $cell 'now') 2)<br><span class=""small"">$sign$(Fmt $changePct 1) %, $(Esc $verdictWord)</span></td>"
			}
			Add "<tr><td>$(Esc (Get-Field $row 'view'))</td>$cells</tr>"
		}
		Add "</tbody></table></div>"
		$summaryWord = if ($faster -eq 0 -and $slower -eq 0) { "Nothing changed beyond the noise." } else { "$faster number$(if ($faster -ne 1) { 's' }) got faster, $slower slower." }
		Add "<p class=""small"">$(Esc $summaryWord) <span class=""good"">Green = faster</span>, <span class=""bad"">red = slower</span>, <span class=""same"">grey = no change</span>.</p>"
		Add "<p class=""muted small"">$(Esc "A change counts only if it is over 5 % and outside the noise (more than the repeats of either session differed); anything smaller is shown as no change. Each cell: before, then now, in ms per frame; processor = the game's scripts and physics.")</p>"
	}

	# ---------- Top costs ----------
	if ($costs.Count -gt 0) {
		Add "<h2>Top costs</h2>"
		Add "<p>Each part was switched off on its own; its cost is the time saved. Parts that the graphics card draws are measured by the whole frame, processor parts by the processor's time per frame.</p>"
		$ranked = @($costs | Where-Object { $_.variant -ne "all_off" } | ForEach-Object {
			$isCpu = [bool](Get-Field $_ "cpu")
			$value = if ($isCpu) { [double](Get-Field $_ "mean_cpu_saving_ms") } else { [double]$_.mean_frame_saving_ms }
			[pscustomobject]@{ cost = $_; isCpu = $isCpu; value = $value }
		} | Sort-Object value -Descending)
		$allOff = @($costs | Where-Object { $_.variant -eq "all_off" }) | Select-Object -First 1
		Add "<div class=""scroll""><table><thead><tr><th class=""n"">#</th><th>Part</th><th>Uses</th><th class=""n"">Cost (ms)</th><th class=""n"">% of 16.7 ms</th>"
		foreach ($v in $views) { Add "<th class=""n"">$(Esc $v.name)</th>" }
		Add "<th>Inside the noise?</th><th>Checked</th><th>Notes</th></tr></thead><tbody>"
		$rank = 0
		$rows = @($ranked)
		if ($allOff) { $rows += [pscustomobject]@{ cost = $allOff; isCpu = $false; value = [double]$allOff.mean_frame_saving_ms } }
		foreach ($item in $rows) {
			$c = $item.cost
			$isTotal = $c.variant -eq "all_off"
			$digits = if ($item.isCpu) { 3 } else { 2 }
			$id = Get-PartId $c.variant
			$name = Get-PartName $c.variant
			$notes = @()
			$detail = [bool](Get-Field $c "detail")
			if ($detail -and -not $item.isCpu) {
				$parent = if ($PieceOf.ContainsKey($id)) { $PieceOf[$id] } else { "a bigger part" }
				$notes += "A piece of $parent, already counted in it."
			}
			$slowerIn = @()
			$fasterIn = @()
			$removes = Get-Field $c "removes"
			$inside = 0; $outside = 0
			$cells = @()
			foreach ($v in $views) {
				$cv = @($c.views | Where-Object { $_.view -eq $v.name }) | Select-Object -First 1
				if ($null -eq $cv) { $cells += "<td class=""n"">-</td>"; continue }
				$val = if ($item.isCpu) { Get-Field $cv "cpu_saving_ms" } else { $cv.frame_saving_ms }
				$out = if ($item.isCpu) { Get-Field $cv "cpu_outside_noise" } else { Get-Field $cv "outside_noise" }
				$isOut = [bool]$out
				if ($null -eq $out) { $isOut = $true }
				if ($isOut) { $outside++ } else { $inside++ }
				if ($isOut -and $null -ne $val -and [double]$val -lt 0) { $slowerIn += $v.name }
				if ($isOut -and $null -ne $val -and [double]$val -gt 0) { $fasterIn += $v.name }
				$cls = if ($null -ne $val -and [double]$val -lt 0) { "n neg" } elseif (-not $isOut) { "n noise" } else { "n" }
				$star = if ($isOut) { "" } else { "*" }
				$cells += "<td class=""$cls"">$(Fmt $val $digits)$star</td>"
			}
			$why = if ($item.isCpu) { "" } else { " This can happen when a part hides what is behind it: with it gone, more of that gets drawn." }
			if ($item.value -lt 0) {
				if ($fasterIn.Count -gt 0 -and $slowerIn.Count -gt 0) {
					$notes += "On average switching it off made the frame slower: slower in $($slowerIn -join ', '), faster in $($fasterIn -join ', ').$why"
				} else {
					$notes += "Switching it off made it slower.$why"
				}
			}
			elseif ($slowerIn.Count -gt 0) { $notes += "Switching it off made it slower in $($slowerIn -join ', ').$why" }
			$pictureChanged = ([string](Get-Field $c "check")).StartsWith("NO")
			if ($item.isCpu) {
				# Processor switches can still change the frame (the graphics card's side).
				$frameSaved = [double]$c.mean_frame_saving_ms
				$frameOut = @($c.views | Where-Object { [bool](Get-Field $_ "outside_noise") }).Count
				if ([math]::Abs($frameSaved) -ge 0.25 -and $frameOut -gt 0) {
					$word = if ($frameSaved -gt 0) { "faster" } else { "slower" }
					if ($pictureChanged) {
						$notes += [string]::Format($Inv, "The whole frame also got {0:F2} ms {1}, but the picture changed (something was no longer drawn), so that is not a real saving. Only the processor time counts.", [math]::Abs($frameSaved), $word)
					} else {
						$notes += [string]::Format($Inv, "The whole frame also got {0:F2} ms {1}: this changes the graphics card's work too.", [math]::Abs($frameSaved), $word)
					}
				}
			}
			$noiseText = if ($outside -eq 0) { "yes, too small to be sure" } elseif ($inside -gt 0) { "in $inside of $($inside + $outside) views" } else { "no" }
			$check = Get-Field $c "check"
			if (-not $check) { $check = if ([bool](Get-Field $c "verified")) { "yes (fewer draw calls or triangles)" } else { "not confirmed" } }
			$checkCls = if (([string]$check).StartsWith("NO")) { " neg" } else { "" }
			$resource = if ($item.isCpu) { "processor" } else { "graphics card" }
			$valueCls = if ($item.value -lt 0) { "n neg" } else { "n" }
			$share = $item.value / $BudgetMs * 100
			$nameHtml = "<strong>$(Esc $name)</strong>"
			if ($removes) { $nameHtml += "<br><span class=""muted small"">$(Esc "Switched off: $removes")</span>" }
			if ($isTotal) {
				$notes = @("Not ranked: all the drawing parts at once.")
				Add "<tr class=""total""><td class=""n""></td><td class=""part"">$nameHtml</td><td class=""res"">$resource</td><td class=""$valueCls"">$(Fmt $item.value $digits)</td><td class=""n"">$(Fmt $share 0) %</td>$($cells -join '')<td>$(Esc $noiseText)</td><td class=""chk$checkCls"">$(Esc $check)</td><td class=""note"">$(Esc ($notes -join ' '))</td></tr>"
			} else {
				$rank++
				Add "<tr><td class=""n"">$rank</td><td class=""part"">$nameHtml</td><td class=""res"">$resource</td><td class=""$valueCls"">$(Fmt $item.value $digits)</td><td class=""n"">$(Fmt $share $(if ($item.isCpu) { 1 } else { 0 })) %</td>$($cells -join '')<td>$(Esc $noiseText)</td><td class=""chk$checkCls"">$(Esc $check)</td><td class=""note"">$(Esc ($notes -join ' '))</td></tr>"
			}
		}
		Add "</tbody></table></div>"
		Add "<p class=""muted small"">* = inside the noise: smaller than how much the repeats differed, so it may be no real change. Cost is the average of the views; processor costs have 3 decimals because they are small. % of 16.7 ms = how much of the time one frame may take at 60 fps. Negative numbers (red) mean the frame got slower when the part was off.</p>"
	}

	# ---------- How it grows (a sweep) ----------
	if ($scaling.Count -gt 0) {
		$firstVariant = [string](@($scaling[0].rows) | Select-Object -First 1).variant
		$unit = Get-SweepUnit $scenario $firstVariant
		Add "<h2>How it grows</h2>"
		Add "<p>$(Esc "The same test was run with more and more $($unit.many). Each number is the middle value of the repeats; the dashed line is the straight line that fits the points best.")</p>"
		foreach ($sc in $scaling) {
			$scRows = @($sc.rows | Where-Object { $null -ne $_ } | Sort-Object { [double]$_.x })
			Add "<div class=""card""><h3>$(Esc $sc.view)</h3>"
			$sentences = @()
			foreach ($fitInfo in @(@{ fit = (Get-Field $sc "cpu_fit"); what = "Processor time" }, @{ fit = (Get-Field $sc "frame_fit"); what = "Frame time" })) {
				$fitValue = $fitInfo.fit
				if ($null -eq $fitValue) { continue }
				$slope = [double]$fitValue.slope
				$r2 = [double]$fitValue.r2
				$grows = if ($slope -ge 0) { "grows" } else { "shrinks" }
				$shape = if ($r2 -ge 0.9) { "it grows steadily" } else { "it does not grow along a straight line" }
				$sentences += [string]::Format($Inv, "{0} {1} by {2} ms per extra {3}; the straight line fits {4:F0} % ({5}).", $fitInfo.what, $grows, (Fmt-Ms ([math]::Abs($slope))), $unit.one, $r2 * 100, $shape)
			}
			foreach ($s in $sentences) { Add "<p>$(Esc $s)</p>" }
			$xLabel = if ($unit.one -eq "one") { "count" } else { "number of $($unit.many)" }
			$cpuPoints = @($scRows | ForEach-Object { [pscustomobject]@{ x = [double]$_.x; y = $(if ($null -ne (Get-Field $_ "cpu_ms")) { [double]$_.cpu_ms } else { $null }); label = [string]$_.variant } })
			$framePoints = @($scRows | ForEach-Object { [pscustomobject]@{ x = [double]$_.x; y = $(if ($null -ne (Get-Field $_ "frame_ms")) { [double]$_.frame_ms } else { $null }); label = [string]$_.variant } })
			Add "<div class=""growths"">"
			Add (New-GrowthChart "Processor time per frame (scripts and physics)" $cpuPoints (Get-Field $sc "cpu_fit") "s-cpu" $xLabel)
			Add (New-GrowthChart "Whole frame (average)" $framePoints (Get-Field $sc "frame_fit") "s-frame" $xLabel)
			Add "</div>"
			Add "<div class=""scroll""><table><thead><tr><th>Variant</th><th class=""n"">How many</th><th class=""n"">Average frame (ms)</th><th class=""n"">Slowest 1 in 100 (ms)</th><th class=""n"">Graphics card (ms)</th><th class=""n"">Processor (ms)</th><th class=""n"">of it physics (ms)</th><th class=""n"">Stutters per run</th></tr></thead><tbody>"
			foreach ($r in $scRows) {
				Add "<tr><td>$(Esc $r.variant)</td><td class=""n"">$(Esc ([string]::Format($Inv, '{0:0.##}', [double]$r.x)))</td><td class=""n"">$(Fmt (Get-Field $r 'frame_ms') 2)</td><td class=""n"">$(Fmt (Get-Field $r 'p99_ms') 2)</td><td class=""n"">$(Fmt (Get-Field $r 'gpu_ms') 2)</td><td class=""n"">$(Fmt (Get-Field $r 'cpu_ms') 3)</td><td class=""n"">$(Fmt (Get-Field $r 'physics_ms') 3)</td><td class=""n"">$(if ($null -ne (Get-Field $r 'hitches')) { [string]::Format($Inv, '{0:0.#}', [double]$r.hitches) } else { '-' })</td></tr>"
			}
			Add "</tbody></table></div></div>"
		}
		Add "<p class=""muted small"">Processor = the game's scripts and the physics step, averaged over all frames. A straight line that fits 90 % or more means the cost grows steadily with the count; less means it jumps or grows faster than the count.</p>"
	}

	# ---------- Frame-time charts ----------
	Add "<h2>Frame time over each view</h2>"
	$fromText = if ($runVariant) { "From the first run of $runVariant (the smallest variant)." } else { "From the first run with everything on." }
	Add "<p>$(Esc $fromText) Lower is better; below the dashed line is faster than 60 fps.</p>"
	Add "<div class=""legend""><span><span class=""key"" style=""background:var(--frame)""></span>whole frame</span><span><span class=""key"" style=""background:var(--gpu)""></span>graphics card's time</span><span><span class=""key dot"" style=""background:var(--bad)""></span>stutter (point at it for details)</span></div>"
	foreach ($v in $views) {
		$rows = if ($rowsByView.ContainsKey($v.name)) { $rowsByView[$v.name] } else { @() }
		$runHitches = @()
		if ($firstRun) {
			$runSeg = @($firstRun.segments | Where-Object { $_.name -eq $v.name }) | Select-Object -First 1
			if ($runSeg) { $runHitches = @(Get-Field $runSeg "hitches") }
		}
		Add "<div class=""card""><h3>$(Esc $v.name)</h3>"
		if (@($rows).Count -gt 0) { Add (New-FrameChart $v.name $rows $runHitches) }
		else { Add "<p class=""muted"">No frame rows for this view.</p>" }
		$line = [string]::Format($Inv, "Typical frame {0:F2} ms ({1:F0} fps)", $v.frame, 1000.0 / [math]::Max(0.001, $v.frame))
		if ($null -ne $v.p99) { $line += [string]::Format($Inv, "; slowest 1 in 100 frames {0:F2} ms", [double]$v.p99) }
		$hitchCount = @($runHitches | Where-Object { $_ }).Count
		$line += "; stutters in this run: $hitchCount."
		Add "<p class=""small"">$(Esc $line)</p></div>"
	}

	# ---------- What causes the stutters ----------
	$causeViews = @($views | Where-Object { @(Get-Pairs $_.causes).Count -gt 0 })
	if ($causeViews.Count -gt 0) {
		Add "<h2>What causes the stutters</h2>"
		Add "<p>Each stutter is put down to what the game was doing in the frames around it (its main cause). Sorted by how often it happens.</p>"
		foreach ($v in $causeViews) {
			$causeRows = @(Get-Pairs $v.causes | ForEach-Object {
				[pscustomobject]@{ id = $_.Name; count = [double](Get-Field $_.Value "count"); worst = [double](Get-Field $_.Value "worst_ms"); at = @(Get-Field $_.Value "at_x" | Where-Object { $null -ne $_ }) }
			} | Sort-Object @{ Expression = { $_.id -eq "screenshot" } }, @{ Expression = { $_.count }; Descending = $true }, @{ Expression = { $_.worst }; Descending = $true })
			Add "<div class=""card""><h3>$(Esc $v.name)</h3>"
			Add "<div class=""scroll""><table><thead><tr><th>Main cause</th><th class=""n"">Stutters per run</th><th class=""n"">Slowest (ms)</th><th>Where (world x, first run)</th></tr></thead><tbody>"
			foreach ($c in $causeRows) {
				$countText = if ($c.count -gt 0) { [string]::Format($Inv, "{0:0.#}", $c.count) } else { "in some runs only" }
				$places = @($c.at | ForEach-Object { [string]::Format($Inv, "{0:F0}", [double]$_) })
				$placeText = if ($places.Count -eq 0) { "-" } elseif ($places.Count -gt 12) { (($places | Select-Object -First 12) -join ", ") + " and $($places.Count - 12) more" } else { $places -join ", " }
				$rowCls = if ($c.id -eq "screenshot") { " class=""own""" } else { "" }
				Add "<tr$rowCls><td title=""$(Esc $c.id)"">$(Esc (Get-CauseName $c.id))</td><td class=""n"">$(Esc $countText)</td><td class=""n"">$(Fmt $c.worst 1)</td><td>$(Esc $placeText)</td></tr>"
			}
			Add "</tbody></table></div></div>"
		}
		Add "<p class=""muted small"">$(Esc "Stutters per run: the middle value over the repeats; when that is 0, the cause happened in some runs only. Slowest: the slowest such stutter in any repeat. Where: the camera's world x position in the first run. When several things happened at once, the main cause is the first of: the screenshot, re-centring, new near trees, new trunk collision, new far houses and rocks, new grass tiles, shaders, physics catching up (which mostly follows a slow frame rather than causing it).")</p>"
	}

	# ---------- Where the frame goes ----------
	Add "<h2>Where the frame goes</h2>"
	Add "<p>The processor and the graphics card work at the same time, so these bars overlap rather than add up: the frame is as long as the slower side (plus a little waiting).</p>"
	$scale = $BudgetMs
	foreach ($v in $views) {
		foreach ($x in @($v.frame, $v.gpu, $v.render, $v.cpu)) { if ($null -ne $x -and [double]$x -gt $scale) { $scale = [double]$x } }
	}
	$scale *= 1.05
	$goal = $BudgetMs / $scale * 100
	foreach ($v in $views) {
		Add "<div class=""card""><h3>$(Esc $v.name)</h3><div class=""bars"">"
		$bars = @(
			@{ label = "Whole frame"; value = $v.frame; color = "var(--frame)"; digits = 2 },
			@{ label = "Graphics card"; value = $v.gpu; color = "var(--gpu)"; digits = 2 },
			@{ label = "Preparing the drawing (processor)"; value = $v.render; color = "var(--render)"; digits = 2 },
			@{ label = $(if ($v.cpuHasPhysics) { "Scripts and physics (processor)" } else { "Scripts (processor)" }); value = $v.cpu; color = "var(--cpu)"; digits = 3 }
		)
		foreach ($b in $bars) {
			if ($null -eq $b.value) {
				Add "<span>$(Esc $b.label)</span><span class=""muted small"">not recorded</span><span></span>"
				continue
			}
			$pct = [math]::Max(0.3, [double]$b.value / $scale * 100)
			Add "<span>$(Esc $b.label)</span><span class=""bar-wrap""><span class=""bar"" style=""display:block;width:$(Fmt $pct 1)%;background:$($b.color)""></span><span class=""goal"" style=""left:$(Fmt $goal 1)%"" title=""16.7 ms = 60 fps""></span></span><span class=""v"">$(Fmt $b.value $b.digits) ms</span>"
		}
		Add "</div></div>"
	}
	$physNote = if ($physicsMissing) { " This older session didn't record physics time separately, so the scripts bar shows scripts only (typical frame)." } else { "" }
	Add "<p class=""muted small"">$(Esc "Graphics card: its time to draw one frame (typical frame). Preparing the drawing: the processor's time to hand the frame to the graphics card (typical frame). Scripts and physics: the game's own code and the physics step, averaged over all frames.$physNote The dashed line is 16.7 ms.")</p>"

	# ---------- Where the processor time goes ----------
	$zoneViews = @($views | Where-Object { @(Get-Pairs $_.zones).Count -gt 0 })
	if ($zoneViews.Count -gt 0) {
		Add "<h2>Where the processor time goes</h2>"
		Add "<p>Stopwatches in the game's own systems: the average time per frame, and the slowest single frame (a big slowest frame with a small average is a one-off spike, so a stutter rather than a lower frame rate).</p>"
		foreach ($v in $zoneViews) {
			$zoneList = @(Get-Pairs $v.zones | ForEach-Object {
				[pscustomobject]@{ id = $_.Name; mean = [double](Get-Field $_.Value "mean_ms"); max = [double](Get-Field $_.Value "max_ms") }
			})
			$zoneIds = @($zoneList | ForEach-Object { $_.id })
			$tops = @($zoneList | Where-Object { $_.id.IndexOf(".") -lt 0 -or $zoneIds -notcontains $_.id.Substring(0, $_.id.IndexOf(".")) } | Sort-Object mean -Descending)
			Add "<div class=""card""><h3>$(Esc $v.name)</h3>"
			Add "<div class=""scroll""><table><thead><tr><th>Part</th><th class=""n"">Average per frame (ms)</th><th class=""n"">Slowest frame (ms)</th></tr></thead><tbody>"
			if ($null -ne $v.processMean -or $null -ne $v.physicsMean) {
				$together = 0.0
				if ($null -ne $v.processMean) { $together += [double]$v.processMean }
				if ($null -ne $v.physicsMean) { $together += [double]$v.physicsMean }
				$split = "all scripts $(Fmt-Ms $v.processMean), physics $(Fmt-Ms $v.physicsMean)"
				Add "<tr class=""total""><td>Scripts and physics together<br><span class=""muted small"">$(Esc $split)</span></td><td class=""n"">$(Fmt-Ms $together)</td><td class=""n""></td></tr>"
			}
			foreach ($z in $tops) {
				$dot = $z.id.IndexOf(".")
				$name = if ($dot -gt 0 -and -not $ZoneNames.ContainsKey($z.id)) { $z.id } elseif ($dot -gt 0) { "$(Get-ZoneName $z.id.Substring(0, $dot)): $(Get-ZoneName $z.id)" } else { Get-ZoneName $z.id }
				Add "<tr><td title=""$(Esc $z.id)"">$(Esc $name)</td><td class=""n"">$(Fmt-Ms $z.mean)</td><td class=""n"">$(Fmt $z.max 2)</td></tr>"
				$pieces = @($zoneList | Where-Object { $_.id.StartsWith("$($z.id).") } | Sort-Object mean -Descending)
				foreach ($p in $pieces) {
					Add "<tr><td class=""piece"" title=""$(Esc $p.id)"">&ndash; $(Esc (Get-ZoneName $p.id))</td><td class=""n"">$(Fmt-Ms $p.mean)</td><td class=""n"">$(Fmt $p.max 2)</td></tr>"
				}
			}
			if ($null -ne $v.unattributedProcess) { Add "<tr class=""own""><td>Scripts without a stopwatch</td><td class=""n"">$(Fmt-Ms $v.unattributedProcess)</td><td class=""n""></td></tr>" }
			if ($null -ne $v.unattributedPhysics) { Add "<tr class=""own""><td>Physics without a stopwatch (mostly the physics engine's own step)</td><td class=""n"">$(Fmt-Ms $v.unattributedPhysics)</td><td class=""n""></td></tr>" }
			Add "</tbody></table></div></div>"
		}
		Add "<p class=""muted small"">Indented rows are pieces of the part above them, already counted in it. Parts marked (physics) run in the physics step and count towards the physics time. Each number is the middle value over the repeats.</p>"
	}

	# ---------- Do the parts add up? ----------
	if ($interaction.Count -gt 0) {
		$apart = @()
		foreach ($i in $interaction) {
			$v = @($views | Where-Object { $_.name -eq $i.view }) | Select-Object -First 1
			$limit = 0.25
			if ($v) { $limit = [math]::Max($limit, $v.band * $v.frame) }
			if ([math]::Abs([double]$i.sum_of_parts_ms - [double]$i.all_off_saving_ms) -gt $limit) { $apart += $i }
		}
		Add "<h2>Do the parts add up?</h2>"
		if ($apart.Count -gt 0) {
			Add "<div class=""card warn""><p>$(Esc "The parts don't simply add up: switched off one at a time, their savings together differ from switching everything off at once. The parts affect each other (one hides another, or they share a drawing pass), so each part's cost above means: with everything else on. The ranking still holds.")</p></div>"
		} else {
			Add "<p>$(Esc 'The parts add up to everything off (within the noise), so they hardly affect each other.')</p>"
		}
		Add "<div class=""scroll""><table><thead><tr><th>View</th><th class=""n"">Parts one by one, added (ms)</th><th class=""n"">All off at once (ms)</th><th class=""n"">Difference</th><th class=""n"">Frame left with all off</th></tr></thead><tbody>"
		foreach ($i in $interaction) {
			$diff = [double]$i.all_off_saving_ms - [double]$i.sum_of_parts_ms
			Add "<tr><td>$(Esc $i.view)</td><td class=""n"">$(Fmt $i.sum_of_parts_ms 2)</td><td class=""n"">$(Fmt $i.all_off_saving_ms 2)</td><td class=""n"">$(if ($diff -ge 0) { '+' })$(Fmt $diff 2)</td><td class=""n"">$(Fmt $i.floor_frame_ms 2) ms</td></tr>"
		}
		Add "</tbody></table></div>"
		Add "<p class=""muted small"">Pieces (such as the trees' shadows) are left out of the sum, so nothing is counted twice. What is left with everything off is the frame's fixed part (the depth pass, tonemapping and the 2D overlay).</p>"
	}

	# ---------- Repeats ----------
	Add "<h2>How much the repeats differed</h2>"
	$worst = 0.0
	$band = $noiseFloor
	foreach ($v in $views) {
		if ($v.spread -gt $worst) { $worst = $v.spread }
		if ($v.band -gt $band) { $band = $v.band }
	}
	Add "<p>$(Esc ([string]::Format($Inv, 'Every run is repeated and the middle value is used. On this PC the repeats differed by up to {0:F1} %, so changes smaller than {1:F1} % count as no change (the noise band; it is never below {2:F1} %).', $worst * 100, $band * 100, $noiseFloor * 100)))</p>"
	$maxRepeats = 0
	foreach ($v in $views) { if ($v.repeatsMs.Count -gt $maxRepeats) { $maxRepeats = $v.repeatsMs.Count } }
	Add "<div class=""scroll""><table><thead><tr><th>View</th>"
	for ($k = 1; $k -le $maxRepeats; $k++) { Add "<th class=""n"">Run $k (ms)</th>" }
	Add "<th class=""n"">Middle value</th><th class=""n"">Spread</th><th class=""n"">Noise band</th></tr></thead><tbody>"
	foreach ($v in $views) {
		$cells = ""
		for ($k = 0; $k -lt $maxRepeats; $k++) {
			$cells += if ($k -lt $v.repeatsMs.Count) { "<td class=""n"">$(Fmt $v.repeatsMs[$k] 2)</td>" } else { "<td class=""n"">-</td>" }
		}
		$viewBand = $v.band
		Add "<tr><td>$(Esc $v.name)</td>$cells<td class=""n"">$(Fmt $v.frame 2)</td><td class=""n"">$(Fmt ($v.spread * 100) 1) %</td><td class=""n"">$(Fmt ($viewBand * 100) 1) % = $(Fmt ($viewBand * $v.frame) 2) ms</td></tr>"
	}
	Add "</tbody></table></div>"
	Add "<p class=""muted small"">Spread = (slowest run - fastest run) / middle value. These are the runs with everything on.</p>"

	if ($notShown.Count -gt 0) {
		Add "<h2>Not shown</h2><ul>"
		foreach ($n in $notShown) { Add "<li>$(Esc $n)</li>" }
		Add "</ul>"
	}
	Add "<p class=""muted small"">$(Esc "Made by the Zobolin benchmark tool from $(Split-Path $dir -Leaf).")</p>"
	Add "</main></body></html>"

	$target = [System.IO.Path]::GetFullPath($OutFile)
	[System.IO.File]::WriteAllText($target, $html.ToString(), (New-Object System.Text.UTF8Encoding $false))
	return $target
}

Export-ModuleMember -Function New-BenchReport
