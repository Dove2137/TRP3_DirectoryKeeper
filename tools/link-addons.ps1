# Links the addon folders of this repository into the game's AddOns folder (directory junctions),
# so the game loads the addon straight from the repository. Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File tools\link-addons.ps1 [-AddOns <path to Interface\AddOns>]

param(
	[string]$AddOns = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$folders = @("TRP3_DirectoryKeeper", "TRP3_DirectoryKeeper_Archive", "TRP3_DirectoryKeeper_Exchange")

if (-not (Test-Path $AddOns)) { throw "AddOns folder not found: $AddOns" }

foreach ($name in $folders) {
	$link = Join-Path $AddOns $name
	$target = Join-Path $repo $name
	if (Test-Path $link) {
		$item = Get-Item $link -Force
		if ($item.LinkType -ne "Junction") {
			throw "$link exists and is a real folder, not a link. Move it away first."
		}
		cmd /c rmdir "$link" | Out-Null # removes the link only, never the target
	}
	New-Item -ItemType Junction -Path $link -Target $target | Out-Null
	Write-Host "linked $name"
}
Write-Host "Restart the game so it detects new addon folders."
