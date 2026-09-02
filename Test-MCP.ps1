[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int] $Port = 7331,

    [string] $Token = $env:DELPHI_IDE_MCP_TOKEN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TokenFromCodexConfig {
    $configFile = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (-not (Test-Path -LiteralPath $configFile)) {
        return $null
    }

    $text = Get-Content -LiteralPath $configFile -Raw
    $begin = '# BEGIN CodexMCPIDE (managed by the Delphi IDE package)'
    $end = '# END CodexMCPIDE'
    $beginIndex = $text.IndexOf($begin, [StringComparison]::Ordinal)
    if ($beginIndex -lt 0) {
        return $null
    }
    $endIndex = $text.IndexOf($end, $beginIndex, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) {
        return $null
    }

    $block = $text.Substring($beginIndex, $endIndex - $beginIndex)
    $match = [regex]::Match(
        $block,
        'Authorization\s*=\s*"Bearer\s+([^"\r\n]+)"',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = Get-TokenFromCodexConfig
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    throw 'Kein Bearer-Token angegeben. Verwenden Sie -Token oder DELPHI_IDE_MCP_TOKEN.'
}

$uri = "http://127.0.0.1:$Port/mcp"
$headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = 'application/json, text/event-stream'
    'MCP-Protocol-Version' = '2025-11-25'
}

function Invoke-McpRequest {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Message,

        [switch] $Notification
    )

    $json = $Message | ConvertTo-Json -Depth 20 -Compress
    if ($Notification) {
        $response = Invoke-WebRequest `
            -Uri $uri `
            -Method Post `
            -Headers $headers `
            -ContentType 'application/json; charset=utf-8' `
            -Body $json `
            -UseBasicParsing
        if ($response.StatusCode -notin 200, 202, 204) {
            throw "MCP-Notification fehlgeschlagen: HTTP $($response.StatusCode)"
        }
        return $null
    }

    return Invoke-RestMethod `
        -Uri $uri `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json; charset=utf-8' `
        -Body $json
}

$initialize = Invoke-McpRequest -Message @{
    jsonrpc = '2.0'
    id = 1
    method = 'initialize'
    params = @{
        protocolVersion = '2025-11-25'
        capabilities = @{}
        clientInfo = @{
            name = 'CodexMCPIDE-Test'
            version = '1.0.0'
        }
    }
}

Invoke-McpRequest -Notification -Message @{
    jsonrpc = '2.0'
    method = 'notifications/initialized'
    params = @{}
}

$tools = Invoke-McpRequest -Message @{
    jsonrpc = '2.0'
    id = 2
    method = 'tools/list'
    params = @{}
}

$status = Invoke-McpRequest -Message @{
    jsonrpc = '2.0'
    id = 3
    method = 'tools/call'
    params = @{
        name = 'ide_status'
        arguments = @{}
    }
}

Write-Host "Server: $($initialize.result.serverInfo.title) $($initialize.result.serverInfo.version)"
Write-Host "Protokoll: $($initialize.result.protocolVersion)"
Write-Host "Tools: $($tools.result.tools.Count)"
$tools.result.tools | ForEach-Object { Write-Host "  - $($_.name)" }
Write-Host 'IDE-Status:'
$status.result.structuredContent | ConvertTo-Json -Depth 20
