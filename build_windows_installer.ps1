<#
    Builds the Orderx Windows desktop app and packages it into a single
    installer: build\windows\installer\Orderx_Installer.exe

    Usage:  powershell -ExecutionPolicy Bypass -File .\build_windows_installer.ps1
            powershell -ExecutionPolicy Bypass -File .\build_windows_installer.ps1 -Version 1.0.1 -Clean
#>
param(
    [string]$Version = "1.0.0",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
Set-Location $projectRoot

function Step($message) { Write-Host "`n==> $message" -ForegroundColor Cyan }

# ---------------------------------------------------------------- build ----
if ($Clean) {
    Step "flutter clean"
    flutter clean
}

Step "flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }

Step "flutter build windows --release"
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed." }

$releaseDir = Join-Path $projectRoot "build\windows\x64\runner\Release"
$appExe = Join-Path $releaseDir "Orderx.exe"
if (-not (Test-Path $appExe)) { throw "Build finished but $appExe was not found." }

# ------------------------------------------------- bundle MSVC runtime ----
# Flutter does not copy these, and a clean client PC without the Visual C++
# redistributable cannot start the app without them.
Step "Bundling Visual C++ runtime DLLs"
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found; is Visual Studio installed?" }

$vsPath = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if (-not $vsPath) { throw "No Visual Studio installation with the C++ toolchain was found." }

$crtDir = Get-ChildItem (Join-Path $vsPath "VC\Redist\MSVC") -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Get-ChildItem (Join-Path $_.FullName "x64") -Directory -Filter "Microsoft.VC*.CRT" -ErrorAction SilentlyContinue } |
    Select-Object -First 1
if (-not $crtDir) { throw "Could not locate the Microsoft.VC*.CRT redistributable folder." }

foreach ($dll in @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
    $source = Join-Path $crtDir.FullName $dll
    if (Test-Path $source) {
        Copy-Item $source -Destination $releaseDir -Force
        Write-Host "    bundled $dll"
    } else {
        Write-Warning "    $dll not found in $($crtDir.FullName)"
    }
}

# ------------------------------------------------------ package installer --
Step "Compiling installer with Inno Setup"
$iscc = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "ISCC.exe not found. Install Inno Setup 6." }

& $iscc "/DMyAppVersion=$Version" (Join-Path $projectRoot "windows\installer.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." }

$installer = Join-Path $projectRoot "build\windows\installer\Orderx_Installer.exe"
$sizeMb = [math]::Round((Get-Item $installer).Length / 1MB, 1)
Write-Host "`nInstaller ready: $installer ($sizeMb MB)" -ForegroundColor Green
