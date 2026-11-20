param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version,
  [Parameter(Mandatory = $true)]
  [ValidateRange(1, 2100000000)]
  [int]$Build,
  [ValidateSet("universal", "arm64-v8a", "armeabi-v7a", "x86_64")]
  [string]$OnlyTarget,
  [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$sdkPath = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$buildTools = Get-ChildItem (Join-Path $sdkPath "build-tools") -Directory |
  Where-Object { (Test-Path (Join-Path $_.FullName "aapt.exe")) -and (Test-Path (Join-Path $_.FullName "apksigner.bat")) } |
  Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $buildTools) { throw "Android SDK build tools with aapt and apksigner are required." }
$aapt = Join-Path $buildTools.FullName "aapt.exe"
$signer = Join-Path $buildTools.FullName "apksigner.bat"
$publishedSigner = "3dfc28b9be40082dc97ff5fdade7a637fb987100c2e7e136568f2f087b04d58b"
$output = Join-Path "apk" "v$Version+$Build"
$targets = [ordered]@{ "universal" = ""; "arm64-v8a" = "android-arm64"; "armeabi-v7a" = "android-arm"; "x86_64" = "android-x64" }
$selectedTargets = if ($OnlyTarget) { @($OnlyTarget) } else { @($targets.Keys) }
$previousAbi = $env:FAMILY_HEALTH_APK_ABI
try {
  if (-not $VerifyOnly) { New-Item -ItemType Directory -Force -Path $output | Out-Null }
  foreach ($target in $selectedTargets) {
    $isUniversal = $target -eq "universal"
    $assetName = if ($isUniversal) { "FamilyHealth.apk" } else { "FamilyHealth-$target.apk" }
    $asset = Join-Path $output $assetName
    if (-not $VerifyOnly) {
      $env:FAMILY_HEALTH_APK_ABI = if ($isUniversal) { $null } else { $target }
      $flutterArgs = @("build", "apk", "--release", "--no-pub", "--build-name=$Version", "--build-number=$Build")
      if (-not $isUniversal) { $flutterArgs += "--target-platform=$($targets[$target])" }
      & flutter @flutterArgs
      if ($LASTEXITCODE -ne 0) { throw "Flutter build failed for $target" }
      Copy-Item -LiteralPath "build\app\outputs\flutter-apk\app-release.apk" -Destination $asset -Force
    }

    $metadata = & $aapt dump badging $asset
    if ($LASTEXITCODE -ne 0 -or -not ($metadata -match "package: name='com.familyhealth.family_health' versionCode='$Build' versionName='$([regex]::Escape($Version))'")) {
      throw "Unexpected package name or version for $asset"
    }
    $nativeCode = @($metadata | Where-Object { $_ -like "native-code:*" })
    $abis = @([regex]::Matches(($nativeCode -join " "), "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    $expectedAbis = if ($isUniversal) { @("arm64-v8a", "armeabi-v7a", "x86_64") } else { @($target) }
    if (-not $abis.Count -or (Compare-Object $expectedAbis $abis)) { throw "Unexpected native architectures in $asset" }
    $certs = & $signer verify --print-certs $asset
    if ($LASTEXITCODE -ne 0 -or -not ($certs -match "certificate SHA-256 digest: $publishedSigner")) {
      throw "Signing certificate does not match the published APK for $asset"
    }
    $file = Get-Item -LiteralPath $asset
    $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "$assetName | $($file.Length) bytes | sha256:$hash"
    $gzipPath = "$asset.gz"
    if (-not $VerifyOnly -or -not (Test-Path -LiteralPath $gzipPath)) {
      $inputFile = $file.OpenRead()
      try {
        $outputFile = [IO.File]::Create($gzipPath)
        try {
          $gzip = [IO.Compression.GZipStream]::new($outputFile, [IO.Compression.CompressionLevel]::Optimal)
          try { $inputFile.CopyTo($gzip) } finally { $gzip.Dispose() }
        } finally { $outputFile.Dispose() }
      } finally { $inputFile.Dispose() }
    }
    $compressed = [IO.File]::OpenRead($gzipPath)
    try {
      $decoder = [IO.Compression.GZipStream]::new($compressed, [IO.Compression.CompressionMode]::Decompress)
      try {
        if ((Get-FileHash -InputStream $decoder -Algorithm SHA256).Hash -ne $hash) {
          throw "Compressed update does not reconstruct $assetName"
        }
      } finally { $decoder.Dispose() }
    } finally { $compressed.Dispose() }
    Write-Host "$assetName.gz | $((Get-Item -LiteralPath $gzipPath).Length) download bytes"
  }
} finally {
  $env:FAMILY_HEALTH_APK_ABI = $previousAbi
}
