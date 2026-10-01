#Requires -Version 5.1
#Requires -RunAsAdministrator

# =============================================================================
# SIGMA PERFORMANCE v0.8
# v0.7 review fixes:
#  [P1] CompensationSucceeded / CompensationFailed are separate states
#  [P2] ApplySucceeded emitted immediately after mutation, before verify
#  [P3] RecoveryRequired transaction state; batch halts on compensation failure
#  [P4] Idle gate: counter failure != 0% load
#  [3]  Transaction IDs include milliseconds + random suffix
#  [4]  Named mutex prevents concurrent Sigma sessions
#  [6]  Manifest with journal + metadata hashes
#  [7]  Idle gate known-state tracked
#  [9]  WinRE registry described as heuristic, not authoritative
#  [10] WinReConfigured != Enabled
#  [11] WHEA classification labelled heuristic
#  [12] WHEA unclassified bucket
#  [13] AlreadyRolledBack recognized
#  [14] Rollback candidates: Applied (CompensationSucceeded=false, RolledBack=false)
#  [15] RecoveryRequired at transaction level
#  [16] SigmaCriticalMutationException halts batch
#  [19] DiskSpd preconditioning separated from measurement
#  [20] Idle gate metadata saved to benchmark
#  [21] Environment guards in comparison
#  [22] CPUComparisonValid / DiskComparisonValid split
#  [23] SHA objects disposed in finally
# =============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
Set-StrictMode -Version 2.0

$script:SigmaVersion       = '0.8.0'
$script:BenchmarkSchemaVer = 4
$script:TransactionSchema  = 4
$script:RulesVersion       = 1

# -----------------------------------------------------------------------------
# SECTION 0 - Header
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "========== SIGMA PERFORMANCES v$($script:SigmaVersion) ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[INFO] Diagnostic scan + transactional optimization (verified, reversible)." -ForegroundColor Cyan
Write-Host "[INFO] Verification failure without compensation halts the batch." -ForegroundColor Cyan
Write-Host ""
Write-Host "[WARNING] Create a System Restore point before proceeding." -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "Proceed? (Y/N)"
if ($confirm -notin 'Y','y') { Write-Host "Exiting." -ForegroundColor Cyan; exit 0 }

# -----------------------------------------------------------------------------
# SECTION 1 - Infrastructure + singleton mutex (Fix #4)
# -----------------------------------------------------------------------------

$script:SigmaRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:SigmaData = Join-Path $script:SigmaRoot 'SigmaData'
$script:SigmaLog  = Join-Path $script:SigmaData 'Logs'
$script:SigmaTx   = Join-Path $script:SigmaData 'Transactions'
$script:SigmaPend = Join-Path $script:SigmaData 'Pending'
$script:SigmaBm   = Join-Path $script:SigmaData 'Benchmarks'
$script:SigmaRpt  = Join-Path $script:SigmaData 'Reports'
$script:ErrorLog  = Join-Path $env:TEMP 'sigma_errors.log'

foreach ($d in @($script:SigmaData,$script:SigmaLog,$script:SigmaTx,$script:SigmaPend,$script:SigmaBm,$script:SigmaRpt)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
if (Test-Path $script:ErrorLog) { Remove-Item $script:ErrorLog -Force -EA SilentlyContinue }

# Fix #4: process-wide mutex (only one Sigma mutation engine at a time)
$script:SigmaMutex = $null
function Acquire-SigMutex {
    try {
        $m = New-Object System.Threading.Mutex($false, 'Global\SigmaPerformanceMutationEngine')
        if (-not $m.WaitOne(0)) {
            $m.Dispose()
            throw "Another Sigma optimization session is already active on this machine."
        }
        $script:SigmaMutex = $m
    } catch [System.Threading.AbandonedMutexException] {
        # Previous process died holding it; we now own it.
        $script:SigmaMutex = $m
    } catch {
        throw "Failed to acquire Sigma mutex: $_"
    }
}
function Release-SigMutex {
    if ($script:SigmaMutex) {
        try { $script:SigmaMutex.ReleaseMutex() } catch { }
        try { $script:SigmaMutex.Dispose() } catch { }
        $script:SigmaMutex = $null
    }
}
Acquire-SigMutex
# Cleanup on exit
trap { Release-SigMutex; break }

function Write-Sig {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK','DEBUG','SECTION')][string]$Level = 'INFO',
        [string]$Tag = ''
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    $tagText = ''
    if ($Tag) { $tagText = " [$Tag]" }
    $line = "[$ts][$Level]$tagText $Message"
    Add-Content -Path (Join-Path $script:SigmaLog ("sigma-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))) -Value $line -Encoding UTF8 -EA SilentlyContinue
    $color = 'Cyan'
    switch ($Level) {
        'ERROR'   { $color = 'Red' }
        'WARN'    { $color = 'Yellow' }
        'OK'      { $color = 'Green' }
        'DEBUG'   { $color = 'DarkGray' }
        'SECTION' { $color = 'Magenta' }
    }
    if ($Level -ne 'DEBUG') { Write-Host $line -ForegroundColor $color }
}

function Add-SigError {
    param([string]$Message)
    Add-Content -Path $script:ErrorLog -Value "$(Get-Date -Format 'HH:mm:ss') $Message" -Encoding UTF8 -EA SilentlyContinue
}

# Custom exception (Fix #16)
class SigmaCriticalMutationException : System.Exception {
    SigmaCriticalMutationException([string]$message) : base($message) { }
}

# -----------------------------------------------------------------------------
# SECTION 2 - Journal (with new event types; Fix #2, #5, #6)
# -----------------------------------------------------------------------------

$script:SigJournalEventTypes = @(
    'Capture','ApplyAttempted','ApplySucceeded',
    'VerifySucceeded','VerifyFailed',
    'CompensationAttempted','CompensationSucceeded','CompensationFailed',
    'RollbackAttempted','RollbackSucceeded','RollbackFailed',
    'Note'
)

function Write-SigJournalEvent {
    param(
        [Parameter(Mandatory)][string]$TxId,
        [Parameter(Mandatory)][string]$MutationId,
        [Parameter(Mandatory)]
        [ValidateSet('Capture','ApplyAttempted','ApplySucceeded',
                     'VerifySucceeded','VerifyFailed',
                     'CompensationAttempted','CompensationSucceeded','CompensationFailed',
                     'RollbackAttempted','RollbackSucceeded','RollbackFailed',
                     'Note')]
        [string]$Event,
        [string]$Kind,
        [string]$Target,
        $Prior,
        $New,
        [int]$Sequence,
        [string]$Detail
    )
    $dir = Join-Path $script:SigmaTx $TxId
    if (-not (Test-Path $dir)) { throw "Transaction not found: $TxId" }

    $entry = [PSCustomObject]@{
        TxId       = $TxId
        MutationId = $MutationId
        Event      = $Event
        Sequence   = $Sequence
        Kind       = $Kind
        Target     = $Target
        Prior      = $Prior
        New        = $New
        Detail     = $Detail
        Time       = (Get-Date).ToString('o')
    }
    $entry | ConvertTo-Json -Depth 6 -Compress |
        Add-Content (Join-Path $dir 'journal.jsonl') -Encoding UTF8
}

function Get-SigNextSequence {
    # Per-transaction monotonic sequence.
    param([Parameter(Mandatory)][string]$TxId)
    $dir = Join-Path $script:SigmaTx $TxId
    $seqFile = Join-Path $dir 'sequence.txt'
    $current = 0
    if (Test-Path $seqFile) {
        $raw = Get-Content $seqFile -Raw -EA SilentlyContinue
        if ($raw -match '^(\d+)') { $current = [int]$Matches[1] }
    }
    $current++
    $current | Set-Content $seqFile -Encoding UTF8
    return $current
}

function Write-SigJournalHash {
    # Fix #23: SHA disposed. Fix #6: also writes a manifest.
    param([Parameter(Mandatory)][string]$TxId)
    $dir = Join-Path $script:SigmaTx $TxId
    $journal = Join-Path $dir 'journal.jsonl'
    $metaFile = Join-Path $dir 'metadata.json'
    if (-not (Test-Path $journal)) { return }
    $sha = $null
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $journalHash = [System.BitConverter]::ToString(
            $sha.ComputeHash([System.IO.File]::ReadAllBytes($journal))) -replace '-',''
        $metaHash = $null
        if (Test-Path $metaFile) {
            $metaHash = [System.BitConverter]::ToString(
                $sha.ComputeHash([System.IO.File]::ReadAllBytes($metaFile))) -replace '-',''
        }
        $manifest = [PSCustomObject]@{
            SigmaVersion              = $script:SigmaVersion
            TransactionSchemaVersion  = $script:TransactionSchema
            TransactionId             = $TxId
            JournalHash               = $journalHash.ToLowerInvariant()
            MetadataHash              = if ($metaHash) { $metaHash.ToLowerInvariant() } else { $null }
            GeneratedAt               = (Get-Date).ToString('o')
        }
        $manifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'manifest.json') -Encoding UTF8
        $journalHash.ToLowerInvariant() | Set-Content (Join-Path $dir 'journal.sha256') -Encoding UTF8
    } finally {
        if ($sha) { $sha.Dispose() }
    }
}

function Test-SigJournalIntegrity {
    param([Parameter(Mandatory)][string]$TxId)
    $dir = Join-Path $script:SigmaTx $TxId
    $journal = Join-Path $dir 'journal.jsonl'
    $hashFile = Join-Path $dir 'journal.sha256'
    if (-not (Test-Path $journal) -or -not (Test-Path $hashFile)) {
        return [PSCustomObject]@{ Known=$false; Match=$null; Expected=$null; Actual=$null }
    }
    $expected = (Get-Content $hashFile -Raw).Trim()
    $sha = $null
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $actual = ([System.BitConverter]::ToString(
            $sha.ComputeHash([System.IO.File]::ReadAllBytes($journal))) -replace '-','').ToLowerInvariant()
    } finally {
        if ($sha) { $sha.Dispose() }
    }
    [PSCustomObject]@{ Known=$true; Match=($expected -eq $actual); Expected=$expected; Actual=$actual }
}

# -----------------------------------------------------------------------------
# SECTION 3 - Transaction engine (Fix #3, #15)
# -----------------------------------------------------------------------------

$script:CurrentTxId = $null

function New-SigMutationId {
    [guid]::NewGuid().ToString('N').Substring(0,12)
}

