[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$artifactsRoot = Join-Path -Path $repoRoot -ChildPath 'artifacts'
$orchestratorPublish = Join-Path -Path $artifactsRoot -ChildPath 'orchestrator'
$installerPublish = Join-Path -Path $artifactsRoot -ChildPath 'installer'
$setupPayloadRoot = Join-Path -Path $repoRoot -ChildPath 'src\Mach1.Setup\Payload'
$bundleStageRoot = Join-Path -Path $artifactsRoot -ChildPath 'payload-stage'
$bundlePayloadRoot = Join-Path -Path $bundleStageRoot -ChildPath 'Payload'
$bundlePayloadMain = Join-Path -Path $bundlePayloadRoot -ChildPath 'Mach1.Orchestrator'
$payloadZipPath = Join-Path -Path $setupPayloadRoot -ChildPath 'payload.zip'

if (Test-Path -LiteralPath $artifactsRoot) {
    Remove-Item -LiteralPath $artifactsRoot -Recurse -Force
}

if (Test-Path -LiteralPath $setupPayloadRoot) {
    Remove-Item -LiteralPath $setupPayloadRoot -Recurse -Force
}

New-Item -Path $orchestratorPublish -ItemType Directory -Force | Out-Null
New-Item -Path $installerPublish -ItemType Directory -Force | Out-Null
New-Item -Path $bundlePayloadMain -ItemType Directory -Force | Out-Null
New-Item -Path $setupPayloadRoot -ItemType Directory -Force | Out-Null

Write-Host 'Publishing Mach1.Orchestrator...' -ForegroundColor Cyan
dotnet publish (Join-Path $repoRoot 'src\Mach1.Orchestrator\Mach1.Orchestrator.csproj') `
  -c $Configuration `
  -r $Runtime `
  --self-contained true `
  /p:PublishSingleFile=true `
  /p:IncludeNativeLibrariesForSelfExtract=true `
  -o $orchestratorPublish

Copy-Item -Path (Join-Path $orchestratorPublish '*') -Destination $bundlePayloadMain -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\WinReEngine.ps1') -Destination (Join-Path $bundlePayloadRoot 'WinReEngine.ps1') -Force

Write-Host 'Creating bundled payload archive...' -ForegroundColor Cyan
if (Test-Path -LiteralPath $payloadZipPath) {
  Remove-Item -LiteralPath $payloadZipPath -Force
}

Compress-Archive -Path (Join-Path $bundleStageRoot '*') -DestinationPath $payloadZipPath -Force

Write-Host 'Publishing Mach1.Setup installer...' -ForegroundColor Cyan
dotnet publish (Join-Path $repoRoot 'src\Mach1.Setup\Mach1.Setup.csproj') `
  -c $Configuration `
  -r $Runtime `
  --self-contained true `
  /p:PublishSingleFile=true `
  /p:IncludeNativeLibrariesForSelfExtract=true `
  -o $installerPublish

Write-Host ''
Write-Host 'Complete installer published:' -ForegroundColor Green
Write-Host (Join-Path $installerPublish 'Mach1.Setup.exe') -ForegroundColor Green
Write-Host 'Bundled payload archive:' -ForegroundColor Green
Write-Host $payloadZipPath -ForegroundColor Green
