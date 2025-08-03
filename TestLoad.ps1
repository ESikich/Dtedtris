# === MINIMAL LOADING TEST ===
Write-Host "Script started at: $(Get-Date)" -ForegroundColor Green

Set-StrictMode -Version Latest
Write-Host "StrictMode set at: $(Get-Date)" -ForegroundColor Yellow

$ErrorActionPreference = 'Stop'
Write-Host "ErrorActionPreference set at: $(Get-Date)" -ForegroundColor Yellow

# Get the script directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "ScriptRoot determined at: $(Get-Date)" -ForegroundColor Yellow

Write-Host "About to load Config..." -ForegroundColor Cyan
. "$ScriptRoot\Config\GameConfig.ps1"
Write-Host "Config loaded at: $(Get-Date)" -ForegroundColor Green

Write-Host "About to load Point..." -ForegroundColor Cyan
. "$ScriptRoot\Core\Point.ps1"
Write-Host "Point loaded at: $(Get-Date)" -ForegroundColor Green

Write-Host "About to load TetrominoData..." -ForegroundColor Cyan
. "$ScriptRoot\Core\TetrominoData.ps1"
Write-Host "TetrominoData loaded at: $(Get-Date)" -ForegroundColor Green

Write-Host "Test complete at: $(Get-Date)" -ForegroundColor Green