function Start-SigTransaction {
    # Fix #3: timestamp with ms + random suffix
    param([string]$Name)
    $id = "tx_{0}_{1}_{2}" -f `
        (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), `
        ($Name -replace '[^\w\-]','_'), `
        ([guid]::NewGuid().ToString('N').Substring(0,8))
    $dir = Join-Path $script:SigmaTx $id
    if (Test-Path $dir) { throw "Transaction directory already exists: $id" }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $script:CurrentTxId = $id

    $metadata = [PSCustomObject]@{
        SigmaVersion             = $script:SigmaVersion
        TransactionSchemaVersion = $script:TransactionSchema
        Id                       = $id
        Name                     = $Name
        Directory                = $dir
        Started                  = (Get-Date).ToString('o')
        State                    = 'Started'
        Applied                  = 0
        Failed                   = 0
        RequiresReboot           = $false
        RecoveryRequired         = $false
        Optimizations            = @()
    }
    $metadata | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'metadata.json') -Encoding UTF8
    New-Item -ItemType File -Path (Join-Path $dir 'journal.jsonl') -Force | Out-Null
    '0' | Set-Content (Join-Path $dir 'sequence.txt') -Encoding UTF8

    Write-Sig "Transaction started: $id" -Tag 'TX'
    return $id
}

function Set-SigTxState {
    param(
        [Parameter(Mandatory)][string]$TxId,
        [Parameter(Mandatory)]
        [ValidateSet('Started','Applying','Applied','PartiallyApplied',
                     'RecoveryRequired',
                     'ValidationPending','ValidatedImprovement','ValidatedRegression',
                     'ValidatedInconclusive','RolledBack','RollbackPartialFailure','AlreadyRolledBack')]
        [string]$State,
        [int]$Applied,
        [int]$Failed,
        [bool]$RequiresReboot,
        [bool]$RecoveryRequired,
        [string[]]$Optimizations
    )
    $metaFile = Join-Path (Join-Path $script:SigmaTx $TxId) 'metadata.json'
    if (-not (Test-Path $metaFile)) { return }
    $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
    $meta.State = $State
    if ($PSBoundParameters.ContainsKey('Applied'))          { $meta.Applied = $Applied }
    if ($PSBoundParameters.ContainsKey('Failed'))           { $meta.Failed  = $Failed }
    if ($PSBoundParameters.ContainsKey('RequiresReboot'))   { $meta.RequiresReboot = $RequiresReboot }
    if ($PSBoundParameters.ContainsKey('RecoveryRequired')) { $meta.RecoveryRequired = $RecoveryRequired }
    if ($PSBoundParameters.ContainsKey('Optimizations'))    { $meta.Optimizations = $Optimizations }
    $meta | Add-Member -NotePropertyName 'LastStateChange' -NotePropertyValue (Get-Date).ToString('o') -Force
    $meta | ConvertTo-Json -Depth 4 | Set-Content $metaFile -Encoding UTF8
    Write-Sig "TX $TxId → $State" -Tag 'TX'
}

function Invoke-SigRegistryWrite {
    # Fix #2: ApplySucceeded immediately after command, before verify.
    # Fix #1: CompensationSucceeded/CompensationFailed are separate.
    # Fix #15: On compensation failure, mark RecoveryRequired and throw critical.
    param(
        [Parameter(Mandatory)][string]$TxId,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        $Value,
        [ValidateSet('String','DWord','QWord','MultiString','ExpandString','Binary')]
        [string]$Type = 'DWord'
    )

    $mutationId = New-SigMutationId
    $seq = Get-SigNextSequence -TxId $TxId

    # ---- Capture ----
    $keyExisted = Test-Path $Path
    $valueExisted = $false
    $priorVal  = $null
    $priorKind = $null
    if ($keyExisted) {
        $item = Get-ItemProperty -Path $Path -Name $Name -EA SilentlyContinue
        if ($null -ne $item) {
            $valueExisted = $true
            $priorVal = $item.$Name
            try { $priorKind = (Get-Item $Path).GetValueKind($Name).ToString() } catch { }
        }
    }

    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'Capture' -Sequence $seq `
        -Kind 'Registry' -Target "$Path::$Name" `
        -Prior @{ KeyExisted=$keyExisted; ValueExisted=$valueExisted; Value=$priorVal; ValueKind=$priorKind } `
        -New   @{ Value=$Value; Type=$Type }

    # ---- Apply attempt ----
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplyAttempted' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"

    $applySucceeded = $false
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -EA Stop | Out-Null
        $applySucceeded = $true
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplySucceeded' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name" -Detail "Apply command failed: $_"
        # Command failed → no mutation happened → nothing to compensate
        throw
    }

    # ---- Verify ----
    $verifyOk = $false
    try {
        $verify = (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name
        if ($verify -is [array]) { $verifyOk = (($verify -join ',') -eq ($Value -join ',')) }
        else { $verifyOk = ("$verify" -eq "$Value") }
        if (-not $verifyOk) { throw "Verification mismatch: expected '$Value', got '$verify'" }
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifySucceeded' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name" -Detail "$_"

        # ---- Compensation ----
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationAttempted' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
        $compensated = $false
        try {
            if ($valueExisted) {
                New-ItemProperty -Path $Path -Name $Name -Value $priorVal -PropertyType $priorKind -Force -EA Stop | Out-Null
                $cverify = (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name
                if ("$cverify" -ne "$priorVal") { throw "Compensation verify mismatch" }
            } else {
                Remove-ItemProperty -Path $Path -Name $Name -EA SilentlyContinue
                $still = Get-ItemProperty -Path $Path -Name $Name -EA SilentlyContinue
                if ($null -ne $still) { throw "Compensation removal failed" }
            }
            if (-not $keyExisted -and (Test-Path $Path)) {
                $children = @(Get-ChildItem $Path -EA SilentlyContinue)
                $props = @((Get-Item $Path).Property)
                if ($children.Count -eq 0 -and $props.Count -eq 0) {
                    Remove-Item $Path -Force -EA SilentlyContinue
                }
            }
            $compensated = $true
            Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationSucceeded' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
        } catch {
            Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationFailed' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name" -Detail "$_"
        }

        if (-not $compensated) {
            # Fix #15: mark transaction, throw critical exception to halt batch
            Set-SigTxState -TxId $TxId -State 'RecoveryRequired' -RecoveryRequired $true
            throw [SigmaCriticalMutationException]::new(
                "Registry mutation $Path::$Name could not be verified OR compensated. Transaction $TxId is in RecoveryRequired.")
        }
        throw
    }

    return $mutationId
}

function Invoke-SigFsutilWrite {
    # Same pattern as registry.
    param(
        [Parameter(Mandatory)][string]$TxId,
        [Parameter(Mandatory)][string]$Setting,
        [Parameter(Mandatory)][string]$NewValue
    )
    $mutationId = New-SigMutationId
    $seq = Get-SigNextSequence -TxId $TxId

    $cmd = "fsutil behavior query $Setting"
    $raw = & fsutil behavior query $Setting 2>&1
    $exit = $LASTEXITCODE
    $text = ($raw -join "`n")
    $prior = $null
    if ($text -match '=\s*(\d+)') { $prior = $Matches[1] }

    if ($null -eq $prior) {
        throw "Unable to determine '$Setting' state (exit=$exit). Refusing modification. ParserVersion=fsutil-equals-int-v1."
    }

    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'Capture' -Sequence $seq -Kind 'Fsutil' -Target $Setting `
        -Prior @{ Value=$prior; RawOutput=$text; ExitCode=$exit; Command=$cmd; ParserVersion='fsutil-equals-int-v1' } `
        -New   @{ Value=$NewValue }

    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplyAttempted' -Sequence $seq -Kind 'Fsutil' -Target $Setting

    try {
        & fsutil behavior set $Setting $NewValue 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "fsutil set exited $LASTEXITCODE" }
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplySucceeded' -Sequence $seq -Kind 'Fsutil' -Target $Setting
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Fsutil' -Target $Setting -Detail "Apply failed: $_"
        throw
    }

    try {
        $vRaw = & fsutil behavior query $Setting 2>&1
        $v = $null
        if ((($vRaw -join "`n") -match '=\s*(\d+)')) { $v = $Matches[1] }
        if ($v -ne $NewValue) { throw "fsutil verify mismatch (expected $NewValue, got $v)" }
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifySucceeded' -Sequence $seq -Kind 'Fsutil' -Target $Setting
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Fsutil' -Target $Setting -Detail "$_"
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationAttempted' -Sequence $seq -Kind 'Fsutil' -Target $Setting

        $compensated = $false
        try {
            & fsutil behavior set $Setting $prior 2>&1 | Out-Null
            $cRaw = & fsutil behavior query $Setting 2>&1
            $restored = $null
            if ((($cRaw -join "`n") -match '=\s*(\d+)')) { $restored = $Matches[1] }
            if ($restored -ne $prior) { throw "fsutil compensation mismatch" }
            $compensated = $true
            Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationSucceeded' -Sequence $seq -Kind 'Fsutil' -Target $Setting
        } catch {
            Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationFailed' -Sequence $seq -Kind 'Fsutil' -Target $Setting -Detail "$_"
        }
        if (-not $compensated) {
            Set-SigTxState -TxId $TxId -State 'RecoveryRequired' -RecoveryRequired $true
            throw [SigmaCriticalMutationException]::new(
                "fsutil mutation $Setting could not be verified OR compensated. Transaction $TxId is in RecoveryRequired.")
        }
        throw
    }
    return $mutationId
}

function Restore-SigTransaction {
    # Fix #1: distinguishes CompensationSucceeded from CompensationFailed
    # Fix #8: respects RolledBack
    # Fix #9: no handler counts as failure
    # Fix #13: AlreadyRolledBack when nothing to do
    # Fix #14: rollback candidates are Applied mutations that are not (CompensationSucceeded or RolledBack)
    param([Parameter(Mandatory)][string]$TxId)

    $dir = Join-Path $script:SigmaTx $TxId
    if (-not (Test-Path $dir)) { throw "Transaction not found: $TxId" }

    $integrity = Test-SigJournalIntegrity -TxId $TxId
    if ($integrity.Known -and -not $integrity.Match) {
        Write-Sig "Journal corruption detected for $TxId. Rollback safety cannot be guaranteed." -Level ERROR -Tag 'TX'
        $proceed = Read-Host "Continue rollback anyway? (Y/N)"
        if ($proceed -notin 'Y','y') { return }
    }

    $journal = Join-Path $dir 'journal.jsonl'
    if (-not (Test-Path $journal)) { Write-Sig "Empty journal: $TxId" -Level WARN -Tag 'TX'; return }

    $events = Get-Content $journal | ForEach-Object { $_ | ConvertFrom-Json }

    $mutations = @{}
    foreach ($e in $events) {
        if (-not $mutations.ContainsKey($e.MutationId)) {
            $mutations[$e.MutationId] = [PSCustomObject]@{
                Id = $e.MutationId; Kind=$null; Target=$null; Prior=$null; New=$null
                Sequence=0
                Applied=$false; Verified=$false
                CompensationSucceeded=$false; CompensationFailed=$false
                RolledBack=$false
            }
        }
        switch ($e.Event) {
            'Capture'              { $mutations[$e.MutationId].Kind     = $e.Kind
                                     $mutations[$e.MutationId].Target   = $e.Target
                                     $mutations[$e.MutationId].Prior    = $e.Prior
                                     $mutations[$e.MutationId].New      = $e.New
                                     $mutations[$e.MutationId].Sequence = [int]$e.Sequence }
            'ApplySucceeded'       { $mutations[$e.MutationId].Applied = $true }
            'VerifySucceeded'      { $mutations[$e.MutationId].Verified = $true }
            'CompensationSucceeded'{ $mutations[$e.MutationId].CompensationSucceeded = $true }
            'CompensationFailed'   { $mutations[$e.MutationId].CompensationFailed = $true }
            'RollbackSucceeded'    { $mutations[$e.MutationId].RolledBack = $true }
        }
    }

    # Fix #14: rollback candidates
    $toRestore = $mutations.Values |
        Where-Object {
            $_.Applied -and
            -not $_.CompensationSucceeded -and
            -not $_.RolledBack
        } |
        Sort-Object Sequence -Descending

    if (-not $toRestore -or @($toRestore).Count -eq 0) {
        # Fix #13
        Write-Sig "No active mutations remain to rollback for $TxId." -Level OK -Tag 'TX'
        Set-SigTxState -TxId $TxId -State 'AlreadyRolledBack'
        return
    }

    $okCount = 0; $failCount = 0

    foreach ($m in $toRestore) {
        Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackAttempted' -Sequence $m.Sequence -Kind $m.Kind -Target $m.Target
        try {
            switch ($m.Kind) {
                'Registry' {
                    $parts = $m.Target -split '::'
                    $path = $parts[0]; $name = $parts[1]
                    $keyExisted   = [bool]$m.Prior.KeyExisted
                    $valueExisted = [bool]$m.Prior.ValueExisted

                    if ($valueExisted) {
                        $kind = $m.Prior.ValueKind
                        if (-not $kind) { $kind = 'String' }
                        New-ItemProperty -Path $path -Name $name -Value $m.Prior.Value -PropertyType $kind -Force -EA Stop | Out-Null
                        $verify = (Get-ItemProperty -Path $path -Name $name -EA Stop).$name
                        if ("$verify" -ne "$($m.Prior.Value)") { throw "Rollback verify mismatch" }
                    } else {
                        Remove-ItemProperty -Path $path -Name $name -EA SilentlyContinue
                        $still = Get-ItemProperty -Path $path -Name $name -EA SilentlyContinue
                        if ($null -ne $still) { throw "Rollback removal failed" }
                    }
                    if (-not $keyExisted -and (Test-Path $path)) {
                        $children = @(Get-ChildItem $path -EA SilentlyContinue)
                        $props = @((Get-Item $path).Property)
                        if ($children.Count -eq 0 -and $props.Count -eq 0) {
                            Remove-Item $path -Force -EA SilentlyContinue
                        }
                    }
                    Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackSucceeded' -Sequence $m.Sequence -Kind 'Registry' -Target $m.Target
                    $okCount++
                }
                'Fsutil' {
                    if ($null -ne $m.Prior.Value) {
                        & fsutil behavior set $m.Target $m.Prior.Value 2>&1 | Out-Null
                        $vRaw = & fsutil behavior query $m.Target 2>&1
                        $v = $null
                        if ((($vRaw -join "`n") -match '=\s*(\d+)')) { $v = $Matches[1] }
                        if ($v -ne $m.Prior.Value) { throw "fsutil rollback verify mismatch" }
                        Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackSucceeded' -Sequence $m.Sequence -Kind 'Fsutil' -Target $m.Target
                        $okCount++
                    }
                }
                default {
                    Write-Sig "No rollback handler for kind '$($m.Kind)'" -Level ERROR -Tag 'TX'
                    Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackFailed' -Sequence $m.Sequence -Kind $m.Kind -Target $m.Target -Detail 'No rollback handler'
                    $failCount++
                }
            }
        } catch {
            Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackFailed' -Sequence $m.Sequence -Kind $m.Kind -Target $m.Target -Detail "$_"
            Write-Sig "Rollback entry failed: $($m.Kind) $($m.Target) — $_" -Level ERROR -Tag 'TX'
            $failCount++
        }
    }

    Write-SigJournalHash -TxId $TxId

    if ($failCount -eq 0) { Set-SigTxState -TxId $TxId -State 'RolledBack' }
    else                  { Set-SigTxState -TxId $TxId -State 'RollbackPartialFailure' }
    Write-Sig "Rollback $TxId done (ok=$okCount fail=$failCount)" -Level OK -Tag 'TX'
}

