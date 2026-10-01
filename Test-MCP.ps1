[CmdletBinding()]
param(
    [int]$Port = 7331,
    [string]$Token = $env:DELPHI_IDE_MCP_TOKEN,

    [ValidateSet('Legacy', 'Modern')]
    [string]$Mode = 'Legacy'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-DAITokenFromCodexConfig {
    $codexDirectory = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $configFile = Join-Path $codexDirectory 'config.toml'
    if (-not (Test-Path -LiteralPath $configFile)) {
        return $null
    }

    $content = Get-Content -LiteralPath $configFile -Raw
    $block = [regex]::Match(
        $content,
        '(?s)# >>> DAI managed >>>.*?Authorization\s*=\s*("Bearer\s+(?:\\.|[^"\\])+").*?# <<< DAI managed <<<'
    )
    if ($block.Success) {
        $authorization = $block.Groups[1].Value | ConvertFrom-Json
        return $authorization.Substring(7)
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
    if ($Mode -eq 'Modern') {
        $requestHeaders['Mcp-Method'] = $Payload.method
        $requestHeaders['MCP-Protocol-Version'] = '2026-07-28'
        if ($Payload.ContainsKey('params') -and $Payload.params.ContainsKey('name')) {
            $requestHeaders['Mcp-Name'] = $Payload.params.name
        }
        if (-not $Payload.ContainsKey('params')) { $Payload.params = @{} }
        if (-not $Payload.params.ContainsKey('_meta')) { $Payload.params._meta = @{} }
        $Payload.params._meta['io.modelcontextprotocol/protocolVersion'] = '2026-07-28'
        $Payload.params._meta['io.modelcontextprotocol/clientCapabilities'] = @{}
        $Payload.params._meta['io.modelcontextprotocol/clientInfo'] = @{ name = 'DAI-Test'; version = '1.2.3' }
    } else {
        $requestHeaders['MCP-Protocol-Version'] = '2025-06-18'
    }
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

if ($Mode -eq 'Legacy') {
    $initialize = Invoke-DAIMcp -Payload @{
    jsonrpc = '2.0'
    id      = 1
    method  = 'initialize'
    params  = @{
        protocolVersion = '2025-06-18'
        capabilities    = @{}
        clientInfo      = @{
            name    = 'DAI-Test'
            version = '1.2.3'
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
} else {
    $sessionId = $null
    $discover = Invoke-DAIMcp -Payload @{ jsonrpc = '2.0'; id = 1; method = 'server/discover'; params = @{} }
    $discover.Body | ConvertTo-Json -Depth 20
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
