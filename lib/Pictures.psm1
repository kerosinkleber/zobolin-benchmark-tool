# SPDX-License-Identifier: GPL-3.0-or-later
# Compares two screenshots of the same view, for switches that must not
# change the picture (the processor and physics switches). Found needed in
# step 5c: with re-centring off, the grass vanished far from the centre,
# while draw calls and triangles stayed the same.

Add-Type -AssemblyName System.Drawing

# The size both pictures are shrunk to before comparing (smooths out tiny
# differences such as moving cloud edges or grass waving).
$CompareWidth = 160
$CompareHeight = 90
# The information panel (top left) shows changing numbers: left out.
$PanelWidthShare = 0.34
$PanelHeightShare = 0.36

function Get-SmallPicture([string] $Path) {
	$source = [System.Drawing.Bitmap]::FromFile($Path)
	try {
		$small = New-Object System.Drawing.Bitmap $CompareWidth, $CompareHeight
		$canvas = [System.Drawing.Graphics]::FromImage($small)
		$canvas.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
		$canvas.DrawImage($source, 0, 0, $CompareWidth, $CompareHeight)
		$canvas.Dispose()
		return $small
	} finally {
		$source.Dispose()
	}
}

# Average difference of two pictures, from 0 (the same) to 1 (black against
# white), leaving out the information panel. $null if a picture is missing.
function Compare-Pictures([string] $PathA, [string] $PathB) {
	if (-not (Test-Path $PathA) -or -not (Test-Path $PathB)) { return $null }
	$a = Get-SmallPicture $PathA
	$b = Get-SmallPicture $PathB
	try {
		$panelRight = [int]($CompareWidth * $PanelWidthShare)
		$panelBottom = [int]($CompareHeight * $PanelHeightShare)
		$total = 0.0
		$count = 0
		for ($y = 0; $y -lt $CompareHeight; $y++) {
			for ($x = 0; $x -lt $CompareWidth; $x++) {
				if ($x -lt $panelRight -and $y -lt $panelBottom) { continue }
				$pa = $a.GetPixel($x, $y)
				$pb = $b.GetPixel($x, $y)
				$total += [math]::Abs($pa.R - $pb.R) + [math]::Abs($pa.G - $pb.G) + [math]::Abs($pa.B - $pb.B)
				$count++
			}
		}
		return $total / ($count * 3.0 * 255.0)
	} finally {
		$a.Dispose()
		$b.Dispose()
	}
}

Export-ModuleMember -Function Compare-Pictures
