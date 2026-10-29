[CmdletBinding()]
param(
    [switch]$Execute,
    [ValidateSet('Baseline', 'Stress')]
    [string]$Suite = 'Baseline',
    [switch]$DeferredSave,
    [ValidateRange(1024, 65535)]
    [int]$Port = 7331,
    [string]$Token
)

# Native regression test; review before execution. Creates six temporary PAS files,
# opens only their tabs and makes three hash-guarded writes per file. DeferredSave
# keeps all three writes unsaved, then saves exactly that scratch file with a no-op.
# It never adds projects, changes registrations, starts/stops the IDE, invokes Undo,
# edits user files, discards dirty buffers, clicks dialogs or deletes evidence.
# Without -Execute, it performs no HTTP, registry or filesystem operation.
if (-not $Execute) {
    Write-Output 'Not executed. Review this script, then pass -Execute only after IDE/scratch-test authorization.'
    return
}
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$probeId = [guid]::NewGuid().ToString('N')
$scratchDirectory = Join-Path ([IO.Path]::GetTempPath()) ("DAI-EditorEof-Live-$probeId")
$script:eofProbeRequestId = 0
$script:eofProbeLastTool = ''
$script:eofProbeHttpStatus = $null
$script:eofProbeFailureReason = ''
$script:eofCheckCount = 0
$testFailed = $false
$cleanupFailed = $false
$records = [Collections.Generic.List[object]]::new()
$requestMeta = @{
    'io.modelcontextprotocol/protocolVersion' = '2026-07-28'
    'io.modelcontextprotocol/clientCapabilities' = @{}
    'io.modelcontextprotocol/clientInfo' = @{ name = 'DAI-EditorEof-Live-Probe'; version = '1' }
    threadId = "dai-editor-eof-$probeId"
}

