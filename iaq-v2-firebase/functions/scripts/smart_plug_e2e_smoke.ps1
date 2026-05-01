param(
    [string]$BaseUrl = $env:CLOUD_FUNCTION_BASE_URL,
    [string]$ApiKey = $env:DEVICE_API_KEY,
    [string]$PlugId = "smoke-plug-$(Get-Date -Format 'yyyyMMddHHmmss')",
    [string]$SensorId = "smoke-sensor-001",
    [string]$TasmotaTopic = "smoke_tasmota",
    [int]$ManualOverrideSeconds = 180,
    [switch]$SkipAck,
    [switch]$RequireWorkerAck,
    [int]$AckTimeoutSeconds = 30,
    [switch]$SkipTraceCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    throw "CLOUD_FUNCTION_BASE_URL or -BaseUrl is required"
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "DEVICE_API_KEY or -ApiKey is required"
}

$base = $BaseUrl.TrimEnd('/')
$headers = @{
    "Content-Type" = "application/json"
    "X-API-Key"    = $ApiKey
}

function Invoke-Api {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][hashtable]$Body,
        [switch]$Silent
    )

    $uri = "$base/$Endpoint"
    $json = $Body | ConvertTo-Json -Depth 10
    if (-not $Silent) {
        Write-Host "[API] POST $Endpoint" -ForegroundColor Cyan
    }
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $json
}

function Get-OptionalString {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    if ($null -eq $Object) {
        return ""
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($PropertyName)) {
            return [string]$Object[$PropertyName]
        }
        return ""
    }

    $prop = $Object.PSObject.Properties[$PropertyName]
    if ($null -ne $prop) {
        return [string]$prop.Value
    }

    return ""
}

if ($RequireWorkerAck -and -not $SkipAck) {
    Write-Host "[INFO] -RequireWorkerAck enabled: synthetic ack is disabled automatically." -ForegroundColor Yellow
    $SkipAck = $true
}

Write-Host "=== Smart Plug E2E Smoke Start ===" -ForegroundColor Green
Write-Host "BaseUrl: $base"
Write-Host "PlugId:  $PlugId"
Write-Host "Sensor:  $SensorId"
Write-Host "Topic:   $TasmotaTopic"

# 1) Register plug metadata
$register = Invoke-Api -Endpoint "registerPlug" -Body @{
    plugId            = $PlugId
    displayName       = "Smoke Test Plug"
    stationId         = $SensorId
    sensorId          = $SensorId
    tasmotaTopic      = $TasmotaTopic
    transportPrimary  = "MQTT"
    transportFallback = "HTTP"
    mode              = "auto"
}
if (-not $register.ok) {
    throw "registerPlug failed"
}

# 2) Send MANUAL command (creates manualOverrideUntil)
$manual = Invoke-Api -Endpoint "commandPlug" -Body @{
    plugId                 = $PlugId
    command                = "ON"
    mode                   = "manual"
    actor                  = "e2e-smoke"
    reason                 = "manual_override_probe"
    manualOverrideSeconds  = $ManualOverrideSeconds
    transportHint          = "MQTT"
}
if (-not $manual.ok) {
    throw "manual commandPlug failed"
}
if (-not $manual.queued) {
    throw "manual command was not queued"
}
$manualRequestId = [string]$manual.requestId
if ([string]::IsNullOrWhiteSpace($manualRequestId)) {
    throw "manual requestId missing"
}

# 3) Send AUTO command while manual override is active
$auto = Invoke-Api -Endpoint "commandPlug" -Body @{
    plugId        = $PlugId
    command       = "OFF"
    mode          = "auto"
    actor         = "e2e-smoke"
    reason        = "auto_policy_probe"
    transportHint = "MQTT"
}
if (-not $auto.ok) {
    throw "auto commandPlug failed"
}

if ($auto.queued -ne $false -or [string]$auto.status -ne "suppressed_manual_override") {
    throw "Expected auto command to be suppressed_manual_override, got queued=$($auto.queued), status=$($auto.status)"
}

Write-Host "[PASS] auto command suppressed by manual override policy" -ForegroundColor Green

