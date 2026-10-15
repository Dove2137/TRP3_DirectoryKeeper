# Builds the installable zip of a released version: the three addon folders, exactly as tagged,
# with the licence inside the main addon folder. Extracting the zip into Interface\AddOns gives
# the right layout. Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File tools\package.ps1 -Version 1.0.0
# The zip is written to dist\TRP3_DirectoryKeeper-<version>.zip.

param(
	[Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$tag = "v$Version"
$dist = Join-Path $repo "dist"
$zip = Join-Path $dist "TRP3_DirectoryKeeper-$Version.zip"

git -C $repo rev-parse --verify --quiet "refs/tags/$tag" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Tag $tag does not exist. Tag the release first." }

New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $zip) { Remove-Item $zip }

# The licence from the tag goes into the main addon folder as LICENSE.txt.
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("trp3dk-package-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $staging | Out-Null
$license = Join-Path $staging "LICENSE.txt"
cmd /c "git -C `"$repo`" show ${tag}:LICENSE > `"$license`""
if ($LASTEXITCODE -ne 0) { throw "could not read LICENSE from $tag" }

# git archive takes the addon files from the tag, never from the working folder.
git -C $repo archive --format=zip --output="$zip" `
	--prefix=TRP3_DirectoryKeeper/ --add-file="$license" `
	--prefix= $tag TRP3_DirectoryKeeper TRP3_DirectoryKeeper_Archive TRP3_DirectoryKeeper_Exchange
$exitCode = $LASTEXITCODE
Remove-Item -Recurse -Force $staging
if ($exitCode -ne 0) { throw "git archive failed" }

Write-Host "built $zip"