function Write-ProbeEvent([hashtable]$Event) {
    Write-Output ($Event | ConvertTo-Json -Depth 6 -Compress)
}
function Assert-ProbeCondition([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        $script:eofProbeFailureReason = $Message
        throw 'Native editor EOF regression assertion failed.'
    }
    $script:eofCheckCount++
}
function Invoke-ProbeTool([string]$Name, [hashtable]$Arguments) {
    if ($Name -notin @('ide_status', 'open_files_list', 'file_open', 'file_read', 'file_write', 'file_close')) {
        throw 'Unexpected tool: probe aborted.'
    }
    $script:eofProbeLastTool = $Name
    $script:eofProbeHttpStatus = $null
    $script:eofProbeRequestId++
    $headers = @{
        Authorization = "Bearer $Token"
        Accept = 'application/json'
        'Content-Type' = 'application/json'
        'Mcp-Method' = 'tools/call'
        'Mcp-Name' = $Name
        'MCP-Protocol-Version' = '2026-07-28'
    }
    $payload = @{
        jsonrpc = '2.0'
        id = $script:eofProbeRequestId
        method = 'tools/call'
        params = @{ name = $Name; arguments = $Arguments; _meta = $requestMeta }
    }
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/mcp" -Method Post -Headers $headers `
            -Body ([Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 10 -Compress))) -TimeoutSec 15
    } catch {
        if ($_.Exception.PSObject.Properties['Response'] -and $null -ne $_.Exception.Response) {
            $script:eofProbeHttpStatus = [int]$_.Exception.Response.StatusCode
        }
        throw 'HTTP request failed; probe does not retry with other credentials.'
    }
    $body = $response.Content | ConvertFrom-Json
    if ($body.PSObject.Properties['error']) { throw 'MCP protocol error; probe aborted.' }
    $result = $body.result
    if ($result.PSObject.Properties['isError'] -and $result.isError) {
        throw 'DAI tool reported failure; no further scratch edits will be attempted.'
    }
    if ($result.PSObject.Properties['structuredContent']) { return $result.structuredContent }
    return ($result.content[0].text | ConvertFrom-Json)
}
function Get-ProbeLoadedPaths($Result) {
    if (-not $Result.PSObject.Properties['files'] -or $Result.files -isnot [Array]) {
        throw 'The loaded-file list is not a recognized files array.'
    }
    foreach ($path in $Result.files) {
        if ($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path)) {
            throw 'The loaded-file list contains an unrecognized entry.'
        }
        Write-Output $path
    }
}
function Read-ProbeEditor([string]$Path) {
    $snapshot = Invoke-ProbeTool 'file_read' @{ file = $Path; interfaces_only = $false; maximum_characters = 0 }
    if ($snapshot.source -ne 'editor_buffer' -or -not $snapshot.content_complete -or $snapshot.truncated) {
        throw 'A complete native editor snapshot is required.'
    }
    return $snapshot
}
function Get-ProbeHash([byte[]]$Bytes) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
function Get-ProbeEnd([string]$Text) {
    $ending = [regex]::Match($Text, '(?:\r\n|\r|\n)*\z').Value
    return @{
        utf8_bytes = [Text.Encoding]::UTF8.GetByteCount($Text)
        crlf = [regex]::Matches($ending, '\r\n').Count
        bare_lf = [regex]::Matches($ending, '(?<!\r)\n').Count
        bare_cr = [regex]::Matches($ending, '\r(?!\n)').Count
    }
}
function Get-ProbeComparableBody([string]$Text) {
    # Interior LF/CRLF conversion can be a normal IDE setting; report EOF separately.
    return ([regex]::Replace($Text, '(?:\r\n|\r|\n)+\z', '')).Replace("`r`n", "`n").Replace("`r", "`n")
}
function Assert-ProbeState($Record, [string]$Requested, [bool]$Saved) {
    $requestedEnding = [regex]::Match($Requested, '(?:\r\n|\r|\n)*\z').Value
    $readerEnding = [regex]::Match($Record.LastReaderText, '(?:\r\n|\r|\n)*\z').Value
    $diskEnding = [regex]::Match($Record.LastDiskText, '(?:\r\n|\r|\n)*\z').Value
    Assert-ProbeCondition ($requestedEnding -ceq $Record.InitialEnding) 'The request changed the intended fixture EOF.'
    Assert-ProbeCondition ($readerEnding -ceq $requestedEnding) 'The reader gained, lost or changed a requested final line break.'
    Assert-ProbeCondition ((Get-ProbeComparableBody $Record.LastReaderText) -ceq (Get-ProbeComparableBody $Requested)) `
        'The native writer changed non-EOF source content.'
    if ($Saved) {
        Assert-ProbeCondition ($diskEnding -ceq $requestedEnding) 'The saved file gained, lost or changed a requested final line break.'
        Assert-ProbeCondition ($Record.LastReaderText -ceq $Record.LastDiskText) 'Saved disk text differs from the native reader.'
    } else {
        Assert-ProbeCondition ($Record.LastDiskHash -ceq $Record.InitialDiskHash) 'save=false changed the physical file.'
        Assert-ProbeCondition ($diskEnding -ceq $Record.InitialEnding) 'save=false changed the original disk EOF.'
    }
}
function Read-ProbeDisk([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $stream = [IO.MemoryStream]::new($bytes, $false)
    # Delphi PAS defaults to the Windows ANSI code page; BOM overrides it.
    $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::GetEncoding((Get-Culture).TextInfo.ANSICodePage), $true)
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    return [pscustomobject]@{ Text = $text; ByteHash = (Get-ProbeHash $bytes) }
}
function New-ProbeStressBody([string]$UnitName, [string]$Variant, [int]$Step) {
    $lineBreak = if ($Variant -eq 'large_utf8_lf_fallback') { "`n" } else { "`r`n" }
    $phase = if ($Variant -eq 'large_utf8_crlf_last_line') { 0 } else { $Step }
    $unitToken = if ($phase % 2) { 'UNIT ' } else { 'unit ' }
    $ending = if ($Step % 2) { 'END .' } else { 'end.' }
    $sample = if ($Variant -eq 'large_ansi_crlf_fallback') { 'Grüße ÄÖÜß' } else { 'Grüße 漢字 😊' }
    $builder = [Text.StringBuilder]::new(500000)
    $null = $builder.Append($unitToken).Append($UnitName).Append(';').Append($lineBreak).Append($lineBreak)
    $null = $builder.Append('interface').Append($lineBreak).Append($lineBreak)
    $null = $builder.Append('implementation').Append($lineBreak).Append($lineBreak)
    for ($row = 1; $row -le 5000; $row++) {
        $null = $builder.AppendFormat('// row {0:D6} phase {1:D2} ', $row, $phase).Append($sample)
        $null = $builder.Append(' abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuv').Append($lineBreak)
    }
    $null = $builder.Append($lineBreak).Append($ending)
    return $builder.ToString()
}
function Add-ProbeObservation($Record, [int]$Step, [string]$Phase, $Snapshot, [string]$RequestedText, [string]$WriteHash) {
    $disk = Read-ProbeDisk $Record.Path
    $Record.LastDiskHash = $disk.ByteHash
    $Record.LastReaderHash = $Snapshot.sha256
    $Record.LastReaderText = [string]$Snapshot.content
    $Record.LastDiskText = [string]$disk.Text
    $event = @{
        event = 'observation'
        file = $Record.Path
        series = $Record.Series
        suite = $Suite
        variant = $Record.Variant
        deferred_save = [bool]$DeferredSave
        initial_line_breaks = $Record.InitialBreaks
        step = $Step
        phase = $Phase
        reader = Get-ProbeEnd $Snapshot.content
        disk = Get-ProbeEnd $disk.Text
        reader_sha256 = $Snapshot.sha256
        disk_bytes_sha256 = $disk.ByteHash
        reader_equals_disk = $Snapshot.content -ceq $disk.Text
        disk_equals_reader_plus_crlf = $disk.Text -ceq ($Snapshot.content + "`r`n")
        reader_equals_disk_plus_crlf = $Snapshot.content -ceq ($disk.Text + "`r`n")
    }
    if ($null -ne $RequestedText) { $event.requested = Get-ProbeEnd $RequestedText }
    if ($WriteHash) { $event.write_response_sha256 = $WriteHash }
    Write-ProbeEvent $event
}

