# SPDX-License-Identifier: GPL-3.0-or-later
# Statistics across repeats of a run. Per-frame statistics are worked out
# inside the game (BenchStats); these only combine the per-run results.

# The smallest noise band (1.5 %), as in BenchStats.MIN_NOISE_SHARE. Repeats
# on the development PC agree within 0.7 %, so 1.5 % is still twice that
# (owner's decision, 2026-11-08; it was 3 %).
$MinNoiseShare = 0.015

function Get-Median([double[]] $Values) {
	if ($Values.Count -eq 0) { return 0.0 }
	$sorted = $Values | Sort-Object
	$middle = [math]::Floor(($sorted.Count - 1) / 2)
	if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$middle] }
	return ([double]$sorted[$middle] + [double]$sorted[$middle + 1]) / 2.0
}

# How far repeats spread, as a share of their median, and the noise band a
# change must leave to count (never below $MinNoiseShare).
function Get-NoiseBand([double[]] $Values) {
	$median = Get-Median $Values
	$spread = 0.0
	if ($median -gt 0 -and $Values.Count -gt 1) {
		$measure = $Values | Measure-Object -Minimum -Maximum
		$spread = ($measure.Maximum - $measure.Minimum) / $median
	}
	return [ordered]@{ median = $median; spread_share = $spread; band_share = [math]::Max($MinNoiseShare, $spread) }
}

Export-ModuleMember -Function Get-Median, Get-NoiseBand -Variable MinNoiseShare
