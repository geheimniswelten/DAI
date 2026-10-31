[CmdletBinding()]
param(
    [ValidateSet('Win32', 'Win64', 'Both')]
    [string]$Platform = 'Both',
    [string]$BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$platforms = if ($Platform -eq 'Both') { @('Win32', 'Win64') } else { @($Platform) }
foreach ($currentPlatform in $platforms) {
    $output = Join-Path $projectRoot "Build\Tests-PortReservations-$currentPlatform"
    $dcu = $output + '-Dcu'
    New-Item -ItemType Directory -Force -Path $output, $dcu | Out-Null
    $compiler = Join-Path $BdsRoot $(if ($currentPlatform -eq 'Win64') { 'bin\dcc64.exe' } else { 'bin\dcc32.exe' })
    $library = Join-Path $BdsRoot "lib\$currentPlatform\release"
    & $compiler '-B' '-Q' '-$B+' '-$Q+' '-$R+' "-E$output" "-N0$dcu" "-U$(Join-Path $projectRoot 'Source');$library" `
        (Join-Path $PSScriptRoot 'Test.PortReservations.dpr')
    if ($LASTEXITCODE -ne 0) { throw "Portverwaltung-Test konnte für $currentPlatform nicht kompiliert werden." }
    $runId = [guid]::NewGuid().ToString('N')
    $testDirectory = Join-Path $output $runId
    $share = Join-Path $testDirectory 'share'
    New-Item -ItemType Directory -Force -Path $testDirectory | Out-Null
    $mutex = "Global\h5uPortReservation.test.$runId"
    $exe = Join-Path $output 'Test.PortReservations.exe'
    $actualDefault = (& $exe '--default-directory').Trim()
    $expectedDefault = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'h5uPortReservation'
    if ($LASTEXITCODE -ne 0 -or $actualDefault -ne $expectedDefault) {
        throw "Der von Windows ermittelte ProgramData-Pfad stimmt nicht: $actualDefault"
    }
    & $exe $share $mutex
    if ($LASTEXITCODE -ne 0) { throw "Portverwaltung-Test fehlgeschlagen für $currentPlatform." }

    # All workers use the production Windows mutex and update the same real user file.
    $workers = @()
    for ($i = 0; $i -lt 12; $i++) {
        $outFile = Join-Path $testDirectory "worker-$i.out"
        $errFile = Join-Path $testDirectory "worker-$i.err"
        $arguments = @('--worker', ('"' + $share + '"'), $mutex, "Test:worker$i")
        $process = Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $workers += [pscustomobject]@{ Process = $process; Output = $outFile; Error = $errFile }
    }
    $ports = @()
    foreach ($worker in $workers) {
        $worker.Process.WaitForExit()
        if ($worker.Process.ExitCode -ne 0) {
            throw "Parallele Portreservierung fehlgeschlagen: $(Get-Content -Raw $worker.Output) $(Get-Content -Raw $worker.Error)"
        }
        $ports += [int](Get-Content -Raw $worker.Output).Trim()
    }
    if (($ports | Sort-Object -Unique).Count -ne 12) { throw 'Parallele Reservierungen haben doppelte Ports ergeben.' }
    $userFiles = @(Get-ChildItem -LiteralPath $share -File -Filter 'S-1-*')
    if ($userFiles.Count -ne 1) { throw 'Es muss genau eine Benutzerdatei bestehen.' }
    $accountSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $fileAcl = Get-Acl -LiteralPath $userFiles[0].FullName
    if ($fileAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $accountSid) {
        throw 'Die Benutzerdatei gehört nicht dem aktuellen Konto.'
    }
    foreach ($ace in (Get-Acl -LiteralPath $share).Access) {
        if ($ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-11' -and
            $ace.AccessControlType -eq 'Allow' -and (([int64]$ace.FileSystemRights -band 0x10040) -ne 0)) {
            throw 'Authentifizierte Benutzer dürfen fremde Dateien nicht über das Verzeichnis löschen.'
        }
    }
    foreach ($ace in $fileAcl.Access) {
        if ($ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-11' -and
            $ace.AccessControlType -eq 'Allow' -and (([int64]$ace.FileSystemRights -band 0xD0006) -ne 0)) {
            throw 'Authentifizierte Benutzer dürfen fremde Benutzerdateien nicht ändern oder löschen.'
        }
    }
    $workerLines = @(Get-Content -LiteralPath $userFiles[0].FullName | Where-Object { $_ -match "`tTest:worker\d+$" })
    if ($workerLines.Count -ne 12) { throw 'Beim parallelen Schreiben sind Reservierungen verloren gegangen.' }

    # A foreign reader can temporarily prevent a Windows rename without holding our mutex.
    $readHandle = [System.IO.File]::Open($userFiles[0].FullName, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $retryOut = Join-Path $testDirectory 'retry.out'
        $retryErr = Join-Path $testDirectory 'retry.err'
        $retryArgs = @('--worker', ('"' + $share + '"'), $mutex, 'Interop:retry')
        $retryWorker = Start-Process -FilePath $exe -ArgumentList $retryArgs -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $retryOut -RedirectStandardError $retryErr
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $temporaryFound = $false
        while ($stopwatch.ElapsedMilliseconds -lt 1000 -and -not $retryWorker.HasExited) {
            if (@(Get-ChildItem -LiteralPath $share -Force -File -Filter '.tmp-*').Count -gt 0) {
                $temporaryFound = $true
                break
            }
            Start-Sleep -Milliseconds 15
        }
        if (-not $temporaryFound) { throw "Temporär gesperrter Ersatz wurde nicht erreicht: $(Get-Content -Raw $retryOut)" }
        Start-Sleep -Milliseconds 100
        if ($retryWorker.HasExited) { throw "Temporäre Dateisperre wurde nicht abgewartet: $(Get-Content -Raw $retryOut)" }
    } finally {
        $readHandle.Dispose()
    }
    if (-not $retryWorker.WaitForExit(5000) -or $retryWorker.ExitCode -ne 0) {
        throw "Ersetzen nach temporärer Dateisperre fehlgeschlagen: $(Get-Content -Raw $retryOut)"
    }

    # A .NET process and Delphi must synchronize through the same named Win32 mutex.
    $dotNetMutex = [System.Threading.Mutex]::new($true, $mutex)
    try {
        $dotNetOut = Join-Path $testDirectory 'dotnet-mutex.out'
        $dotNetErr = Join-Path $testDirectory 'dotnet-mutex.err'
        $dotNetArgs = @('--worker', ('"' + $share + '"'), $mutex, 'Interop:dotnet')
        $dotNetWorker = Start-Process -FilePath $exe -ArgumentList $dotNetArgs -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $dotNetOut -RedirectStandardError $dotNetErr
        if ($dotNetWorker.WaitForExit(400)) { throw 'Delphi hat den gehaltenen .NET-Mutex nicht abgewartet.' }
    } finally {
        $dotNetMutex.ReleaseMutex()
        $dotNetMutex.Dispose()
    }
    if (-not $dotNetWorker.WaitForExit(10000) -or $dotNetWorker.ExitCode -ne 0) {
        throw "Delphi konnte den freigegebenen .NET-Mutex nicht übernehmen: $(Get-Content -Raw $dotNetOut)"
    }

    # An already-bound socket without listen() is absent from the listener table.
    $boundSocket = $null
    for ($attempt = 0; $attempt -lt 16; $attempt++) {
        $candidateSocket = [System.Net.Sockets.Socket]::new([System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Stream, [System.Net.Sockets.ProtocolType]::Tcp)
        $candidateSocket.ExclusiveAddressUse = $true
        $candidateSocket.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, 0))
        $boundPort = $candidateSocket.LocalEndPoint.Port
        if ($boundPort -lt 65535) { $boundSocket = $candidateSocket; break }
        $candidateSocket.Dispose()
    }
    if ($null -eq $boundSocket) { throw 'Kein Testport unterhalb von 65535 verfügbar.' }
    try {
        $absentShare = Join-Path $testDirectory 'standalone-no-share'
        $foundPort = & $exe '--search' $absentShare $mutex $boundPort
        if ($LASTEXITCODE -ne 0 -or [int]$foundPort -le $boundPort) {
            throw 'Die eigenständige Suche hat einen gebundenen Socket ohne Listener nicht übersprungen.'
        }
        if (Test-Path -LiteralPath $absentShare) { throw 'Die reine Suche darf keine Portverwaltung anlegen.' }
    } finally {
        $boundSocket.Dispose()
    }

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        $occupied = $listener.LocalEndpoint.Port
        $result = & $exe '--worker' $share $mutex 'Test:listener' $occupied
        if ($LASTEXITCODE -ne 0 -or [int]$result -eq $occupied) { throw 'Ein aktiver fremder Listener wurde nicht berücksichtigt.' }
    } finally {
        $listener.Stop()
    }
    Write-Host "PASS $currentPlatform`: parallele Reservierung, temporäre Dateisperre, .NET-Mutex und TCP-Ports geprüft"
}