function Get-SigPendingTxIds {
    if (-not (Test-Path $script:SigmaPend)) { return @() }
    Get-ChildItem $script:SigmaPend -Filter '*.json' -EA SilentlyContinue | ForEach-Object { $_.BaseName }
}

function Save-SigPendingValidation {
    param([string]$TxId, [string]$BaselineLabel)
    $obj = [PSCustomObject]@{
        TxId=$TxId; BaselineLabel=$BaselineLabel; NextPhase='Validate'
        SavedAt=(Get-Date).ToString('o'); SigmaVersion=$script:SigmaVersion
    }
    $obj | ConvertTo-Json | Set-Content (Join-Path $script:SigmaPend "$TxId.json") -Encoding UTF8
    Write-Sig "Pending validation: $TxId" -Tag 'RESUME'
}

function Clear-SigPendingValidation {
    param([string]$TxId)
    $f = Join-Path $script:SigmaPend "$TxId.json"
    if (Test-Path $f) { Remove-Item $f -Force -EA SilentlyContinue }
}

# -----------------------------------------------------------------------------
# SECTION 4 - Counter defs
# -----------------------------------------------------------------------------

$script:SigCounterDefs = @(
    [PSCustomObject]@{ Id='DPC_TIME'; English='\Processor Information(_Total)\% DPC Time' }
    [PSCustomObject]@{ Id='ISR_TIME'; English='\Processor Information(_Total)\% Interrupt Time' }
    [PSCustomObject]@{ Id='DPC_RATE'; English='\Processor Information(_Total)\DPCs Queued/sec' }
    [PSCustomObject]@{ Id='ISR_RATE'; English='\Processor Information(_Total)\Interrupts/sec' }
)

function Resolve-SigCounterDef {
    param($Def)
    try {
        $null = Get-Counter -Counter $Def.English -MaxSamples 1 -EA Stop
        return [PSCustomObject]@{ Id=$Def.Id; Resolved=$true; Path=$Def.English; Method='English' }
    } catch {
        return [PSCustomObject]@{ Id=$Def.Id; Resolved=$false; Path=$Def.English; Method='EnglishFailed'; Error="$($_.Exception.Message)" }
    }
}

# -----------------------------------------------------------------------------
# SECTION 5 - Evidence
# -----------------------------------------------------------------------------

function New-Evidence {
    param(
        [string]$DetectorId, [int]$Category,
        [ValidateSet('OK','WARN','FAIL','INFO','SKIP')][string]$Status,
        [int]$Severity = 0, [double]$Confidence = 1.0,
        [string]$Subject = '', [string]$Finding = '',
        $ObservedValue = $null, $ExpectedValue = $null,
        [string[]]$EvidenceLines = @(),
        [string[]]$ProbableCauses = @(),
        [string[]]$RecommendationIds = @(),
        $Data = $null
    )
    [PSCustomObject]@{
        DetectorId=$DetectorId; Category=$Category; Status=$Status; Severity=$Severity
        Confidence=$Confidence; Subject=$Subject; Finding=$Finding
        ObservedValue=$ObservedValue; ExpectedValue=$ExpectedValue
        Evidence=$EvidenceLines; ProbableCauses=$ProbableCauses
        RecommendationIds=$RecommendationIds; Data=$Data
        Timestamp=(Get-Date).ToString('o')
    }
}

# -----------------------------------------------------------------------------
# SECTION 6 - Hardware
# -----------------------------------------------------------------------------

function Test-SigLikelyHybridCpu {
    param($Cpu)
    $name = $Cpu.Name
    $patterns = @('12th Gen Intel','13th Gen Intel','14th Gen Intel','Core Ultra','Core 5 1','Core 7 1','Core 9 1')
    foreach ($p in $patterns) { if ($name -match $p) { return $true } }
    try {
        $cim = Get-CimInstance Win32_Processor -EA Stop
        if ($cim.PSObject.Properties.Name -contains 'EfficiencyClass') {
            $classes = @($cim | Select-Object -ExpandProperty EfficiencyClass -EA SilentlyContinue)
            if (($classes | Sort-Object -Unique).Count -gt 1) { return $true }
        }
    } catch { }
    return $false
}

function Get-SigMachineProfile {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $batt = Get-CimInstance Win32_Battery -EA SilentlyContinue
    $vendor = 'Other'
    if ($cpu.Manufacturer -match 'Intel') { $vendor = 'Intel' }
    elseif ($cpu.Manufacturer -match 'AMD') { $vendor = 'AMD' }
    [PSCustomObject]@{
        Manufacturer = $cs.Manufacturer; Model = $cs.Model
        IsLaptop = [bool]$batt; CPUVendor = $vendor; CPUName = $cpu.Name
        LikelyHybrid = (Test-SigLikelyHybridCpu $cpu)
        TotalRAMGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        ChassisType = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
    }
}

function Get-SigHardwareInventory {
    $profile = Get-SigMachineProfile
    $mb   = Get-CimInstance Win32_BaseBoard -EA SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -EA SilentlyContinue
    $mem  = Get-CimInstance Win32_PhysicalMemory
    $arr  = Get-CimInstance Win32_PhysicalMemoryArray
    $gpus = Get-CimInstance Win32_VideoController
    $disks = Get-PhysicalDisk -EA SilentlyContinue
    $net  = Get-NetAdapter -Physical -EA SilentlyContinue

    $memModules = $mem | ForEach-Object {
        [PSCustomObject]@{ Bank=$_.BankLabel; Loc=$_.DeviceLocator; GB=[math]::Round($_.Capacity / 1GB, 0)
            Rated=$_.Speed; Running=$_.ConfiguredClockSpeed; Mfr=$_.Manufacturer; Part=($_.PartNumber -replace '\s+$','') }
    }

    [PSCustomObject]@{
        Timestamp = (Get-Date).ToString('o'); SigmaVersion = $script:SigmaVersion; Profile = $profile
        Motherboard = [PSCustomObject]@{ Mfr=$mb.Manufacturer; Product=$mb.Product; Version=$mb.Version }
        BIOS = [PSCustomObject]@{ Vendor=$bios.Manufacturer; Version=$bios.SMBIOSBIOSVersion; Date=$bios.ReleaseDate }
        CPUs = Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,CurrentClockSpeed,SocketDesignation
        Memory = [PSCustomObject]@{
            TotalGB = [math]::Round(($mem|Measure-Object Capacity -Sum).Sum/1GB,0)
            Modules = $memModules; Slots = $arr.MemoryDevices
            MultipleModulesDetected = (($memModules.Loc | Sort-Object -Unique).Count -ge 2)
            ConfiguredBelowReportedModuleSpeed = (($memModules | Where-Object { $_.Running -lt $_.Rated }).Count -gt 0)
        }
        GPUs = $gpus | Select-Object Name,DriverVersion,DriverDate,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate,Status
        Storage = $disks | ForEach-Object {
            $rel = $null; try { $rel = $_ | Get-StorageReliabilityCounter -EA Stop } catch { }
            [PSCustomObject]@{ Number=$_.DeviceId; Name=$_.FriendlyName; Media=$_.MediaType; Bus=$_.BusType
                SizeGB=[math]::Round($_.Size/1GB,1); Health=$_.HealthStatus
                Temp=$rel.Temperature; Wear=$rel.Wear; PowerOn=$rel.PowerOnHours }
        }
        Network = $net | ForEach-Object {
            [PSCustomObject]@{ Name=$_.Name; Desc=$_.InterfaceDescription; Status=$_.Status
                LinkSpeed=$_.LinkSpeed; DriverVersion=$_.DriverVersion; DriverDate=$_.DriverDate }
        }
    }
}

# -----------------------------------------------------------------------------
# SECTION 7 - Correlation
# -----------------------------------------------------------------------------

function Get-SigEventStream {
    param([int]$HoursBack = 72)
    $start = (Get-Date).AddHours(-$HoursBack)
    $rules = @(
        [PSCustomObject]@{ Log='System'; Id=41;   Provider=$null; Cat='Stability'; Name='Unexpected shutdown (Kernel-Power)' }
        [PSCustomObject]@{ Log='System'; Id=1001; Provider='Microsoft-Windows-WER-SystemErrorReporting'; Cat='Stability'; Name='BSOD (WER)' }
        [PSCustomObject]@{ Log='System'; Id=4101; Provider=$null; Cat='GPU'; Name='GPU TDR' }
        [PSCustomObject]@{ Log='System'; Id=1;    Provider='Microsoft-Windows-WHEA-Logger'; Cat='Hardware'; Name='WHEA error' }
        [PSCustomObject]@{ Log='System'; Id=7;    Provider=$null; Cat='Storage'; Name='Disk bad block' }
        [PSCustomObject]@{ Log='System'; Id=51;   Provider=$null; Cat='Storage'; Name='Disk paging error' }
        [PSCustomObject]@{ Log='System'; Id=153;  Provider=$null; Cat='Storage'; Name='Disk IO retry' }
        [PSCustomObject]@{ Log='System'; Id=19;   Provider=$null; Cat='Update'; Name='Windows update installed' }
        [PSCustomObject]@{ Log='System'; Id=20;   Provider=$null; Cat='Update'; Name='Windows update failed' }
        [PSCustomObject]@{ Log='System'; Id=7045; Provider=$null; Cat='Persistence'; Name='Service installed' }
        [PSCustomObject]@{ Log='Application'; Id=1000; Provider=$null; Cat='App'; Name='Application crash' }
        [PSCustomObject]@{ Log='Application'; Id=1002; Provider=$null; Cat='App'; Name='Application hang' }
    )
    $events = New-Object System.Collections.ArrayList
    foreach ($rule in $rules) {
        $filter = @{ LogName=$rule.Log; Id=$rule.Id; StartTime=$start }
        if ($rule.Provider) { $filter.ProviderName = $rule.Provider }
        try {
            Get-WinEvent -FilterHashtable $filter -EA Stop | ForEach-Object {
                $null = $events.Add([PSCustomObject]@{
                    Time=$_.TimeCreated; Log=$rule.Log; Id=$rule.Id
                    Category=$rule.Cat; Name=$rule.Name; Provider=$_.ProviderName
                    Message=(($_.Message -split "`n")[0]).Trim()
                })
            }
        } catch { }
    }
    try {
        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Configuration';StartTime=$start} -EA Stop |
            Where-Object { $_.Id -in 400,410,411,412,420 } |
            ForEach-Object {
                $null = $events.Add([PSCustomObject]@{ Time=$_.TimeCreated; Log='PnP'; Id=$_.Id
                    Category='Driver'; Name='PnP driver event'; Provider=$_.ProviderName
                    Message=(($_.Message -split "`n")[0]).Trim() })
            }
    } catch { }
    $events | Sort-Object Time
}

function Get-SigCorrelationScore {
    param($Cause, $Symptom, [double]$DeltaSec)
    $score = 0.20
    switch ($Cause.Category) {
        'Driver'      { if ($Symptom.Category -eq 'GPU') { $score=0.75 }; if ($Symptom.Category -eq 'Stability') { $score=0.60 } }
        'Update'      { if ($Symptom.Category -eq 'Stability') { $score=0.65 }; if ($Symptom.Category -eq 'GPU') { $score=0.55 } }
        'Persistence' { if ($Symptom.Category -eq 'App') { $score=0.40 } }
    }
    if ($DeltaSec -le 5) { $score += 0.15 } elseif ($DeltaSec -le 15) { $score += 0.05 }
    if ($score -gt 1.0) { $score = 1.0 }
    [math]::Round($score, 2)
}

