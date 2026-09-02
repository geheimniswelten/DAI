[CmdletBinding()]
param(
    [int]$Port = 7331,
    [string]$Token = $env:DELPHI_IDE_MCP_TOKEN
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-DAITokenFromCodexConfig {
    $configFile = Join-Path $HOME '.codex\config.toml'
    if (-not (Test-Path -LiteralPath $configFile)) {
        return $null
    }

    $content = Get-Content -LiteralPath $configFile -Raw
    $block = [regex]::Match(
        $content,
        '(?s)# >>> DAI managed >>>.*?Authorization\s*=\s*"Bearer\s+([^"]+)".*?# <<< DAI managed <<<'
    )
    if ($block.Success) {
        return $block.Groups[1].Value
    }

    return $null
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = Get-DAITokenFromCodexConfig
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    throw 'Kein Bearer-Token angegeben und kein verwalteter DAI-Block in ~/.codex/config.toml gefunden.'
}

$uri = "http://127.0.0.1:$Port/mcp"
$headers = @{
    Authorization = "Bearer $Token"
    Accept        = 'application/json'
    'Content-Type'= 'application/json'
}

function Invoke-DAIMcp {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Payload,

        [string]$SessionId
    )

    $requestHeaders = @{} + $headers
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $requestHeaders['Mcp-Session-Id'] = $SessionId
    }

    $response = Invoke-WebRequest `
        -Uri $uri `
        -Method Post `
        -Headers $requestHeaders `
        -Body ($Payload | ConvertTo-Json -Depth 20 -Compress)

    [pscustomobject]@{
        Body      = if ($response.Content) { $response.Content | ConvertFrom-Json } else { $null }
        SessionId = $response.Headers['Mcp-Session-Id']
    }
}

$initialize = Invoke-DAIMcp -Payload @{
    jsonrpc = '2.0'
    id      = 1
    method  = 'initialize'
    params  = @{
        protocolVersion = '2025-06-18'
        capabilities    = @{}
        clientInfo      = @{
            name    = 'DAI-Test'
            version = '1.1.2'
        }
    }
}
$sessionId = $initialize.SessionId
$initialize.Body | ConvertTo-Json -Depth 20

$null = Invoke-DAIMcp -SessionId $sessionId -Payload @{
    jsonrpc = '2.0'
    method  = 'notifications/initialized'
    params  = @{}
}

$tools = Invoke-DAIMcp -SessionId $sessionId -Payload @{
    jsonrpc = '2.0'
    id      = 2
    method  = 'tools/list'
    params  = @{}
}
$tools.Body | ConvertTo-Json -Depth 20

$status = Invoke-DAIMcp -SessionId $sessionId -Payload @{
    jsonrpc = '2.0'
    id      = 3
    method  = 'tools/call'
    params  = @{
        name      = 'ide_status'
        arguments = @{}
        _meta     = @{
            threadId = 'dai-test-thread'
        }
    }
}
$status.Body | ConvertTo-Json -Depth 20
