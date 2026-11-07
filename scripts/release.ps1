<#
.SYNOPSIS
  Build, version-bump, tag and publish a new Family Health release.

.DESCRIPTION
  Family Health isn't on the Play Store, so updates are shipped as GitHub
  Releases: the app itself checks https://github.com/Indla26v/family-health-app
  for a newer tag and offers to download + install it in-app (see
  lib/services/app_update.dart). This script is the publishing half:

    1. Bumps the build number in pubspec.yaml (version: X.Y.Z+B -> B+1)
       — pass -Version to also change the X.Y.Z part.
    2. Builds the release APK.
    3. Copies it to apk/FamilyHealth.apk and, if present, the Google Drive
       folder (first-install source — the in-app updater takes over after
       that).
    4. Commits the version bump, tags it vX.Y.Z+B, and pushes both.
    5. Publishes a GitHub Release at that tag with the APK attached.

  Commit your other code changes FIRST (git add / git commit as normal) —
  this script only commits the pubspec.yaml/pubspec.lock version bump.

.PARAMETER Notes
  Release notes shown in the app's "Update available" sheet. If omitted,
  you'll be prompted (or pass one to keep it non-interactive).

.PARAMETER Version
  Optional new version name, e.g. "1.1.0". Default: keep the current name
  and only bump the build number.

.PARAMETER SkipBuild
  Skip `flutter build apk` and reuse the existing build output (for
  re-publishing after a build you already ran).

.EXAMPLE
  .\scripts\release.ps1 -Notes "Fixed BP/sugar reading times on Today"
#>
param(
  [string]$Notes = "",
  [string]$Version = "",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

# ---- 1. Bump the version in pubspec.yaml ----------------------------------
$pubspec = "pubspec.yaml"
$content = Get-Content $pubspec -Raw
if ($content -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  throw "Could not find a 'version: X.Y.Z+B' line in $pubspec"
}
$curName = $Matches[1]
$curBuild = [int]$Matches[2]
$newBuild = $curBuild + 1
$newName = if ($Version -ne "") { $Version } else { $curName }
$newVersion = "$newName+$newBuild"
$tag = "v$newVersion"

Write-Host "Version: $curName+$curBuild -> $newVersion  (tag $tag)" -ForegroundColor Cyan
$content = $content -replace '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $newVersion"
Set-Content $pubspec $content -NoNewline

# ---- 2. Build -------------------------------------------------------------
if (-not $SkipBuild) {
  flutter build apk --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
}
$apkSrc = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkSrc)) { throw "Built APK not found at $apkSrc (run without -SkipBuild first)" }

# ---- 3. Copy to the usual places ------------------------------------------
New-Item -ItemType Directory -Force -Path "apk" | Out-Null
Copy-Item $apkSrc "apk\FamilyHealth.apk" -Force
Write-Host "Copied to apk\FamilyHealth.apk" -ForegroundColor Green

$driveDir = "G:\My Drive\My Family"
if (Test-Path $driveDir) {
  Copy-Item $apkSrc "$driveDir\FamilyHealth.apk" -Force
  Write-Host "Copied to $driveDir\FamilyHealth.apk" -ForegroundColor Green
} else {
  Write-Host "Google Drive folder not found ($driveDir) — skipped." -ForegroundColor Yellow
}

# ---- 4. Commit, tag, push ---------------------------------------------------
git add pubspec.yaml pubspec.lock
git commit -m "Release $tag" | Out-Null
git tag $tag
git push origin HEAD
git push origin $tag
Write-Host "Pushed commit + tag $tag" -ForegroundColor Green

# ---- 5. Publish the GitHub Release -----------------------------------------
if ($Notes -eq "") { $Notes = "Release $tag" }
gh release create $tag "apk\FamilyHealth.apk" --title $tag --notes $Notes
if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }

Write-Host "`nDone — $tag is live. Phones with the app installed will see 'Update available' within $(20) hours, or right away via Settings -> Check for updates." -ForegroundColor Cyan