# 4) Optional ack to close the manual command lifecycle
if (-not $SkipAck) {
    $ack = Invoke-Api -Endpoint "ackPlugCommand" -Body @{
        requestId        = $manualRequestId
        status           = "acknowledged"
        actualState      = "ON"
        online           = $true
        latencyMs        = 120
        responseTopic    = "stat/$TasmotaTopic/POWER"
        responsePayloadRaw = "ON"
        workerId         = "e2e-smoke-script"
    }

    if (-not $ack.ok) {
        throw "ackPlugCommand failed"
    }
}

# 5) Read plug status
$plug = Invoke-Api -Endpoint "getPlug" -Body @{
    plugId = $PlugId
}
if (-not $plug.ok) {
    throw "getPlug failed"
}

# 5-1) Optional worker ACK verification (actual MQTT loop)
$workerAckVerified = $false
if ($RequireWorkerAck) {
    $deadline = (Get-Date).AddSeconds($AckTimeoutSeconds)
    $lastSeenAckRequestId = ""
    $lastSeenActualState = ""
    while ((Get-Date) -lt $deadline) {
        $poll = Invoke-Api -Endpoint "getPlug" -Body @{ plugId = $PlugId } -Silent
        $actualState = Get-OptionalString -Object $poll.plug -PropertyName "actualState"
        $lastAckRequestId = Get-OptionalString -Object $poll.plug -PropertyName "lastAckRequestId"
        $lastSeenActualState = $actualState
        $lastSeenAckRequestId = $lastAckRequestId
        if ($lastAckRequestId -eq $manualRequestId -and $actualState -eq "ON") {
            $workerAckVerified = $true
            $plug = $poll
            break
        }
        Start-Sleep -Milliseconds 1200
    }

    if (-not $workerAckVerified) {
        throw "Worker ACK verification failed within ${AckTimeoutSeconds}s (lastAckRequestId=$lastSeenAckRequestId, actualState=$lastSeenActualState)"
    }

    Write-Host "[PASS] worker ACK observed (requestId matched + actualState=ON)" -ForegroundColor Green
}

# 6) Read plug list by sensor
$list = Invoke-Api -Endpoint "listPlugs" -Body @{
    sensorId = $SensorId
    limit    = 20
}
if (-not $list.ok) {
    throw "listPlugs failed"
}

# 7) Optional trace chain check (decision/request/response view API)
$traceCount = 0
if (-not $SkipTraceCheck) {
    $trace = Invoke-Api -Endpoint "getPlugControlTrace" -Body @{
        plugId = $PlugId
        limit  = 10
    }
    if (-not $trace.ok) {
        throw "getPlugControlTrace failed"
    }

    $traceItems = @($trace.traces)
    $traceCount = $traceItems.Count
    if ($traceCount -lt 1) {
        throw "getPlugControlTrace returned no trace rows"
    }

    $manualTrace = $traceItems | Where-Object {
        [string]$_.requestId -eq $manualRequestId
    } | Select-Object -First 1

    if ($null -eq $manualTrace) {
        throw "manual requestId not found in trace payload"
    }

    Write-Host "[PASS] getPlugControlTrace returned trace rows and includes manual requestId" -ForegroundColor Green
}

Write-Host "=== Smoke Summary ===" -ForegroundColor Yellow
$summaryAutoPaused = Get-OptionalString -Object $plug.plug -PropertyName "autoPaused"
$summaryManualOverride = Get-OptionalString -Object $plug.plug -PropertyName "manualOverrideUntil"
$summaryActualState = Get-OptionalString -Object $plug.plug -PropertyName "actualState"
$summaryLastAckRequest = Get-OptionalString -Object $plug.plug -PropertyName "lastAckRequestId"
Write-Host "manualRequestId: $manualRequestId"
Write-Host "autoSuppressed:  $($auto.status)"
Write-Host "autoPaused:      $summaryAutoPaused"
Write-Host "manualOverride:  $summaryManualOverride"
Write-Host "workerAck:       $workerAckVerified"
Write-Host "actualState:     $summaryActualState"
Write-Host "lastAckRequest:  $summaryLastAckRequest"
Write-Host "listCount:       $($list.count)"
Write-Host "traceCount:      $traceCount"
Write-Host "=== Smart Plug E2E Smoke End ===" -ForegroundColor Green
