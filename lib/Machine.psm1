# SPDX-License-Identifier: GPL-3.0-or-later
# The PC's details for each benchmark session: processor, graphics cards and
# drivers, memory, Windows, power plan, battery, and the game repo's commit.

# Windows' own power plans that run the processor at full speed.
$FastPlans = @(
	"8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", # High performance
	"e9a42b02-d5df-448d-aa00-03f14749eb61"  # Ultimate performance
)

function Get-PowerPlan {
	$line = (powercfg /getactivescheme) -join " "
	if ($line -match '([0-9a-fA-F-]{36})\s+\((.+)\)') {
		$guid = $Matches[1].ToLower()
		return [ordered]@{ guid = $guid; name = $Matches[2].Trim(); full_speed = ($FastPlans -contains $guid) }
	}
	return [ordered]@{ guid = ""; name = "unknown"; full_speed = $false }
}

function Get-GameCommit([string] $GameRepo) {
	try {
		$commit = (git -C $GameRepo rev-parse HEAD 2>$null)
		$dirty = [bool](git -C $GameRepo status --porcelain 2>$null)
		if ($commit) { return [ordered]@{ commit = $commit.Trim(); uncommitted_changes = $dirty } }
	} catch {}
	return [ordered]@{ commit = "unknown"; uncommitted_changes = $true }
}

function Get-MachineInfo([string] $GameRepo) {
	$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
	$system = Get-CimInstance Win32_ComputerSystem
	$os = Get-CimInstance Win32_OperatingSystem
	$cards = @(Get-CimInstance Win32_VideoController | ForEach-Object {
		[ordered]@{ name = $_.Name; driver = $_.DriverVersion }
	})
	$battery = Get-CimInstance Win32_Battery | Select-Object -First 1
	# BatteryStatus 1 means it is running on the battery.
	$onBattery = ($null -ne $battery) -and ($battery.BatteryStatus -eq 1)
	$game = Get-GameCommit $GameRepo
	return [ordered]@{
		pc = $env:COMPUTERNAME
		processor = $cpu.Name.Trim()
		cores = $cpu.NumberOfCores
		threads = $cpu.NumberOfLogicalProcessors
		ram_gb = [math]::Round($system.TotalPhysicalMemory / 1GB, 1)
		graphics_cards = $cards
		windows = "$($os.Caption) $($os.Version)"
		power_plan = Get-PowerPlan
		has_battery = ($null -ne $battery)
		on_battery = $onBattery
		game_commit = $game.commit
		game_uncommitted_changes = $game.uncommitted_changes
	}
}

Export-ModuleMember -Function Get-MachineInfo, Get-PowerPlan, Get-GameCommit
