param(
  [Parameter(Mandatory = $true)][string]$Candidate,
  [Parameter(Mandatory = $true)][int]$Build,
  [string]$Avd = "FamilyHealthApi34Upgrade"
)

$ErrorActionPreference = "Stop"
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android/Sdk" }
$adb = Join-Path $sdk "platform-tools/adb.exe"
$emulator = Join-Path $sdk "emulator/emulator.exe"
$package = "com.familyhealth.family_health"
$activity = "$package/.MainActivity"
$assetName = "FamilyHealth-x86_64.apk"
$baselineTag = "v1.0.8+7"
$repo = "Indla26v/Family-health-app"

function Wait-Until([scriptblock]$Condition, [int]$Seconds, [string]$Failure) {
  $watch = [Diagnostics.Stopwatch]::StartNew()
  do {
    if (& $Condition) { return }
    Start-Sleep -Seconds 2
  } while ($watch.Elapsed.TotalSeconds -lt $Seconds)
  throw $Failure
}

function Device([string[]]$Arguments) {
  $output = & $adb -s $serial @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Emulator command failed: $($Arguments -join ' ')" }
  return $output
}

$installedAvds = & $emulator -list-avds
if ($LASTEXITCODE -ne 0 -or $installedAvds -notcontains $Avd) {
  throw "Create a rootable x86-64 AVD named $Avd, or pass -UpgradeTestAvd to release.ps1."
}
$port = 0
foreach ($candidatePort in 5560..5584) {
  if ($candidatePort % 2 -ne 0) { continue }
  try {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $candidatePort)
    $listener.Start()
    $listener.Stop()
    $port = $candidatePort
    break
  } catch [Net.Sockets.SocketException] {}
}
if ($port -eq 0) { throw "No port is available for a disposable emulator." }
$serial = "emulator-$port"
$temp = Join-Path ([IO.Path]::GetTempPath()) ("family-health-upgrade-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp | Out-Null
$process = $null
try {
  $metadata = gh api "repos/$repo/releases/tags/v1.0.8%2B7"
  if ($LASTEXITCODE -ne 0) { throw "Could not read the published $baselineTag release." }
  $asset = ($metadata | ConvertFrom-Json).assets | Where-Object name -eq $assetName
  $localBaseline = Join-Path $PSScriptRoot "../apk/$baselineTag/$assetName"
  if (Test-Path -LiteralPath $localBaseline) {
    $baseline = (Resolve-Path -LiteralPath $localBaseline).Path
  } else {
    gh release download $baselineTag --repo $repo --pattern $assetName --dir $temp
    if ($LASTEXITCODE -ne 0) { throw "Could not download the baseline APK." }
    $baseline = Join-Path $temp $assetName
  }
  $digest = (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($asset.digest -ne "sha256:$digest") { throw "The baseline APK does not match GitHub." }

  $emulatorArgs = @("-avd", ('"' + $Avd + '"'), "-read-only", "-no-snapshot", "-no-window", "-no-audio", "-port", $port)
  $process = Start-Process -FilePath $emulator -PassThru -WindowStyle Hidden -ArgumentList $emulatorArgs -RedirectStandardOutput (Join-Path $temp "emulator.log") -RedirectStandardError (Join-Path $temp "emulator.err")
  Wait-Until {
    if ($process.HasExited) { throw "The disposable emulator exited before booting." }
    (& $adb -s $serial shell getprop sys.boot_completed 2>$null) -eq "1"
  } 150 "The disposable emulator did not boot."
  Device @("root") | Out-Null
  Wait-Until { (& $adb -s $serial shell id -u 2>$null) -eq "0" } 25 "The test AVD must support adb root."
  Device @("shell", "input", "keyevent", "KEYCODE_WAKEUP") | Out-Null
  Device @("shell", "wm", "dismiss-keyguard") | Out-Null
  Device @("shell", "svc", "wifi", "enable") | Out-Null
  Device @("install", "-r", "-d", $baseline) | Write-Host
  if ((Device @("shell", "pm", "clear", $package)) -notmatch "Success") { throw "Could not clear the disposable test app." }

  $prefsDir = "/data/user/0/$package/shared_prefs"
  $prefsFile = "$prefsDir/FlutterSharedPreferences.xml"
  $uid = (Device @("shell", "stat", "-c", "%u", "/data/user/0/$package")).Trim()
  if ($uid -notmatch "^\d+$") { throw "Could not identify the test app UID." }
  $marker = "Release smoke test " + [guid]::NewGuid().ToString("N")
  $profile = @{
    id = "release-smoke-profile"
    name = $marker
    initial = "R"
    age = 40
    bloodGroup = ""
    sex = "female"
    role = "full"
    color = 4278210952L
  }
  $json = @{ members = @($profile) } | ConvertTo-Json -Depth 4 -Compress
  $xml = '<map><string name="flutter.family_health_v2">' + [Security.SecurityElement]::Escape($json) + '</string></map>'
  $seed = Join-Path $temp "prefs.xml"
  [IO.File]::WriteAllText($seed, $xml)
  Device @("push", $seed, "/data/local/tmp/fh-release-prefs.xml") | Out-Null
  Device @("shell", "mkdir -p $prefsDir && cp /data/local/tmp/fh-release-prefs.xml $prefsFile && chown ${uid}:${uid} $prefsDir $prefsFile && chmod 660 $prefsFile && restorecon -RF $prefsDir") | Out-Null
  Device @("logcat", "-c") | Out-Null
  Device @("install", "-r", $candidatePath) | Write-Host
  if (-not (Device @("shell", "dumpsys", "package", $package) | Select-String "versionCode=$Build\b")) {
    throw "The installed APK has the wrong build number."
  }
  Device @("shell", "am", "start", "-W", "-n", $activity) | Write-Host
  Wait-Until {
    [bool](Device @("shell", "dumpsys", "activity", "activities") | Select-String "topResumedActivity=.*$package/")
  } 30 "The signed app did not reach the foreground."
  Device @("shell", "input", "keyevent", "KEYCODE_HOME") | Out-Null
  Wait-Until {
    [bool](Device @("logcat", "-d", "-s", "FamilyHealthUpdate") | Select-String "Background release check completed")
  } 90 "The signed app did not complete its scheduled release check."
  if (-not ((Device @("shell", "cat", $prefsFile)) -join "" -match $marker)) {
    throw "The upgrade did not preserve the seeded Family Health profile."
  }
  if (Device @("logcat", "-d", "-s", "flutter") | Select-String "Could not read saved data, starting fresh") {
    throw "The app could not load the seeded Family Health profile."
  }
  Write-Host "Signed upgrade from $baselineTag to build $Build passed." -ForegroundColor Green
} finally {
  if ($process -and !$process.HasExited) {
    & $adb -s $serial emu kill 2>$null | Out-Null
    if (!$process.WaitForExit(10000)) { Stop-Process -Id $process.Id }
  }
  $resolved = (Resolve-Path -LiteralPath $temp).Path
  $parent = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).Path.TrimEnd('\')
  if ((Split-Path $resolved -Parent).TrimEnd('\') -eq $parent -and
      (Split-Path $resolved -Leaf) -match '^family-health-upgrade-[0-9a-f]{32}$') {
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
      try {
        Remove-Item -LiteralPath $resolved -Recurse -Force
        break
      } catch {
        if ($attempt -eq 4) {
          Write-Warning "The emulator still holds its logs in $resolved."
        } else {
          Start-Sleep -Seconds 1
        }
      }
    }
  }
}