function Get-SigCorrelations {
    param([Parameter(Mandatory)]$Events, [int]$WindowSeconds = 30)
    $symptomCats = 'Stability','GPU','App','Hardware'
    $causeCats   = 'Driver','Update','Persistence'
    $out = New-Object System.Collections.ArrayList
    foreach ($s in ($Events | Where-Object { $_.Category -in $symptomCats })) {
        $windowStart = $s.Time.AddSeconds(-$WindowSeconds)
        $candidates = $Events | Where-Object { $_.Category -in $causeCats -and $_.Time -ge $windowStart -and $_.Time -le $s.Time }
        foreach ($c in $candidates) {
            $delta = [math]::Round(($s.Time - $c.Time).TotalSeconds, 1)
            $score = Get-SigCorrelationScore -Cause $c -Symptom $s -DeltaSec $delta
            $null = $out.Add([PSCustomObject]@{
                SymptomTime=$s.Time; SymptomName=$s.Name
                SuspectTime=$c.Time; SuspectName=$c.Name; SuspectCat=$c.Category
                DeltaSec=$delta; CorrelationScore=$score
                Reasoning="$($c.Category) event $delta seconds before $($s.Name)"
            })
        }
    }
    $out | Sort-Object CorrelationScore -Descending
}

# -----------------------------------------------------------------------------
# SECTION 8 - WinRE (Fix #9, #10)
# -----------------------------------------------------------------------------

function Get-SigWinReState {
    $result = [PSCustomObject]@{
        InstalledKnown = $false; Installed = $null
        EnabledKnown   = $false; Enabled   = $null
        ConfiguredKnown= $false; Configured= $null
        Method = $null; Confidence = 'unknown'
    }

    try {
        $p = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinRE'
        if (Test-Path $p) {
            $item = Get-ItemProperty -Path $p -EA Stop
            $hasDisabled = ($item.PSObject.Properties.Name -contains 'WinReDisabled') -and ($null -ne $item.WinReDisabled)
            $hasConfigured = ($item.PSObject.Properties.Name -contains 'WinReConfigured') -and ($null -ne $item.WinReConfigured)

            if ($hasDisabled) {
                # Fix #9: registry heuristic, not authoritative
                $result.InstalledKnown = $true
                $result.Installed = $true
                $result.EnabledKnown = $true
                $result.Enabled = ($item.WinReDisabled -eq 0)
                $result.ConfiguredKnown = $hasConfigured
                if ($hasConfigured) { $result.Configured = [bool]$item.WinReConfigured }
                $result.Method = 'registry heuristic: WinReDisabled'
                $result.Confidence = 'medium'
                return $result
            }
            if ($hasConfigured) {
                # Fix #10: do NOT infer Enabled from Configured
                $result.InstalledKnown = $true
                $result.Installed = [bool]$item.WinReConfigured
                $result.ConfiguredKnown = $true
                $result.Configured = [bool]$item.WinReConfigured
                $result.EnabledKnown = $false
                $result.Enabled = $null
                $result.Method = 'registry heuristic: WinReConfigured (enabled state unknown)'
                $result.Confidence = 'low'
                return $result
            }
        }
    } catch { }

    try {
        $wim = "$env:WINDIR\System32\Recovery\Winre.wim"
        if (Test-Path $wim) {
            $result.InstalledKnown = $true
            $result.Installed = $true
            $result.EnabledKnown = $false
            $result.Enabled = $null
            $result.Method = 'file:Winre.wim (enabled state unknown)'
            $result.Confidence = 'low'
            return $result
        }
    } catch { }

    $result.Method = 'unknown'
    return $result
}

function Test-SigEfiSystemPresent {
    $isUefi = $false
    try {
        $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType' -EA Stop).PEFirmwareType
        $isUefi = ($pf -eq 2)
    } catch { }
    $efi = Get-Partition -EA SilentlyContinue | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
    [PSCustomObject]@{ IsUefi=$isUefi; HasEfi=[bool]$efi; EfiPartition=$efi }
}

# -----------------------------------------------------------------------------
# SECTION 9 - Counter snapshot
# -----------------------------------------------------------------------------

function Get-SigCounterSnapshot {
    param([int]$Seconds = 15, [int]$IntervalSeconds = 1)
    if ($IntervalSeconds -lt 1) { $IntervalSeconds = 1 }
    $samples = [math]::Max(4, [int]($Seconds / $IntervalSeconds))

    $resolved = @()
    foreach ($def in $script:SigCounterDefs) {
        $r = Resolve-SigCounterDef -Def $def
        if ($r.Resolved) { $resolved += $r }
    }
    if ($resolved.Count -eq 0) {
        return [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); Verdict='UNAVAILABLE'
            Note='No DPC/ISR counters resolved.'; Totals=@() }
    }

    try { $result = Get-Counter -Counter ($resolved.Path) -SampleInterval $IntervalSeconds -MaxSamples $samples -EA Stop }
    catch { return [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); Verdict='UNAVAILABLE'; Note="Get-Counter: $($_.Exception.Message)"; Totals=@() } }

    $totals = foreach ($r in $resolved) {
        $vals = @($result.CounterSamples | Where-Object Path -eq $r.Path | ForEach-Object { [double]$_.CookedValue })
        if ($vals.Count -eq 0) { continue }
        [PSCustomObject]@{ Id = $r.Id; Path = $r.Path
            Avg = [math]::Round(($vals | Measure-Object -Average).Average, 3)
            Max = [math]::Round(($vals | Measure-Object -Maximum).Maximum, 3) }
    }

    $maxDpc = ($totals | Where-Object Id -eq 'DPC_TIME' | Select-Object -ExpandProperty Max -EA SilentlyContinue)
    $maxIsr = ($totals | Where-Object Id -eq 'ISR_TIME' | Select-Object -ExpandProperty Max -EA SilentlyContinue)

    $verdict = 'NORMAL'
    if ($null -ne $maxDpc) {
        if ($maxDpc -gt 20 -or ($null -ne $maxIsr -and $maxIsr -gt 20)) { $verdict = 'CRITICAL — DPC/ISR CPU time elevated' }
        elseif ($maxDpc -gt 5 -or ($null -ne $maxIsr -and $maxIsr -gt 5)) { $verdict = 'ELEVATED — recommend ETW escalation' }
    }

    [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); DurationSec=$Seconds; IntervalSec=$IntervalSeconds
        Totals=$totals; Verdict=$verdict
        Note='DPC/ISR CPU activity screening — not per-DPC execution latency.' }
}

# -----------------------------------------------------------------------------
# SECTION 10 - ETW
# -----------------------------------------------------------------------------

function Start-SigEtwCapture {
    param([Parameter(Mandatory)][string]$OutputPath, [int]$DurationSeconds = 30)
    $wpr = Get-Command wpr.exe -EA SilentlyContinue
    if (-not $wpr) { Write-Sig "WPR not found." -Level WARN -Tag 'ETW'; return $null }

    $wprp = Join-Path $env:TEMP ("sigma-{0}.wprp" -f (Get-Random))
    $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<WindowsPerformanceRecorder Version="1.0">
  <Profiles>
    <SystemCollector Id="SigSys" Name="NT Kernel Logger">
      <BufferSize Value="1024"/><Buffers Value="256"/><MaximumFileSize Value="1024"/>
    </SystemCollector>
    <SystemProvider Id="SigKernel">
      <Keywords>
        <Keyword Value="Loader"/><Keyword Value="Base"/><Keyword Value="CSwitch"/>
        <Keyword Value="DPC"/><Keyword Value="Interrupt"/><Keyword Value="Profile"/>
        <Keyword Value="Timer"/><Keyword Value="ReadyThread"/>
      </Keywords>
      <Stacks><Stack Value="Stack"/></Stacks>
    </SystemProvider>
    <Profile Id="SigDpc.Verbose.File" Name="SigDpc" Description="DPC/ISR" LoggingMode="File" DetailLevel="Verbose">
      <Collectors><SystemCollectorId Value="SigSys"><SystemProviderId Value="SigKernel"/></SystemCollectorId></Collectors>
    </Profile>
  </Profiles>
</WindowsPerformanceRecorder>
'@
    $xml | Set-Content -Path $wprp -Encoding UTF8

    Write-Sig "WPR start..." -Tag 'ETW'
    $startOut = & wpr.exe -start $wprp -filemode 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Sig "WPR start failed: $($startOut -join ' ')" -Level ERROR -Tag 'ETW'
        Remove-Item $wprp -Force -EA SilentlyContinue; return $null
    }
    for ($i = $DurationSeconds; $i -gt 0; $i -= 5) {
        Write-Host "  > capturing ${i}s..." -ForegroundColor DarkGray
        Start-Sleep -Seconds ([math]::Min(5, $i))
    }
    $stopOut = & wpr.exe -stop $OutputPath 2>&1
    Remove-Item $wprp -Force -EA SilentlyContinue
    $null = & wpr.exe -cancel 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Sig "WPR stop failed: $($stopOut -join ' ')" -Level ERROR -Tag 'ETW'; return $null }
    if (-not (Test-Path $OutputPath)) { Write-Sig "ETL not found." -Level ERROR -Tag 'ETW'; return $null }
    $size = (Get-Item $OutputPath).Length
    if ($size -lt 64KB) { Write-Sig "ETL small ($size bytes)." -Level WARN -Tag 'ETW' }
    $mb = [math]::Round($size/1MB,1)
    Write-Sig "ETW: $OutputPath ($mb MB)" -Level OK -Tag 'ETW'
    return $OutputPath
}

# -----------------------------------------------------------------------------
# SECTION 11 - Benchmark (Fixes #7, #19, #20, #23)
# -----------------------------------------------------------------------------

