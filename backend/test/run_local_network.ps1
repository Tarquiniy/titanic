param(
  [string]$BaseUrl = "http://192.168.10.10:8080",
  [int]$Concurrency = 200,
  [int]$DurationSeconds = 90,
  [double]$TimeoutSeconds = 5.0,
  [int]$RampUpSeconds = 0,
  [string]$Endpoints = "/api/health:8,/:2",
  [string]$Method = "GET"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Resolve-Path (Join-Path $scriptDir "..")

Push-Location $backendDir
try {
  poetry run python test/load_test.py `
    --base-url $BaseUrl `
    --concurrency $Concurrency `
    --duration $DurationSeconds `
    --timeout $TimeoutSeconds `
    --ramp-up $RampUpSeconds `
    --endpoints $Endpoints `
    --method $Method
}
finally {
  Pop-Location
}