if ($Platform -eq 'Both') {
    # 32-bit and 64-bit clients share exactly the same global mutex and user file.
    $mixedWorkers = @()
    for ($i = 0; $i -lt 8; $i++) {
        $arch = if ($i % 2 -eq 0) { 'Win32' } else { 'Win64' }
        $mixedExe = Join-Path $projectRoot "Build\Tests-PortReservations-$arch\Test.PortReservations.exe"
        $outFile = Join-Path $testDirectory "mixed-$i.out"
        $errFile = Join-Path $testDirectory "mixed-$i.err"
        $workerArgs = @('--worker', ('"' + $share + '"'), $mutex, "Mixed:worker$i")
        $process = Start-Process -FilePath $mixedExe -ArgumentList $workerArgs -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $mixedWorkers += [pscustomobject]@{ Process = $process; Output = $outFile; Error = $errFile }
    }
    $mixedPorts = @()
    foreach ($worker in $mixedWorkers) {
        $worker.Process.WaitForExit()
        if ($worker.Process.ExitCode -ne 0) { throw "Win32/Win64-Reservierung fehlgeschlagen: $(Get-Content -Raw $worker.Output)" }
        $mixedPorts += [int](Get-Content -Raw $worker.Output).Trim()
    }
    if (($mixedPorts | Sort-Object -Unique).Count -ne 8) { throw 'Win32/Win64 haben doppelte Ports reserviert.' }
    $mixedLines = @(Get-Content -LiteralPath $userFiles[0].FullName | Where-Object { $_ -match "`tMixed:worker\d+$" })
    if ($mixedLines.Count -ne 8) { throw 'Win32/Win64-Reservierungen sind verloren gegangen.' }
    Write-Host 'PASS: 8 parallele Win32- und Win64-Prozesse teilen dieselbe Sperre'
}
