$ErrorActionPreference = "Stop"

function Write-Step($message) {
  Write-Host ""
  Write-Host "== $message ==" -ForegroundColor Cyan
}

function Pick-Port {
  Write-Step "USB 센서 포트 확인"
  $ports = Get-CimInstance Win32_SerialPort |
    Where-Object {
      $_.DeviceID -match "^COM" -and
      ($_.PNPDeviceID -match "VID_303A" -or $_.Name -match "USB|CP210|CH340|ESP")
    } |
    Select-Object DeviceID, Name, PNPDeviceID

  if (-not $ports) {
    $manual = Read-Host "USB 센서 포트를 자동으로 찾지 못했습니다. 예: COM5"
    if ([string]::IsNullOrWhiteSpace($manual)) {
      throw "포트가 선택되지 않았습니다."
    }
    return $manual.Trim()
  }

  $list = @($ports)
  for ($i = 0; $i -lt $list.Count; $i++) {
    Write-Host "[$($i + 1)] $($list[$i].DeviceID)  $($list[$i].Name)"
  }

  if ($list.Count -eq 1) {
    $confirm = Read-Host "$($list[0].DeviceID)에 설치할까요? [Y/n]"
    if ($confirm -match "^[nN]") {
      throw "사용자가 설치를 취소했습니다."
    }
    return $list[0].DeviceID
  }

  $choice = Read-Host "설치할 포트 번호를 입력하세요"
  $index = [int]$choice - 1
  if ($index -lt 0 -or $index -ge $list.Count) {
    throw "잘못된 포트 번호입니다."
  }
  return $list[$index].DeviceID
}

function Find-Command($name) {
  return Get-Command $name -ErrorAction SilentlyContinue
}

Write-Host "CleanAir AirGradient 펌웨어 설치 도구" -ForegroundColor Green
Write-Host "센서를 USB로 연결한 뒤 안내에 따라 진행하세요."

$port = Pick-Port

Write-Step "빌드된 바이너리로 업로드"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$firmwareDir = $scriptDir

if (-not $firmwareDir) {
  throw "firmware.bin을 찾지 못했습니다. 설치 폴더에 펌웨어 파일이 필요합니다."
}

$python = Find-Command "python"
if (-not $python) {
  $python = Find-Command "py"
}
if (-not $python) {
  throw "Python을 찾지 못했습니다. PlatformIO를 설치하거나 Python/esptool 환경을 준비해 주세요."
}

$bootloader = Join-Path $firmwareDir "bootloader.bin"
$partitions = Join-Path $firmwareDir "partitions.bin"
$bootApp0 = Join-Path $firmwareDir "boot_app0.bin"
$firmware = Join-Path $firmwareDir "firmware.bin"

if (-not (Test-Path $bootloader) -or -not (Test-Path $partitions) -or -not (Test-Path $bootApp0)) {
  throw "bootloader.bin, partitions.bin 또는 boot_app0.bin이 없습니다. PlatformIO 빌드 산출물이 필요합니다."
}

& $python.Source -m esptool --chip auto --port $port --baud 460800 write_flash -z 0x0 $bootloader 0x8000 $partitions 0xe000 $bootApp0 0x10000 $firmware
if ($LASTEXITCODE -ne 0) {
  throw "esptool 업로드에 실패했습니다."
}

Write-Host ""
Write-Host "설치 완료. 센서가 재부팅됩니다." -ForegroundColor Green