try {
    if ([string]::IsNullOrWhiteSpace($Token)) {
        $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $connection = $registry.OpenSubKey('Software\DelphiAI\DAI\Connection', $false)
            if ($null -eq $connection) { throw 'Shared connection settings are unavailable.' }
            try {
                $Token = [string]$connection.GetValue('Token', '')
                if (-not $PSBoundParameters.ContainsKey('Port')) { $Port = [int]$connection.GetValue('Port', $Port) }
            } finally { $connection.Dispose() }
        } finally { $registry.Dispose() }
    }
    if ([string]::IsNullOrWhiteSpace($Token)) { throw 'Shared authentication token is unavailable.' }
    $null = Invoke-ProbeTool 'ide_status' @{}
    $null = Get-ProbeLoadedPaths (Invoke-ProbeTool 'open_files_list' @{})
    $null = [IO.Directory]::CreateDirectory($scratchDirectory)
    Write-ProbeEvent @{ event = 'scratch_created'; directory = $scratchDirectory }
    $fileIndex = 0
    foreach ($series in @('preserve_reader_eof', 'preserve_initial_disk_eof')) {
        $cases = if ($Suite -eq 'Baseline') {
            @(0, 1, 2) | ForEach-Object { [pscustomobject]@{ Breaks = $_; Variant = 'small_const' } }
        } else {
            @('large_ansi_crlf_fallback', 'large_utf8_lf_fallback', 'large_utf8_crlf_last_line') |
                ForEach-Object { [pscustomobject]@{ Breaks = 2; Variant = $_ } }
        }
        foreach ($case in $cases) {
            $initialBreaks = $case.Breaks
            $lineBreak = if ($case.Variant -eq 'large_utf8_lf_fallback') { "`n" } else { "`r`n" }
            $unitName = "TestEditorEOFX$fileIndex"
            $fileIndex++
            $path = Join-Path $scratchDirectory ($unitName + '.pas')
            $initialBody = if ($case.Variant -eq 'small_const') {
                "unit $unitName;`r`n`r`ninterface`r`n`r`nconst ProbeValue = 0;`r`n`r`nimplementation`r`n`r`nend."
            } else { New-ProbeStressBody $unitName $case.Variant 0 }
            $initialText = $initialBody + ($lineBreak * $initialBreaks)
            $record = [pscustomobject]@{
                Path = $path; Series = $series; InitialBreaks = $initialBreaks; Variant = $case.Variant
                InitialEnding = ($lineBreak * $initialBreaks); InitialDiskHash = ''
                Opened = $false; Completed = $false; ConfirmedSaved = $false
                LastDiskHash = ''; LastReaderHash = ''; LastReaderText = ''; LastDiskText = ''
            }
            $records.Add($record)
            $diskEncoding = if ($case.Variant -eq 'large_ansi_crlf_fallback') {
                [Text.Encoding]::GetEncoding((Get-Culture).TextInfo.ANSICodePage)
            } else { [Text.UTF8Encoding]::new($true) }
            [IO.File]::WriteAllText($path, $initialText, $diskEncoding)
            $record.InitialDiskHash = Get-ProbeHash ([IO.File]::ReadAllBytes($path))
            # Mark a possible open before the HTTP call: a timeout does not prove failure.
            $record.Opened = $true
            $null = Invoke-ProbeTool 'file_open' @{ file = $path }
            $snapshot = Read-ProbeEditor $path
            Add-ProbeObservation $record 0 'after_open' $snapshot $null ''
            Assert-ProbeState $record $initialText $true
            for ($step = 1; $step -le 3; $step++) {
                $snapshot = Read-ProbeEditor $path
                Assert-ProbeCondition ($snapshot.sha256 -ceq $record.LastReaderHash) 'Scratch content changed before its next write.'
                Assert-ProbeCondition (([regex]::Match($snapshot.content, '(?:\r\n|\r|\n)*\z').Value) -ceq $record.InitialEnding) `
                    'The current snapshot no longer has the intended fixture EOF.'
                if ($case.Variant -eq 'small_const') {
                    $oldAnchor = 'const ProbeValue = ' + ($step - 1) + ';'
                    if ([regex]::Matches($snapshot.content, [regex]::Escape($oldAnchor)).Count -ne 1) {
                        throw 'Unexpected scratch content; no replacement will be attempted.'
                    }
                    $requested = $snapshot.content.Replace($oldAnchor, ('const ProbeValue = ' + $step + ';'))
                } else {
                    $readerEnding = [regex]::Match($snapshot.content, '(?:\r\n|\r|\n)*\z').Value
                    $requested = (New-ProbeStressBody $unitName $case.Variant $step) + $readerEnding
                }
                if ($series -eq 'preserve_initial_disk_eof') {
                    $requested = [regex]::Replace($requested, '(?:\r\n|\r|\n)+\z', '') + ($lineBreak * $initialBreaks)
                }
                $record.ConfirmedSaved = $false
                $saveNow = -not [bool]$DeferredSave
                $written = Invoke-ProbeTool 'file_write' @{
                    file = $path; content = $requested; expected_sha256 = $snapshot.sha256; save = $saveNow
                }
                Assert-ProbeCondition ($written.saved -is [bool] -and $written.saved -eq $saveNow -and $written.target -eq 'editor_buffer') `
                    'The write response did not confirm the requested native editor/save mode.'
                $snapshot = Read-ProbeEditor $path
                $phase = if ($saveNow) { 'after_saved_write' } else { 'after_unsaved_write' }
                Add-ProbeObservation $record $step $phase $snapshot $requested $written.sha256
                Assert-ProbeCondition ($snapshot.sha256 -ceq $written.sha256) 'Write-response hash differs from complete readback.'
                Assert-ProbeState $record $requested $saveNow
                $record.ConfirmedSaved = $saveNow
            }
            if ($DeferredSave) {
                $snapshot = Read-ProbeEditor $path
                Assert-ProbeCondition ($snapshot.sha256 -ceq $record.LastReaderHash) 'Scratch content changed before deferred save.'
                $requested = [string]$snapshot.content
                Assert-ProbeCondition (([regex]::Match($requested, '(?:\r\n|\r|\n)*\z').Value) -ceq $record.InitialEnding) `
                    'The deferred-save snapshot no longer has the intended fixture EOF.'
                $written = Invoke-ProbeTool 'file_write' @{
                    file = $path; content = $requested; expected_sha256 = $snapshot.sha256; save = $true
                }
                Assert-ProbeCondition ($written.saved -is [bool] -and $written.saved -and $written.target -eq 'editor_buffer') `
                    'The deferred no-op save was not confirmed.'
                $snapshot = Read-ProbeEditor $path
                Add-ProbeObservation $record 4 'after_deferred_noop_save' $snapshot $requested $written.sha256
                Assert-ProbeCondition ($snapshot.sha256 -ceq $written.sha256) 'Deferred-save response hash differs from readback.'
                Assert-ProbeCondition ($snapshot.content -ceq $requested) 'The deferred no-op save changed the editor text.'
                Assert-ProbeState $record $requested $true
                $record.ConfirmedSaved = $true
            }
            $record.Completed = $true
        }
    }
} catch {
    $testFailed = $true
    Write-ProbeEvent @{
        event = 'probe_stopped'
        last_tool = $script:eofProbeLastTool
        http_status = $script:eofProbeHttpStatus
        assertion = $script:eofProbeFailureReason
        reason = 'Request or scratch validation failed. No credential retry, forced close, dialog action or evidence deletion.'
    }
} finally {
    foreach ($record in $records) {
        if (-not $record.Opened -or -not $record.Completed -or -not $record.ConfirmedSaved) {
            Write-ProbeEvent @{ event = 'scratch_retained'; file = $record.Path; editor_may_be_open = $record.Opened }
            continue
        }
        try {
            $current = Read-ProbeEditor $record.Path
            $disk = Read-ProbeDisk $record.Path
            if ($current.sha256 -cne $record.LastReaderHash -or $disk.ByteHash -cne $record.LastDiskHash) {
                throw 'Scratch contents changed after the confirmed save.'
            }
            $closed = Invoke-ProbeTool 'file_close' @{ file = $record.Path }
            if (-not $closed.PSObject.Properties['closed'] -or $closed.closed -isnot [bool] -or -not $closed.closed) {
                throw 'The native scratch close was not confirmed.'
            }
            $loaded = @(Get-ProbeLoadedPaths (Invoke-ProbeTool 'open_files_list' @{}))
            if ($record.Path -in $loaded) { throw 'Scratch editor is still loaded.' }
            Write-ProbeEvent @{ event = 'scratch_tab_closed'; file = $record.Path; disk_evidence_retained = $true }
        } catch {
            $cleanupFailed = $true
            Write-ProbeEvent @{ event = 'scratch_retained'; file = $record.Path; editor_may_be_open = $true }
        }
    }
    Write-ProbeEvent @{ event = 'probe_finished'; directory = $scratchDirectory; created_files = $records.Count; disk_evidence_retained = $true }
}
if ($testFailed -or $cleanupFailed) {
    throw 'Native editor EOF regression failed; inspect the JSON events. Scratch evidence was retained.'
}
Write-ProbeEvent @{
    event = 'test_passed'; suite = $Suite; deferred_save = [bool]$DeferredSave
    cases = $records.Count; assertions = $script:eofCheckCount; disk_evidence_retained = $true
}