function Get-SigMedian {
    param([double[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $s = $Values | Sort-Object
    $n = $s.Count
    if ($n % 2 -eq 1) { return [double]$s[[int]($n/2)] }
    ([double]$s[$n/2 - 1] + [double]$s[$n/2]) / 2.0
}

function Get-SigStdDev {
    param([double[]]$Values)
    if (-not $Values -or $Values.Count -lt 2) { return 0 }
    $m = ($Values | Measure-Object -Average).Average
    $sq = 0.0; foreach ($v in $Values) { $sq += ($v - $m) * ($v - $m) }
    [math]::Sqrt($sq / ($Values.Count - 1))
}

function Get-SigBootstrapCI {
    param([double[]]$A, [double[]]$B, [int]$Iterations = 2000, [double]$Confidence = 0.95)
    if ($A.Count -lt 2 -or $B.Count -lt 2) {
        return [PSCustomObject]@{ PointEstimate=$null; CI_Low=$null; CI_High=$null; Significant=$false; Direction='Unknown'; Reason='Insufficient samples' }
    }
    $rng = New-Object System.Random
    $diffs = New-Object 'double[]' $Iterations
    for ($i=0; $i -lt $Iterations; $i++) {
        $a = New-Object 'double[]' $A.Count; $b = New-Object 'double[]' $B.Count
        for ($j=0; $j -lt $A.Count; $j++) { $a[$j] = $A[$rng.Next($A.Count)] }
        for ($j=0; $j -lt $B.Count; $j++) { $b[$j] = $B[$rng.Next($B.Count)] }
        $diffs[$i] = (Get-SigMedian $b) - (Get-SigMedian $a)
    }
    [array]::Sort($diffs)
    $alpha = (1 - $Confidence) / 2
    $lo = $diffs[[math]::Max(0, [int]($Iterations * $alpha))]
    $hi = $diffs[[math]::Min($Iterations - 1, [int]($Iterations * (1 - $alpha)))]
    $significant = (($lo -gt 0) -or ($hi -lt 0))
    $direction = 'Inconclusive'
    if ($significant) { if ($lo -gt 0) { $direction='Improvement' } else { $direction='Regression' } }
    [PSCustomObject]@{ PointEstimate=(Get-SigMedian $B) - (Get-SigMedian $A)
        CI_Low=$lo; CI_High=$hi; Confidence=$Confidence
        Significant=$significant; Direction=$direction
        Reason=if ($significant) { 'CI excludes zero' } else { 'CI includes zero' } }
}

function Get-SigThermalSnapshot {
    $out = [PSCustomObject]@{ ACPI_TempC=$null; CurrentMHz=$null; MaxMHz=$null }
    try {
        $z = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -EA Stop | Select-Object -First 1
        if ($z) { $out.ACPI_TempC = [math]::Round(($z.CurrentTemperature / 10) - 273.15, 1) }
    } catch { }
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $out.CurrentMHz = $cpu.CurrentClockSpeed; $out.MaxMHz = $cpu.MaxClockSpeed
    } catch { }
    return $out
}

function Wait-SigSystemIdle {
    # Fix #7: counter failure != 0% load. Both must be KNOWN to advance.
    param([int]$RequiredIdleSeconds = 4, [int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $consecutiveIdle = 0
    $samples = 0
    $started = (Get-Date)
    $cpuBefore = $null; $diskBefore = $null

    while ((Get-Date) -lt $deadline -and $consecutiveIdle -lt $RequiredIdleSeconds) {
        $samples++
        $cpu = $null; $disk = $null
        $cpuKnown = $false; $diskKnown = $false
        try {
            $c = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -EA Stop
            $cpu = ($c.CounterSamples | Measure-Object CookedValue -Average).Average
            $cpuKnown = $true
        } catch { $cpuKnown = $false }
        try {
            $d = Get-Counter '\PhysicalDisk(_Total)\% Disk Time' -SampleInterval 1 -MaxSamples 1 -EA Stop
            $disk = ($d.CounterSamples | Measure-Object CookedValue -Average).Average
            $diskKnown = $true
        } catch { $diskKnown = $false }

        if ($null -eq $cpuBefore -and $cpuKnown) { $cpuBefore = $cpu }
        if ($null -eq $diskBefore -and $diskKnown) { $diskBefore = $disk }

        if ($cpuKnown -and $diskKnown -and $cpu -lt 10 -and $disk -lt 15) {
            $consecutiveIdle++
        } else {
            $consecutiveIdle = 0
            if ($cpuKnown -and $diskKnown) {
                Write-Host "  > waiting for idle (cpu=$([math]::Round($cpu,1))% disk=$([math]::Round($disk,1))%)" -ForegroundColor DarkGray
            } else {
                Write-Host "  > counters unavailable this sample" -ForegroundColor DarkGray
            }
        }
    }

    $passed = ($consecutiveIdle -ge $RequiredIdleSeconds)
    $duration = ((Get-Date) - $started).TotalSeconds

    if (-not $cpuKnown -and -not $diskKnown -and $samples -ge 2) {
        Write-Host "  > idle gate unavailable — proceeding without verified idle state" -ForegroundColor Yellow
    } elseif ($passed) {
        Write-Host "  > BENCHMARK ENVIRONMENT READY" -ForegroundColor Green
    } else {
        Write-Host "  > idle gate timed out" -ForegroundColor Yellow
    }

    [PSCustomObject]@{
        Passed = $passed
        Duration = [math]::Round($duration, 1)
        CpuBeforeStart = $cpuBefore
        DiskBeforeStart = $diskBefore
        CountersAvailable = ($cpuKnown -or $diskKnown)
        Samples = $samples
    }
}

function Measure-SigCpuConsistency {
    param([int]$Seconds = 10, [int]$Runs = 5)
    $results = @()
    $thermal = @()
    $hash = $null
    try {
        $hash = [System.Security.Cryptography.SHA256]::Create()
        for ($run = 1; $run -le $Runs; $run++) {
            Start-Sleep -Seconds 2
            $thermBefore = Get-SigThermalSnapshot
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $iter = 0
            while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("sig-$iter-$($sw.ElapsedTicks)")
                $null = $hash.ComputeHash($bytes)
                $iter++
            }
            $sw.Stop()
            $thermAfter = Get-SigThermalSnapshot
            $thermal += [PSCustomObject]@{ Run=$run; Before=$thermBefore; After=$thermAfter }
            $results += [PSCustomObject]@{ Run=$run; Ops=$iter; OpsPerSec=[math]::Round($iter / $sw.Elapsed.TotalSeconds, 0) }
        }
    } finally {
        if ($hash) { $hash.Dispose() }   # Fix #23
    }
    $ops = [double[]]$results.OpsPerSec
    $median = Get-SigMedian $ops
    $min = ($ops | Measure-Object -Minimum).Minimum
    $max = ($ops | Measure-Object -Maximum).Maximum
    $sd = Get-SigStdDev $ops
    $cv = 0
    if ($median -gt 0) { $cv = [math]::Round(($sd / $median) * 100, 3) }
    [PSCustomObject]@{ Kind='Sigma CPU Consistency Benchmark'; Runs=$results; Thermal=$thermal
        AllOpsPerSec=$ops; MedianOpsPerSec=$median; MinOpsPerSec=$min; MaxOpsPerSec=$max
        StdDevOpsPerSec=[math]::Round($sd, 0); CV_Percent=$cv }
}

function Invoke-SigDiskSpdXml {
    param([string[]]$Arguments, [string]$OutXml, [string]$DiskSpdPath)
    $output = & $DiskSpdPath @Arguments -Rxml 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "DiskSpd exited $exitCode. Output: $($output -join "`n")" }
    $xmlText = $output -join "`r`n"
    try { [xml]$x = $xmlText } catch { throw "DiskSpd output was not valid XML." }
    $xmlText | Set-Content -Path $OutXml -Encoding UTF8
    return $x
}

function Read-SigDiskSpdXml {
    param([xml]$X, [ValidateSet('Read','Write')][string]$Mode)
    $time = [double]$X.Results.TimeSpan.TestTimeSeconds
    if ($time -le 0) { $time = 10 }
    $targets = @($X.Results.TimeSpan.Thread.Target)
    if ($Mode -eq 'Read') {
        $ioCount = ($targets | Measure-Object ReadCount -Sum).Sum
        $bytes   = ($targets | Measure-Object ReadBytes -Sum).Sum
        $avgLat  = [double]$X.Results.TimeSpan.Latency.AverageReadMilliseconds
    } else {
        $ioCount = ($targets | Measure-Object WriteCount -Sum).Sum
        $bytes   = ($targets | Measure-Object WriteBytes -Sum).Sum
        $avgLat  = [double]$X.Results.TimeSpan.Latency.AverageWriteMilliseconds
    }
    $p95 = $null; $p99 = $null
    foreach ($bucket in @($X.Results.TimeSpan.Latency.Bucket)) {
        if ("$($bucket.Percentile)" -eq '95') {
            if ($Mode -eq 'Read') { $p95 = [double]$bucket.ReadMilliseconds } else { $p95 = [double]$bucket.WriteMilliseconds }
        }
        if ("$($bucket.Percentile)" -eq '99') {
            if ($Mode -eq 'Read') { $p99 = [double]$bucket.ReadMilliseconds } else { $p99 = [double]$bucket.WriteMilliseconds }
        }
    }
    [PSCustomObject]@{ IOCount=[int64]$ioCount; Bytes=[int64]$bytes
        IOPS=[math]::Round($ioCount / $time, 0)
        MBps=[math]::Round(($bytes / 1MB) / $time, 1)
        AvgLatencyMs=$avgLat; P95LatencyMs=$p95; P99LatencyMs=$p99
        TestTimeSeconds=$time }
}

function Get-SigDiskSpdVersion {
    param([string]$DiskSpdPath)
    try {
        $file = Get-Item $DiskSpdPath -EA Stop
        if ($file.VersionInfo -and $file.VersionInfo.FileVersion) { return $file.VersionInfo.FileVersion }
    } catch { }
    try {
        $out = & $DiskSpdPath '-?' 2>&1
        if (($out -join "`n") -match '(\d+\.\d+(?:\.\d+)*)') { return $Matches[1] }
    } catch { }
    return 'unknown'
}

function Measure-SigDiskSpd {
    # Fix #19: separate PRECONDITION from MEASUREMENT (no -c on tests)
    param([string]$TargetPath = $env:TEMP)

    $diskspd = Get-Command diskspd.exe -EA SilentlyContinue
    if (-not $diskspd) {
        return [PSCustomObject]@{ Available=$false; Reason='DiskSpd not installed. Install DiskSpd for reliable disk benchmarking.' }
    }
    $diskspdVersion = Get-SigDiskSpdVersion -DiskSpdPath $diskspd.Source

    $tmp = Join-Path $TargetPath ("sigma-diskspd-{0}.bin" -f (Get-Random))
    $xmlPath = [System.IO.Path]::ChangeExtension($tmp, '.xml')

    try {
        # --- PRECONDITION: create 1G file and warm it ---
        $prepArgs = @('-c1G','-t1','-o1','-d3','-w100','-b1M','-Sh',$tmp)
        $null = Invoke-SigDiskSpdXml -Arguments $prepArgs -OutXml $xmlPath -DiskSpdPath $diskspd.Source
        Start-Sleep -Seconds 2

        # --- MEASURE: no -c (uses existing file) ---
        $seqArgs = @('-t1','-o1','-d10','-w0','-b1M','-L','-Sh',$tmp)
        $x = Invoke-SigDiskSpdXml -Arguments $seqArgs -OutXml $xmlPath -DiskSpdPath $diskspd.Source
        $seqRead = Read-SigDiskSpdXml -X $x -Mode 'Read'
        Start-Sleep -Seconds 2

        $writeArgs = @('-t1','-o1','-d10','-w100','-b1M','-L','-Sh',$tmp)
        $x = Invoke-SigDiskSpdXml -Arguments $writeArgs -OutXml $xmlPath -DiskSpdPath $diskspd.Source
        $seqWrite = Read-SigDiskSpdXml -X $x -Mode 'Write'
        Start-Sleep -Seconds 2

        $randArgs = @('-t1','-o1','-d10','-w0','-b4K','-r','-L','-Sh',$tmp)
        $x = Invoke-SigDiskSpdXml -Arguments $randArgs -OutXml $xmlPath -DiskSpdPath $diskspd.Source
        $rand4k = Read-SigDiskSpdXml -X $x -Mode 'Read'

        return [PSCustomObject]@{ Available=$true; Engine='DiskSpd'; EngineVersion=$diskspdVersion
            CacheMode='unbuffered/write-through (-Sh)'
            TestFilePreconditioned=$true
            SequentialRead=$seqRead; SequentialWrite=$seqWrite; Random4KRead_QD1=$rand4k }
    } catch {
        return [PSCustomObject]@{ Available=$false; Reason="DiskSpd run failed: $($_.Exception.Message)" }
    } finally {
        Remove-Item $tmp     -Force -EA SilentlyContinue
        Remove-Item $xmlPath -Force -EA SilentlyContinue
    }
}

function Get-SigTestEnvironment {
    $plan = ((& powercfg /getactivescheme 2>&1) -join '')
    $isAc = $null
    try {
        $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -EA Stop | Select-Object -First 1
        if ($b) { $isAc = [bool]$b.PowerOnline }
    } catch { }
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bg = $null
    try {
        $dpc = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 3 -EA Stop
        $bg = [math]::Round(($dpc.CounterSamples | Measure-Object CookedValue -Average).Average, 2)
    } catch { }   # $bg stays null → safe
    $uptime = ((Get-Date) - $os.LastBootUpTime).TotalMinutes
    [PSCustomObject]@{
        PowerPlan=$plan; OnAc=$isAc; BackgroundCpuPct=$bg
        AvailableRamMB=[math]::Round($os.FreePhysicalMemory / 1KB, 0)
        UptimeMin=[math]::Round($uptime, 1); LastBootTime=$os.LastBootUpTime
        WindowsBuild=$os.BuildNumber
        WindowsUBR=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR -EA SilentlyContinue).UBR
        ComputerModel="$($cs.Manufacturer) $($cs.Model)"
        ThermalSnapshot=(Get-SigThermalSnapshot)
    }
}

function Start-SigBenchmark {
    param([string]$Label = ("run_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
    Write-Sig "Benchmark [$Label]" -Tag 'BM'
    Write-Host "  > idle gating..." -ForegroundColor DarkGray
    $idle = Wait-SigSystemIdle -RequiredIdleSeconds 4 -TimeoutSeconds 30

    $env = Get-SigTestEnvironment
    $cpu = Measure-SigCpuConsistency -Seconds 10 -Runs 5
    $disk = Measure-SigDiskSpd

    $result = [PSCustomObject]@{
        SigmaVersion = $script:SigmaVersion
        BenchmarkSchemaVersion = $script:BenchmarkSchemaVer
        Label = $Label
        Timestamp = (Get-Date).ToString('o')
        IdleGate = $idle                                     # Fix #20
        Environment = $env
        Machine = (Get-SigMachineProfile)
        CPU = $cpu
        Disk = $disk
    }
    $file = Join-Path $script:SigmaBm "$Label.json"
    $result | ConvertTo-Json -Depth 8 | Set-Content $file -Encoding UTF8
    Write-Sig "Benchmark saved: $file" -Level OK -Tag 'BM'
    return $result
}

function Compare-SigBenchmarks {
    # Fix #21: environment guards. Fix #22: split CPU/Disk validity.
    param(
        [Parameter(Mandatory)][string]$BeforeLabel,
        [Parameter(Mandatory)][string]$AfterLabel
    )
    $bFile = Join-Path $script:SigmaBm "$BeforeLabel.json"
    $aFile = Join-Path $script:SigmaBm "$AfterLabel.json"
    if (-not (Test-Path $bFile) -or -not (Test-Path $aFile)) { throw "Missing benchmark file(s)" }
    $b = Get-Content $bFile -Raw | ConvertFrom-Json
    $a = Get-Content $aFile -Raw | ConvertFrom-Json

    $cpuWarnings = @()
    $diskWarnings = @()
    $cpuValid = $true; $diskValid = $true
    $cpuInvalidReason = $null; $diskInvalidReason = $null

    if ($b.BenchmarkSchemaVersion -ne $a.BenchmarkSchemaVersion) {
        $cpuValid = $false; $diskValid = $false
        $cpuInvalidReason = "Benchmark schema changed ($($b.BenchmarkSchemaVersion) → $($a.BenchmarkSchemaVersion))"
        $cpuWarnings += $cpuInvalidReason; $diskWarnings += $cpuInvalidReason
    }
    if ($b.SigmaVersion -ne $a.SigmaVersion) {
        $cpuValid = $false; $diskValid = $false
        $cpuInvalidReason = "Sigma version changed"
        $cpuWarnings += $cpuInvalidReason; $diskWarnings += $cpuInvalidReason
    }
    # Fix #21: environment guards
    if ($null -ne $b.Environment.OnAc -and $null -ne $a.Environment.OnAc -and $b.Environment.OnAc -ne $a.Environment.OnAc) {
        $cpuValid = $false
        $cpuInvalidReason = "AC/battery state differs (before=$($b.Environment.OnAc) after=$($a.Environment.OnAc))"
        $cpuWarnings += $cpuInvalidReason
    }
    if ($b.Environment.PowerPlan -ne $a.Environment.PowerPlan) {
        $cpuWarnings += "Power plan changed (before=$($b.Environment.PowerPlan) after=$($a.Environment.PowerPlan))"
    }
    if ($b.Disk.Available -and $a.Disk.Available) {
        if ($b.Disk.EngineVersion -ne $a.Disk.EngineVersion) {
            $diskValid = $false
            $diskInvalidReason = "DiskSpd version changed ($($b.Disk.EngineVersion) → $($a.Disk.EngineVersion))"
            $diskWarnings += $diskInvalidReason
        } elseif ($b.Disk.EngineVersion -eq 'unknown' -or $a.Disk.EngineVersion -eq 'unknown') {
            $diskWarnings += 'DiskSpd version unknown — disk comparison not considered reproducible'
        }
    }

    $cpuCI = Get-SigBootstrapCI -A ([double[]]$b.CPU.AllOpsPerSec) -B ([double[]]$a.CPU.AllOpsPerSec)
    $deltaPct = $null
    if ($b.CPU.MedianOpsPerSec -gt 0) { $deltaPct = [math]::Round(100 * ($cpuCI.PointEstimate / $b.CPU.MedianOpsPerSec), 2) }

    [PSCustomObject]@{
        BeforeLabel=$BeforeLabel; AfterLabel=$AfterLabel
        CPUComparisonValid = $cpuValid; CPUInvalidReason = $cpuInvalidReason; CPUWarnings = $cpuWarnings
        DiskComparisonValid = $diskValid; DiskInvalidReason = $diskInvalidReason; DiskWarnings = $diskWarnings
        CPU_Before_Median = $b.CPU.MedianOpsPerSec
        CPU_After_Median  = $a.CPU.MedianOpsPerSec
        CPU_Delta         = $cpuCI.PointEstimate
        CPU_DeltaPct      = $deltaPct
        CPU_CI_Low        = $cpuCI.CI_Low
        CPU_CI_High       = $cpuCI.CI_High
        CPU_StatisticallySignificant = $cpuCI.Significant
        CPU_Direction     = $cpuCI.Direction
        CPU_Reason        = $cpuCI.Reason
        CPU_Before_CV     = $b.CPU.CV_Percent
        CPU_After_CV      = $a.CPU.CV_Percent
        IdleGate_Before = $b.IdleGate
        IdleGate_After  = $a.IdleGate
        Disk = [PSCustomObject]@{ Before=$b.Disk; After=$a.Disk }
    }
}

# -----------------------------------------------------------------------------
# SECTION 12 - Optimization catalog
# -----------------------------------------------------------------------------

function Get-SigOptimizationCatalog {
    @(
        @{
            Id='GameMode_Enable'; Category='Gaming'; Title='Enable Game Mode'
            Risk='Low'; Impact='Low/Med'; RequiresReboot=$false
            AppliesTo = { param($ctx) $ctx.OS.Build -ge 10240 }
            Apply = { param($TxId)
                Invoke-SigRegistryWrite -TxId $TxId -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type 'DWord' | Out-Null
            }
        },
        @{
            Id='MenuShowDelay_Low'; Category='Responsiveness'; Title='Reduce menu show delay to 100ms'
            Risk='Low'; Impact='Cosmetic'; RequiresReboot=$false
            AppliesTo = { param($ctx) $true }
            Apply = { param($TxId)
                Invoke-SigRegistryWrite -TxId $TxId -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '100' -Type 'String' | Out-Null
            }
        },
        @{
            Id='ShowFileExtensions'; Category='Usability'; Title='Show file extensions in Explorer'
            Risk='Low'; Impact='Security'; RequiresReboot=$false
            AppliesTo = { param($ctx) $true }
            Apply = { param($TxId)
                Invoke-SigRegistryWrite -TxId $TxId -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Type 'DWord' | Out-Null
            }
        },
        @{
            Id='FastStartup_Off_Laptop'; Category='Reliability'; Title='Disable Fast Startup (laptop)'
            Risk='Low'; Impact='Reliability'; RequiresReboot=$true
            AppliesTo = { param($ctx) $ctx.Hardware.IsLaptop }
            Apply = { param($TxId)
                Invoke-SigRegistryWrite -TxId $TxId `
                    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
                    -Name 'HiberbootEnabled' -Value 0 -Type 'DWord' | Out-Null
            }
        },
        @{
            Id='FastStartup_Off_Desktop'; Category='Reliability'; Title='Disable Fast Startup (desktop)'
            Risk='Low'; Impact='Reliability'; RequiresReboot=$true
            AppliesTo = { param($ctx) -not $ctx.Hardware.IsLaptop }
            Apply = { param($TxId)
                Invoke-SigRegistryWrite -TxId $TxId `
                    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
                    -Name 'HiberbootEnabled' -Value 0 -Type 'DWord' | Out-Null
            }
        },
        @{
            Id='Telemetry_Minimum'; Category='Privacy'; Title='Diagnostic data → Required only (value 1)'
            Risk='Low'; Impact='Privacy'; RequiresReboot=$false
            AppliesTo = { param($ctx) $ctx.OS.Build -ge 10240 }
            Apply = { param($TxId)
                Invoke-SigRegistryWrite -TxId $TxId `
                    -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
                    -Name 'AllowTelemetry' -Value 1 -Type 'DWord' | Out-Null
            }
        },
        @{
            Id='DisableLastAccess'; Category='Storage'; Title='Disable NTFS last-access timestamp'
            Risk='Low'; Impact='Storage'; RequiresReboot=$true
            AppliesTo = { param($ctx) @($ctx.Storage | Where-Object { $_.Media -eq 'SSD' }).Count -gt 0 }
            Apply = { param($TxId)
                Invoke-SigFsutilWrite -TxId $TxId -Setting 'disablelastaccess' -NewValue '1' | Out-Null
            }
        }
    )
}

function Get-SigContext {
    param($HardwareInventory)
    $os = Get-CimInstance Win32_OperatingSystem
    [PSCustomObject]@{
        Hardware = $HardwareInventory.Profile
        Storage  = $HardwareInventory.Storage
        OS = [PSCustomObject]@{ Caption=$os.Caption; Build=[int]$os.BuildNumber; Version=$os.Version }
    }
}

function Invoke-SigOptimization {
    # Fix #16: SigmaCriticalMutationException halts the batch immediately.
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [switch]$DryRun
    )
    $hw = Get-SigHardwareInventory
    $ctx = Get-SigContext -HardwareInventory $hw
    $catalog = Get-SigOptimizationCatalog

    if ($DryRun) {
        foreach ($id in $Ids) {
            $opt = $catalog | Where-Object { $_.Id -eq $id }
            if (-not $opt) { continue }
            if (-not (& $opt.AppliesTo $ctx)) { continue }
            Write-Host "  [DRY] $($opt.Title)  [Risk:$($opt.Risk)] Reboot=$($opt.RequiresReboot)" -ForegroundColor Cyan
        }
        return [PSCustomObject]@{ TransactionId=$null; Applied=@(); RequiresReboot=$false; RecoveryRequired=$false }
    }

    $txId = Start-SigTransaction -Name 'optimize'
    Set-SigTxState -TxId $txId -State 'Applying'
    $applied = @()
    $failed = 0
    $needsReboot = $false
    $appliedIds = @()
    $recoveryRequired = $false

    foreach ($id in $Ids) {
        $opt = $catalog | Where-Object { $_.Id -eq $id }
        if (-not $opt) { Write-Sig "Unknown optimization: $id" -Level WARN -Tag 'OPT'; continue }
        if (-not (& $opt.AppliesTo $ctx)) { Write-Sig "Skip (not applicable): $($opt.Title)" -Tag 'OPT'; continue }
        try {
            & $opt.Apply $txId
            if ($opt.RequiresReboot) { $needsReboot = $true }
            $applied += [PSCustomObject]@{ Id=$id; Title=$opt.Title; RequiresReboot=$opt.RequiresReboot; Time=(Get-Date) }
            $appliedIds += $id
            Write-Sig "Applied: $($opt.Title)" -Level OK -Tag 'OPT'
        } catch [SigmaCriticalMutationException] {
            Write-Sig "CRITICAL: $_ — halting batch." -Level ERROR -Tag 'OPT'
            Add-SigError "Critical: $id — $_"
            $failed++
            $recoveryRequired = $true
            break
        } catch {
            Write-Sig "Apply failed: $($opt.Title) — $_" -Level ERROR -Tag 'OPT'
            Add-SigError "Apply failed: $id — $_"
            $failed++
        }
    }

    if ($recoveryRequired) {
        Set-SigTxState -TxId $txId -State 'RecoveryRequired' -Applied $applied.Count -Failed $failed `
            -RequiresReboot $needsReboot -RecoveryRequired $true -Optimizations $appliedIds
    } elseif ($failed -eq 0 -and $applied.Count -gt 0) {
        Set-SigTxState -TxId $txId -State 'Applied' -Applied $applied.Count -Failed 0 `
            -RequiresReboot $needsReboot -RecoveryRequired $false -Optimizations $appliedIds
    } elseif ($applied.Count -gt 0) {
        Set-SigTxState -TxId $txId -State 'PartiallyApplied' -Applied $applied.Count -Failed $failed `
            -RequiresReboot $needsReboot -RecoveryRequired $false -Optimizations $appliedIds
    } else {
        Set-SigTxState -TxId $txId -State 'PartiallyApplied' -Applied 0 -Failed $failed `
            -RequiresReboot $false -RecoveryRequired $false -Optimizations @()
    }

    Write-SigJournalHash -TxId $txId

    [PSCustomObject]@{ TransactionId=$txId; Applied=$applied; RequiresReboot=$needsReboot; RecoveryRequired=$recoveryRequired }
}

# -----------------------------------------------------------------------------
# SECTION 13 - Collectors
# -----------------------------------------------------------------------------

function Get-SigResults_GroupA {
    $out = New-Object System.Collections.ArrayList

    # Cat 1
    $nt = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $os = Get-CimInstance Win32_OperatingSystem
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -EA SilentlyContinue | Select-Object -First 1
    $findings = @()
    if ($lic -and $lic.LicenseStatus -ne 1) { $findings += "Windows not activated (status $($lic.LicenseStatus))" }
    $status = 'OK'; if ($findings.Count) { $status = 'WARN' }
    $null = $out.Add((New-Evidence -DetectorId 'OS_INSTALL_001' -Category 1 -Status $status -Severity 3 -Confidence 0.95 -Subject 'Installation' -Finding ($findings -join '; ') -EvidenceLines $findings -Data @{
        Edition=$nt.EditionID; Build="$($os.BuildNumber).$($nt.UBR)"
        Activation=$(if ($lic) { $lic.LicenseStatus } else { $null })
    }))

    # Cat 2
    $sd = "$env:WINDIR\SoftwareDistribution\Download"
    $sdMB = 0
    if (Test-Path $sd) {
        $size = Get-ChildItem $sd -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum
        if ($null -ne $size.Sum) { $sdMB = [math]::Round($size.Sum / 1MB, 1) }
    }
    $pending = 0
    try { $ss = New-Object -ComObject Microsoft.Update.Session; $se = $ss.CreateUpdateSearcher(); $pending = $se.Search("IsInstalled=0 and IsHidden=0").Updates.Count } catch { }
    $ev = Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WindowsUpdateClient'} -MaxEvents 30 -EA SilentlyContinue
    $fails = ($ev | Where-Object { $_.Id -in 20,16 }).Count
    $findings = @()
    if ($sdMB -gt 5000) { $findings += "SoftwareDistribution cache $sdMB MB" }
    if ($pending -gt 10) { $findings += "$pending pending updates" }
    if ($fails -gt 3)   { $findings += "$fails recent update failures" }
    $wuStatus = 'OK'; if ($findings.Count) { $wuStatus = 'WARN' }
    $null = $out.Add((New-Evidence -DetectorId 'WU_STATE_001' -Category 2 -Status $wuStatus -Severity 3 -Confidence 0.95 -Subject 'Windows Update' -Finding ($findings -join '; ') -EvidenceLines $findings -Data @{
        CacheMB=$sdMB; Pending=$pending; Failures=$fails
    }))

    # Cat 3
    $allDrv = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName }
    $old = $allDrv | Where-Object { $_.DriverDate -and ([datetime]$_.DriverDate) -lt (Get-Date).AddYears(-3) -and $_.DeviceName -match 'Display|Network|Audio|Storage' }
    $unsigned = $allDrv | Where-Object { -not $_.IsSigned }
    $drvSeverity = 0; $drvStatus = 'OK'; $findings = @()
    if ($old.Count) { $findings += "$($old.Count) display/network/audio/storage drivers older than 3 years (informational)"; $drvStatus = 'INFO' }
    if ($unsigned.Count) { $findings += "$($unsigned.Count) unsigned drivers"; $drvStatus = 'WARN'; $drvSeverity = 4 }
    $null = $out.Add((New-Evidence -DetectorId 'DRV_AGE_001' -Category 3 -Status $drvStatus -Severity $drvSeverity -Confidence 0.9 -Subject 'Drivers' -Finding ($findings -join '; ') -EvidenceLines $findings -Data @{ Total=$allDrv.Count; Old=$old; Unsigned=$unsigned }))

    # Cat 4
    $prob = Get-PnpDevice -PresentOnly -EA SilentlyContinue | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' }
    $probSeverity = 0; if ($prob) { $probSeverity = 6 }
    $probStatus = 'OK'; if ($prob) { $probStatus = 'WARN' }
    $probFinding = 'No problem devices'; if ($prob) { $probFinding = "$($prob.Count) problem devices" }
    $null = $out.Add((New-Evidence -DetectorId 'DEVMGR_PROBLEM_001' -Category 4 -Status $probStatus -Severity $probSeverity -Confidence 0.98 -Subject 'Device Manager' -Finding $probFinding -EvidenceLines @($prob | ForEach-Object { "$($_.FriendlyName): $($_.ProblemDescription)" }) -Data @{ Problems=$prob }))

    # Cat 5
    $efiInfo = Test-SigEfiSystemPresent
    $sb = $null; try { $sb = Confirm-SecureBootUEFI -EA Stop } catch { }
    $tpm = $null; try { $tpm = Get-Tpm -EA Stop } catch { }
    $findings = @()
    if ($sb -eq $false) { $findings += "Secure Boot disabled" }
    if ($tpm -and -not $tpm.TpmReady) { $findings += "TPM present but not ready" }
    if ($efiInfo.IsUefi -and -not $efiInfo.HasEfi) { $findings += "UEFI firmware but no EFI System Partition" }
    $fwStatus = 'OK'; if ($findings.Count) { $fwStatus = 'WARN' }
    $null = $out.Add((New-Evidence -DetectorId 'FW_STATE_001' -Category 5 -Status $fwStatus -Severity 4 -Confidence 0.95 -Subject 'Firmware' -Finding ($findings -join '; ') -EvidenceLines $findings -Data @{
        IsUefi=$efiInfo.IsUefi; HasEfiPartition=$efiInfo.HasEfi; SecureBoot=$sb
        TPM=$(if ($tpm) { @{ Present=$tpm.TpmPresent; Ready=$tpm.TpmReady } } else { $null })
    }))

    return $out
}

function Get-SigResults_GroupB {
    $out = New-Object System.Collections.ArrayList

    # Cat 6 (WinRE model v0.8)
    $winreState = Get-SigWinReState
    $efiInfo = Test-SigEfiSystemPresent
    $fastStart = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -EA SilentlyContinue).HiberbootEnabled
    $findings = @(); $status = 'OK'; $severity = 0
    if ($winreState.EnabledKnown -and -not $winreState.Enabled) {
        $findings += "WinRE disabled"; $status='WARN'; $severity=4
    } elseif (-not $winreState.EnabledKnown) {
        if ($winreState.InstalledKnown -and $winreState.Installed) {
            $findings += "WinRE installed, but enabled state could not be verified ($($winreState.Method))"
        } else {
            $findings += "WinRE state could not be verified"
        }
        $status='INFO'
    }
    $null = $out.Add((New-Evidence -DetectorId 'BOOT_STATE_001' -Category 6 -Status $status -Severity $severity -Confidence 0.9 -Subject 'Boot' -Finding ($findings -join '; ') -EvidenceLines $findings -Data @{
        WinReInstalledKnown=$winreState.InstalledKnown; WinReInstalled=$winreState.Installed
        WinReEnabledKnown=$winreState.EnabledKnown;   WinReEnabled=$winreState.Enabled
        WinReConfiguredKnown=$winreState.ConfiguredKnown; WinReConfigured=$winreState.Configured
        WinReMethod=$winreState.Method; WinReConfidence=$winreState.Confidence
        IsUefi=$efiInfo.IsUefi; HasEfi=$efiInfo.HasEfi; FastStartup=$fastStart
    }))

    # Cat 7 (Fix #11, #12)
    $dumps = Get-ChildItem "$env:SystemRoot\Minidump" -Filter '*.dmp' -EA SilentlyContinue | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-30) }
    $wheaEvents = @(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=(Get-Date).AddDays(-30)} -EA SilentlyContinue)
    $kp41 = Get-WinEvent -FilterHashtable @{LogName='System';Id=41;StartTime=(Get-Date).AddDays(-30)} -EA SilentlyContinue

    # Heuristic classification (language-dependent)
    $wheaFatal = @($wheaEvents | Where-Object { $_.Message -match 'fatal|unrecoverable|uncorrected|Machine Check|MCE' })
    $wheaCorrected = @($wheaEvents | Where-Object { $_.Message -match 'corrected' -or $_.Id -in 17,18,19,20 })
    # Fix #12: unclassified bucket
    $wheaOther = @($wheaEvents | Where-Object { $_ -notin $wheaFatal -and $_ -notin $wheaCorrected })

    $findings = @()
    if ($dumps.Count) { $findings += "$($dumps.Count) minidumps (30d)" }
    if ($wheaEvents.Count) {
        $findings += "$($wheaEvents.Count) WHEA events (fatal=$($wheaFatal.Count) corrected=$($wheaCorrected.Count) unclassified=$($wheaOther.Count)) [heuristic classification]"
    }
    if ($kp41.Count)  { $findings += "$($kp41.Count) unexpected shutdowns (Kernel-Power 41)" }

    $stabStatus = 'OK'; $stabSeverity = 0
    if ($wheaFatal.Count)      { $stabStatus='FAIL'; $stabSeverity=9 }
    elseif ($dumps.Count)      { $stabStatus='FAIL'; $stabSeverity=7 }
    elseif ($kp41.Count -ge 3) { $stabStatus='WARN'; $stabSeverity=5 }
    elseif ($wheaCorrected.Count) { $stabStatus='WARN'; $stabSeverity=4 }
    elseif ($wheaOther.Count)  { $stabStatus='WARN'; $stabSeverity=4 }   # Fix #12
    elseif ($kp41.Count -eq 1) { $stabStatus='INFO'; $stabSeverity=2 }

    $null = $out.Add((New-Evidence -DetectorId 'STAB_BSOD_001' -Category 7 -Status $stabStatus -Severity $stabSeverity -Confidence 0.85 -Subject 'BSOD' -Finding ($findings -join '; ') -EvidenceLines $findings -Data @{
        Minidumps=$dumps | Select-Object Name,LastWriteTime
        WHEA_Total=$wheaEvents.Count
        WHEA_Fatal=$wheaFatal.Count
        WHEA_Corrected=$wheaCorrected.Count
        WHEA_Unclassified=$wheaOther.Count
        WHEA_Classification='heuristic (language-dependent)'
        KernelPower41=$kp41 | Select-Object -First 10 TimeCreated
    }))

    # Cat 8
    $top = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Name,Id,@{n='RAM_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},@{n='CPU_s';e={[math]::Round($_.CPU,1)}}
    $startup = Get-CimInstance Win32_StartupCommand -EA SilentlyContinue
    $null = $out.Add((New-Evidence -DetectorId 'PERF_TOP_001' -Category 8 -Status 'INFO' -Severity 0 -Confidence 1.0 -Subject 'Processes' -Finding "$($top.Count) top processes" -Data @{ Top=$top; StartupCount=$startup.Count }))

    # Cat 9
    $cpu = Get-CimInstance Win32_Processor
    $plan = (powercfg /getactivescheme) -join ''
    $null = $out.Add((New-Evidence -DetectorId 'CPU_STATE_001' -Category 9 -Status 'INFO' -Severity 0 -Confidence 1.0 -Subject 'CPU' -Finding "$($cpu.Name)" -Data @{ Cores=$cpu.NumberOfCores; Threads=$cpu.NumberOfLogicalProcessors; ActivePlan=$plan }))

    return $out
}

# -----------------------------------------------------------------------------
# SECTION 14 - Report
# -----------------------------------------------------------------------------

function New-SigHtmlReport {
    param(
        [object[]]$Evidence, [object]$Hardware, [object]$Dpc, [object]$Correlations,
        [string]$Path = (Join-Path $script:SigmaRpt ("report-{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
    )
    Add-Type -AssemblyName System.Web -EA SilentlyContinue
    $ok=0; $warn=0; $fail=0
    foreach ($e in $Evidence) { switch ($e.Status) { 'OK'{$ok++} 'WARN'{$warn++} 'FAIL'{$fail++} } }
    $rows = foreach ($e in $Evidence) {
        $color = '#888'
        switch ($e.Status) { 'OK'{$color='#6bff8f'} 'WARN'{$color='#ffd93b'} 'FAIL'{$color='#ff6b6b'} }
        $finding = [System.Web.HttpUtility]::HtmlEncode($e.Finding)
        $data = ''
        if ($e.Data) {
            $json = [System.Web.HttpUtility]::HtmlEncode(($e.Data | ConvertTo-Json -Depth 3 -Compress))
            $data = "<details><summary>data</summary><pre>$json</pre></details>"
        }
        "<tr style='border-left:4px solid $color'><td>$($e.Category)</td><td>$($e.DetectorId)</td><td>$($e.Status)</td><td>$([math]::Round($e.Confidence,2))</td><td>$finding</td><td>$data</td></tr>"
    }
    $corrRows = foreach ($c in $Correlations) {
        "<tr><td>$($c.CorrelationScore)</td><td>$($c.SuspectName)</td><td>$($c.SymptomName)</td><td>$($c.DeltaSec)s</td><td>$($c.Reasoning)</td></tr>"
    }
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>Sigma Report</title>
<style>
body{font-family:Segoe UI,sans-serif;background:#0f1115;color:#e6e6e6;padding:2em;line-height:1.4}
h1,h2{color:#8ab4f8} table{border-collapse:collapse;width:100%}
th,td{border:1px solid #333;padding:6px;text-align:left;vertical-align:top;font-size:13px}
th{background:#1f2330} pre{background:#0a0c10;padding:.5em;overflow:auto;max-height:280px;font-size:12px}
.good{color:#6bff8f} .warn{color:#ffd93b} .bad{color:#ff6b6b} .meta{color:#888;font-size:11px}
</style></head><body>
<h1>Sigma Performance Report</h1>
<p class="meta">Sigma $($script:SigmaVersion) | BenchmarkSchema $($script:BenchmarkSchemaVer) | TxSchema $($script:TransactionSchema) | Generated $(Get-Date)</p>
<p>OK: <span class='good'>$ok</span>  WARN: <span class='warn'>$warn</span>  FAIL: <span class='bad'>$fail</span></p>
<h2>Hardware</h2>
<pre>$([System.Web.HttpUtility]::HtmlEncode(($Hardware | ConvertTo-Json -Depth 4)))</pre>
<h2>DPC / ISR Screening</h2>
<pre>$([System.Web.HttpUtility]::HtmlEncode(($Dpc | ConvertTo-Json -Depth 4)))</pre>
<h2>Correlations (heuristic CorrelationScore)</h2>
<table><thead><tr><th>Score</th><th>Suspect</th><th>Symptom</th><th>Δt</th><th>Reasoning</th></tr></thead>
<tbody>$($corrRows -join "`n")</tbody></table>
<h2>Detections</h2>
<table><thead><tr><th>#</th><th>Detector</th><th>Status</th><th>Conf</th><th>Finding</th><th>Data</th></tr></thead>
<tbody>$($rows -join "`n")</tbody></table>
</body></html>
"@
    $html | Set-Content $Path -Encoding UTF8
    Write-Sig "Report: $Path" -Level OK -Tag 'RPT'
    return $Path
}

# -----------------------------------------------------------------------------
# SECTION 15 - Main flow
# -----------------------------------------------------------------------------

try {
    # --- Pending validation
    $pendingIds = Get-SigPendingTxIds
    $unresolvedPending = @()

    if ($pendingIds.Count -gt 0) {
        Write-Host ""
        Write-Host "========== PENDING VALIDATION ==========" -ForegroundColor Yellow
        Write-Host "$($pendingIds.Count) pending transaction(s): $($pendingIds -join ', ')" -ForegroundColor Yellow

        foreach ($pendingId in $pendingIds) {
            $pendingFile = Join-Path $script:SigmaPend "$pendingId.json"
            $pending = Get-Content $pendingFile -Raw | ConvertFrom-Json
            $metaFile = Join-Path (Join-Path $script:SigmaTx $pending.TxId) 'metadata.json'
            $meta = Get-Content $metaFile -Raw | ConvertFrom-Json

            if ($meta.RecoveryRequired) {
                Write-Host "  $pendingId is in RecoveryRequired — manual review needed." -ForegroundColor Red
                $unresolvedPending += $pendingId
                continue
            }

            if ($meta.RequiresReboot) {
                $lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
                if ($lastBoot -le [datetime]$pending.SavedAt) {
                    Write-Host "  $pendingId requires reboot before validation (not yet rebooted)." -ForegroundColor Yellow
                    $unresolvedPending += $pendingId
                    continue
                }
            }

            Write-Host ""
            Write-Host "  Validating $pendingId (baseline: $($pending.BaselineLabel))" -ForegroundColor Cyan
            $afterLabel = "after_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
            $null = Start-SigBenchmark -Label $afterLabel
            $cmp = Compare-SigBenchmarks -BeforeLabel $pending.BaselineLabel -AfterLabel $afterLabel

            Write-Host "  Δ median: $($cmp.CPU_Delta) ops/s ($($cmp.CPU_DeltaPct)%)" -ForegroundColor DarkGray
            Write-Host "  95% CI:   $($cmp.CPU_CI_Low) → $($cmp.CPU_CI_High)" -ForegroundColor DarkGray

            if (-not $cmp.CPUComparisonValid) {
                Write-Host "  RESULT: CPU COMPARISON INVALID ($($cmp.CPUInvalidReason))" -ForegroundColor Red
                Set-SigTxState -TxId $pending.TxId -State 'ValidatedInconclusive'
            }
            elseif ($cmp.CPU_StatisticallySignificant -and $cmp.CPU_Direction -eq 'Improvement') {
                Write-Host "  RESULT: SUPPORTED IMPROVEMENT" -ForegroundColor Green
                Set-SigTxState -TxId $pending.TxId -State 'ValidatedImprovement'
            } elseif ($cmp.CPU_StatisticallySignificant -and $cmp.CPU_Direction -eq 'Regression') {
                Write-Host "  RESULT: SUPPORTED REGRESSION" -ForegroundColor Red
                Set-SigTxState -TxId $pending.TxId -State 'ValidatedRegression'
                $rb = Read-Host "  Rollback $($pending.TxId)? (Y/N)"
                if ($rb -in 'Y','y') { Restore-SigTransaction -TxId $pending.TxId }
            } else {
                Write-Host "  RESULT: INCONCLUSIVE ($($cmp.CPU_Reason))" -ForegroundColor Yellow
                Set-SigTxState -TxId $pending.TxId -State 'ValidatedInconclusive'
            }
            Clear-SigPendingValidation -TxId $pending.TxId
        }

        if ($unresolvedPending.Count -gt 0) {
            Write-Host ""
            Write-Host "Unresolved transactions remain: $($unresolvedPending -join ', ')" -ForegroundColor Yellow
            Write-Host "Resolve them before starting another optimization session." -ForegroundColor Yellow
            Release-SigMutex
            exit 0
        }

        Write-Host ""
        $continue = Read-Host "Pending validation(s) handled. Start a new Sigma session? (Y/N)"
        if ($continue -notin 'Y','y') { Release-SigMutex; Write-Host "Exiting." -ForegroundColor Cyan; exit 0 }
    }

    # --- Normal flow
    Write-Host ""
    Write-Host "========== DISCOVER ==========" -ForegroundColor Green
    $hw = Get-SigHardwareInventory
    $ctx = Get-SigContext -HardwareInventory $hw
    Write-Host "  Machine: $($hw.Profile.Manufacturer) $($hw.Profile.Model)" -ForegroundColor DarkGray
    Write-Host "  CPU:     $($hw.Profile.CPUName)  (LikelyHybrid: $($hw.Profile.LikelyHybrid))" -ForegroundColor DarkGray
    Write-Host "  RAM:     $($hw.Profile.TotalRAMGB) GB" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "========== DETECT ==========" -ForegroundColor Green
    $evidence = New-Object System.Collections.ArrayList
    foreach ($fn in 'Get-SigResults_GroupA','Get-SigResults_GroupB') {
        Write-Host "  > $fn ..." -NoNewline
        try {
            $r = & $fn
            foreach ($e in $r) { $null = $evidence.Add($e) }
            Write-Host " $($r.Count) results" -ForegroundColor Green
        } catch {
            Write-Host " ERROR: $_" -ForegroundColor Red
            Add-SigError "$fn failed: $_"
        }
    }

    Write-Host ""
    Write-Host "========== MEASURE ==========" -ForegroundColor Green
    Write-Host "  > DPC/ISR screening (15s)..." -NoNewline
    $dpc = Get-SigCounterSnapshot -Seconds 15 -IntervalSeconds 1
    Write-Host " $($dpc.Verdict)" -ForegroundColor $(if ($dpc.Verdict -match 'CRITICAL') {'Red'} elseif ($dpc.Verdict -match 'ELEVATED') {'Yellow'} else {'Green'})
    if ($dpc.Verdict -match 'CRITICAL|ELEVATED') {
        $ans = Read-Host "  Capture 30s ETW trace? (Y/N)"
        if ($ans -in 'Y','y') {
            $trace = Join-Path $script:SigmaData ("etw-{0}.etl" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
            $t = Start-SigEtwCapture -OutputPath $trace -DurationSeconds 30
            if ($t) { Write-Host "  Open in WPA: wpa.exe '$t'" -ForegroundColor Cyan }
        }
    }

    Write-Host ""
    Write-Host "========== CORRELATE ==========" -ForegroundColor Green
    $events = Get-SigEventStream -HoursBack 72
    $correlations = Get-SigCorrelations -Events $events -WindowSeconds 30
    Write-Host "  Events: $($events.Count), correlations: $($correlations.Count)" -ForegroundColor DarkGray
    foreach ($c in ($correlations | Select-Object -First 5)) {
        Write-Host ("  [{0}] {1} → {2}  ({3}s before)" -f $c.CorrelationScore, $c.SuspectName, $c.SymptomName, $c.DeltaSec) -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "========== BASELINE BENCHMARK ==========" -ForegroundColor Green
    $baselineLabel = "baseline_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    $baseline = Start-SigBenchmark -Label $baselineLabel
    Write-Host "  CPU median: $($baseline.CPU.MedianOpsPerSec) ops/s  (CV $($baseline.CPU.CV_Percent)%)" -ForegroundColor DarkGray
    Write-Host "  Idle gate: passed=$($baseline.IdleGate.Passed) counters=$($baseline.IdleGate.CountersAvailable)" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "========== OPTIMIZE ==========" -ForegroundColor Green
    $catalog = Get-SigOptimizationCatalog
    $applicable = $catalog | Where-Object { & $_.AppliesTo $ctx }
    for ($i = 0; $i -lt $applicable.Count; $i++) {
        $rebootFlag = ''
        if ($applicable[$i].RequiresReboot) { $rebootFlag = ' [reboot]' }
        Write-Host ("  [{0}] {1}  (Risk: {2}){3}" -f ($i+1), $applicable[$i].Title, $applicable[$i].Risk, $rebootFlag) -ForegroundColor White
    }
    Write-Host ""
    $optChoice = Read-Host "Apply optimizations? comma-separated numbers, 'all', or 'none'"

    $txId = $null
    $txRequiresReboot = $false
    $txRecoveryRequired = $false
    if ($optChoice -and $optChoice -ne 'none') {
        $ids = @()
        if ($optChoice -eq 'all') { $ids = $applicable.Id }
        else {
            foreach ($tok in ($optChoice -split ',')) {
                $n = 0
                if ([int]::TryParse($tok.Trim(), [ref]$n)) {
                    if ($n -ge 1 -and $n -le $applicable.Count) { $ids += $applicable[$n-1].Id }
                }
            }
        }
        $optResult = Invoke-SigOptimization -Ids $ids
        $txId = $optResult.TransactionId
        $txRequiresReboot = $optResult.RequiresReboot
        $txRecoveryRequired = $optResult.RecoveryRequired
    }

    Write-Host ""
    Write-Host "========== VALIDATE ==========" -ForegroundColor Green
    if ($txRecoveryRequired) {
        Write-Host "  Transaction is in RecoveryRequired. Skipping validation." -ForegroundColor Red
        Write-Host "  Restore with: Restore-SigTransaction -TxId '$txId'" -ForegroundColor Yellow
    } elseif ($txId) {
        if ($txRequiresReboot) {
            Write-Host "  Transaction includes reboot-required changes." -ForegroundColor Yellow
            $mode = Read-Host "  [R]eboot and validate, or [S]kip validation"
        } else {
            $mode = Read-Host "  [N]ow, [R]eboot-then-validate, or [S]kip validation"
        }

        if ($mode -in 'N','n' -and -not $txRequiresReboot) {
            $afterLabel = "after_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
            $null = Start-SigBenchmark -Label $afterLabel
            $cmp = Compare-SigBenchmarks -BeforeLabel $baselineLabel -AfterLabel $afterLabel
            Write-Host "  Δ median: $($cmp.CPU_Delta) ops/s ($($cmp.CPU_DeltaPct)%)" -ForegroundColor DarkGray
            if (-not $cmp.CPUComparisonValid) {
                Write-Host "  RESULT: CPU COMPARISON INVALID ($($cmp.CPUInvalidReason))" -ForegroundColor Red
                Set-SigTxState -TxId $txId -State 'ValidatedInconclusive'
            } elseif ($cmp.CPU_StatisticallySignificant -and $cmp.CPU_Direction -eq 'Improvement') {
                Write-Host "  RESULT: SUPPORTED IMPROVEMENT" -ForegroundColor Green
                Set-SigTxState -TxId $txId -State 'ValidatedImprovement'
            } elseif ($cmp.CPU_StatisticallySignificant -and $cmp.CPU_Direction -eq 'Regression') {
                Write-Host "  RESULT: SUPPORTED REGRESSION" -ForegroundColor Red
                Set-SigTxState -TxId $txId -State 'ValidatedRegression'
                $rb = Read-Host "  Rollback $txId now? (Y/N)"
                if ($rb -in 'Y','y') { Restore-SigTransaction -TxId $txId }
            } else {
                Write-Host "  RESULT: INCONCLUSIVE" -ForegroundColor Yellow
                Set-SigTxState -TxId $txId -State 'ValidatedInconclusive'
            }
        } elseif ($mode -in 'R','r') {
            Save-SigPendingValidation -TxId $txId -BaselineLabel $baselineLabel
            Set-SigTxState -TxId $txId -State 'ValidationPending'
            Write-Host "  Pending validation saved." -ForegroundColor Cyan
        } else {
            Write-Host "  Validation skipped." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  No optimizations applied." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "========== REPORT ==========" -ForegroundColor Green
    $reportPath = New-SigHtmlReport -Evidence $evidence.ToArray() -Hardware $hw -Dpc $dpc -Correlations $correlations
    Write-Host "  $reportPath" -ForegroundColor Cyan

    if (Test-Path $script:ErrorLog) {
        $ec = (Get-Content $script:ErrorLog | Measure-Object -Line).Lines
        if ($ec -gt 0) { Write-Host ""; Write-Host "[WARNING] $ec errors logged: $script:ErrorLog" -ForegroundColor Yellow }
        else { Remove-Item $script:ErrorLog -Force -EA SilentlyContinue }
    }

    Write-Host ""
    Write-Host "[SUCCESS] Sigma scan complete." -ForegroundColor Green
    if ($txId) { Write-Host "[INFO] Rollback: Restore-SigTransaction -TxId '$txId'" -ForegroundColor Cyan }
    Write-Host ""

    $rebootChoice = Read-Host "Press R to reboot, or Q to quit"
    if ($rebootChoice -in 'R','r') { shutdown /r /f /t 0 }
} finally {
    Release-SigMutex
}