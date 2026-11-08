# SPDX-License-Identifier: GPL-3.0-or-later
# Makes the report page (report.html) for a finished benchmark session.
#
#   powershell -ExecutionPolicy Bypass -File report.ps1 results\<session folder>
#
# The page opens in any web browser, also without internet.

param(
	[Parameter(Mandatory = $true, Position = 0)] [string] $Folder,
	[string] $Out = ""
)

Import-Module (Join-Path $PSScriptRoot "lib\Report.psm1") -Force
try {
	$page = if ($Out) { New-BenchReport -Session $Folder -OutFile $Out } else { New-BenchReport -Session $Folder }
	Write-Host "Report: $page" -ForegroundColor Green
} catch {
	Write-Host "Could not make the report: $($_.Exception.Message)" -ForegroundColor Red
	exit 1
}
