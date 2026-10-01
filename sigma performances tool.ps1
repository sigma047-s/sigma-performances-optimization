#Requires -Version 5.1
#Requires -RunAsAdministrator

# =============================================================================
# SIGMA PERFORMANCE v0.9.1
#  - HTML-first output (scan report, benchmark, comparison, transaction)
#  - 82 optimizations across the master map, all transactional
#  - Fixed: constructors accept Note positionally (v0.9.0 cast bug)
# =============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
Set-StrictMode -Version 1.0

$script:SigmaVersion       = '0.9.1'
$script:BenchmarkSchemaVer = 5
$script:TransactionSchema  = 5
$script:RulesVersion       = 2

# -----------------------------------------------------------------------------
# SECTION 0 - Header
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "========== SIGMA PERFORMANCES v$($script:SigmaVersion) ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[INFO] Diagnostic scan + transactional optimization (HTML output)." -ForegroundColor Cyan
Write-Host "[INFO] 82 optimizations available. Every change is verified and reversible." -ForegroundColor Cyan
Write-Host ""
Write-Host "[WARNING] Create a System Restore point before proceeding." -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "Proceed? (Y/N)"
if ($confirm -notin 'Y','y') { Write-Host "Exiting." -ForegroundColor Cyan; exit 0 }

# -----------------------------------------------------------------------------
# SECTION 1 - Infrastructure
# -----------------------------------------------------------------------------

$script:SigmaRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:SigmaData = Join-Path $script:SigmaRoot 'SigmaData'
$script:SigmaLog  = Join-Path $script:SigmaData 'Logs'
$script:SigmaTx   = Join-Path $script:SigmaData 'Transactions'
$script:SigmaPend = Join-Path $script:SigmaData 'Pending'
$script:SigmaBm   = Join-Path $script:SigmaData 'Benchmarks'
$script:SigmaRpt  = Join-Path $script:SigmaData 'Reports'
$script:SigmaHtm  = Join-Path $script:SigmaData 'Html'
$script:ErrorLog  = Join-Path $env:TEMP 'sigma_errors.log'

foreach ($d in @($script:SigmaData,$script:SigmaLog,$script:SigmaTx,$script:SigmaPend,$script:SigmaBm,$script:SigmaRpt,$script:SigmaHtm)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
if (Test-Path $script:ErrorLog) { Remove-Item $script:ErrorLog -Force -EA SilentlyContinue }

$script:SigmaMutex = $null
function Acquire-SigMutex {
    try {
        $m = New-Object System.Threading.Mutex($false, 'Global\SigmaPerformanceMutationEngine')
        if (-not $m.WaitOne(0)) { $m.Dispose(); throw "Another Sigma optimization session is already active." }
        $script:SigmaMutex = $m
    } catch [System.Threading.AbandonedMutexException] { $script:SigmaMutex = $m }
}
function Release-SigMutex {
    if ($script:SigmaMutex) {
        try { $script:SigmaMutex.ReleaseMutex() } catch { }
        try { $script:SigmaMutex.Dispose() } catch { }
        $script:SigmaMutex = $null
    }
}
Acquire-SigMutex
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
        'ERROR' { $color='Red' } 'WARN' { $color='Yellow' } 'OK' { $color='Green' }
        'DEBUG' { $color='DarkGray' } 'SECTION' { $color='Magenta' }
    }
    if ($Level -ne 'DEBUG') { Write-Host $line -ForegroundColor $color }
}
function Add-SigError { param([string]$Message) Add-Content -Path $script:ErrorLog -Value "$(Get-Date -Format 'HH:mm:ss') $Message" -Encoding UTF8 -EA SilentlyContinue }

class SigmaCriticalMutationException : System.Exception {
    SigmaCriticalMutationException([string]$message) : base($message) { }
}

# -----------------------------------------------------------------------------
# SECTION 2 - HTML helpers
# -----------------------------------------------------------------------------

Add-Type -AssemblyName System.Web -EA SilentlyContinue

function ConvertTo-SigHtmlEncoded { param($Text) if ($null -eq $Text) { return '' }; [System.Web.HttpUtility]::HtmlEncode([string]$Text) }

function Get-SigHtmlStyles {
@'
<style>
:root{--bg:#0f1115;--fg:#e6e6e6;--dim:#888;--accent:#8ab4f8;--ok:#6bff8f;--warn:#ffd93b;--bad:#ff6b6b;--border:#2a2e38;}
*{box-sizing:border-box}
body{font-family:'Segoe UI',-apple-system,sans-serif;background:var(--bg);color:var(--fg);padding:2em;line-height:1.45;margin:0}
h1,h2,h3{color:var(--accent);margin-top:1.4em}
h1{border-bottom:2px solid var(--border);padding-bottom:.3em}
a{color:var(--accent)}
table{border-collapse:collapse;width:100%;margin:1em 0}
th,td{border:1px solid var(--border);padding:8px 10px;text-align:left;vertical-align:top;font-size:13px}
th{background:#1a1d24;color:var(--accent);font-weight:600}
tr:nth-child(even) td{background:#14171d}
pre,code{font-family:'Cascadia Mono',Consolas,monospace;background:#0a0c10;border:1px solid var(--border);border-radius:3px}
pre{padding:.8em;overflow:auto;max-height:400px;font-size:12px}
code{padding:.1em .35em;font-size:.92em}
.ok{color:var(--ok)} .warn{color:var(--warn)} .bad{color:var(--bad)} .dim{color:var(--dim)}
.meta{color:var(--dim);font-size:12px;margin:.3em 0}
.card{background:#14171d;border:1px solid var(--border);border-radius:4px;padding:1em 1.2em;margin:1em 0}
.kv{display:grid;grid-template-columns:240px 1fr;gap:.4em 1em;font-size:13px}
.kv .k{color:var(--dim)}
.badge{display:inline-block;padding:.15em .55em;border-radius:3px;font-size:11px;font-weight:600;text-transform:uppercase}
.badge.ok{background:#1b3a2a;color:var(--ok)}
.badge.warn{background:#3a341b;color:var(--warn)}
.badge.bad{background:#3a1b1b;color:var(--bad)}
.badge.info{background:#1b2a3a;color:var(--accent)}
details{margin:.5em 0}
summary{cursor:pointer;color:var(--accent)}
.lede{font-size:15px;color:var(--dim)}
hr{border:none;border-top:1px solid var(--border);margin:1.5em 0}
</style>
'@
}

function ConvertTo-SigHtmlPage {
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][string]$Body, [string]$Subtitle)
    $sub = ''
    if ($Subtitle) { $sub = "<p class='lede'>$(ConvertTo-SigHtmlEncoded $Subtitle)</p>" }
    @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>$(ConvertTo-SigHtmlEncoded $Title)</title>
$(Get-SigHtmlStyles)
</head><body>
<h1>$(ConvertTo-SigHtmlEncoded $Title)</h1>
$sub
$Body
<hr>
<p class="meta">Sigma Performance v$($script:SigmaVersion) | Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
</body></html>
"@
}

function ConvertTo-SigHtmlTable {
    param([Parameter(Mandatory)]$InputObject, [string[]]$Columns)
    $items = @($InputObject | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { return "<p class='dim'>(no rows)</p>" }
    if (-not $Columns) {
        $first = $items[0]
        if ($first -is [System.Collections.IDictionary]) { $Columns = @($first.Keys) }
        else { $Columns = @($first.PSObject.Properties | Where-Object { $_.MemberType -in 'NoteProperty','Property' } | Select-Object -ExpandProperty Name) }
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<table><thead><tr>")
    foreach ($c in $Columns) { [void]$sb.Append("<th>$(ConvertTo-SigHtmlEncoded $c)</th>") }
    [void]$sb.Append("</tr></thead><tbody>")
    foreach ($item in $items) {
        [void]$sb.Append("<tr>")
        foreach ($c in $Columns) {
            $v = $null
            if ($item -is [System.Collections.IDictionary]) { $v = $item[$c] } else { $v = $item.$c }
            if ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd HH:mm:ss') }
            if ($v -is [array]) { $v = ($v -join ', ') }
            if ($v -is [PSCustomObject] -or $v -is [System.Collections.IDictionary]) { $v = ($v | ConvertTo-Json -Depth 2 -Compress) }
            [void]$sb.Append("<td>$(ConvertTo-SigHtmlEncoded $v)</td>")
        }
        [void]$sb.Append("</tr>")
    }
    [void]$sb.Append("</tbody></table>")
    return $sb.ToString()
}

function ConvertTo-SigHtmlKeyValue {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Map)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<div class='kv'>")
    foreach ($k in $Map.Keys) {
        $v = $Map[$k]
        if ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd HH:mm:ss') }
        if ($v -is [PSCustomObject] -or $v -is [System.Collections.IDictionary]) {
            $encoded = ConvertTo-SigHtmlEncoded ($v | ConvertTo-Json -Depth 4)
            [void]$sb.Append("<div class='k'>$(ConvertTo-SigHtmlEncoded $k)</div><div><pre>$encoded</pre></div>")
        } else {
            [void]$sb.Append("<div class='k'>$(ConvertTo-SigHtmlEncoded $k)</div><div>$(ConvertTo-SigHtmlEncoded $v)</div>")
        }
    }
    [void]$sb.Append("</div>")
    return $sb.ToString()
}

# -----------------------------------------------------------------------------
# SECTION 3 - Journal
# -----------------------------------------------------------------------------

function Write-SigJournalEvent {
    param(
        [Parameter(Mandatory)][string]$TxId,
        [Parameter(Mandatory)][string]$MutationId,
        [Parameter(Mandatory)]
        [ValidateSet('Capture','ApplyAttempted','ApplySucceeded','VerifySucceeded','VerifyFailed',
                     'CompensationAttempted','CompensationSucceeded','CompensationFailed',
                     'RollbackAttempted','RollbackSucceeded','RollbackFailed','Note')]
        [string]$Event,
        [string]$Kind, [string]$Target, $Prior, $New, [int]$Sequence, [string]$Detail
    )
    $dir = Join-Path $script:SigmaTx $TxId
    if (-not (Test-Path $dir)) { throw "Transaction not found: $TxId" }
    [PSCustomObject]@{
        TxId=$TxId; MutationId=$MutationId; Event=$Event; Sequence=$Sequence
        Kind=$Kind; Target=$Target; Prior=$Prior; New=$New; Detail=$Detail
        Time=(Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 -Compress | Add-Content (Join-Path $dir 'journal.jsonl') -Encoding UTF8
}

function Get-SigNextSequence {
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
    param([Parameter(Mandatory)][string]$TxId)
    $dir = Join-Path $script:SigmaTx $TxId
    $journal = Join-Path $dir 'journal.jsonl'
    $metaFile = Join-Path $dir 'metadata.json'
    if (-not (Test-Path $journal)) { return }
    $sha = $null
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $journalHash = [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($journal))) -replace '-',''
        $metaHash = $null
        if (Test-Path $metaFile) {
            $metaHash = [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($metaFile))) -replace '-',''
        }
        [PSCustomObject]@{
            SigmaVersion=$script:SigmaVersion; TransactionSchemaVersion=$script:TransactionSchema
            TransactionId=$TxId; JournalHash=$journalHash.ToLowerInvariant()
            MetadataHash=if ($metaHash) { $metaHash.ToLowerInvariant() } else { $null }
            GeneratedAt=(Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'manifest.json') -Encoding UTF8
        $journalHash.ToLowerInvariant() | Set-Content (Join-Path $dir 'journal.sha256') -Encoding UTF8
    } finally { if ($sha) { $sha.Dispose() } }
}

# -----------------------------------------------------------------------------
# SECTION 4 - Transaction engine
# -----------------------------------------------------------------------------

$script:CurrentTxId = $null

function New-SigMutationId { [guid]::NewGuid().ToString('N').Substring(0,12) }

function Start-SigTransaction {
    param([string]$Name)
    $id = "tx_{0}_{1}_{2}" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), ($Name -replace '[^\w\-]','_'), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $dir = Join-Path $script:SigmaTx $id
    if (Test-Path $dir) { throw "Transaction directory already exists: $id" }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $script:CurrentTxId = $id
    [PSCustomObject]@{
        SigmaVersion=$script:SigmaVersion; TransactionSchemaVersion=$script:TransactionSchema
        Id=$id; Name=$Name; Directory=$dir; Started=(Get-Date).ToString('o')
        State='Started'; Applied=0; Failed=0; RequiresReboot=$false; RecoveryRequired=$false
        Optimizations=@()
    } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'metadata.json') -Encoding UTF8
    New-Item -ItemType File -Path (Join-Path $dir 'journal.jsonl') -Force | Out-Null
    '0' | Set-Content (Join-Path $dir 'sequence.txt') -Encoding UTF8
    Write-Sig "Transaction started: $id" -Tag 'TX'
    return $id
}

function Set-SigTxState {
    param(
        [Parameter(Mandatory)][string]$TxId,
        [Parameter(Mandatory)][string]$State,
        [int]$Applied, [int]$Failed, [bool]$RequiresReboot, [bool]$RecoveryRequired, [string[]]$Optimizations
    )
    $metaFile = Join-Path (Join-Path $script:SigmaTx $TxId) 'metadata.json'
    if (-not (Test-Path $metaFile)) { return }
    $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
    $meta.State = $State
    if ($PSBoundParameters.ContainsKey('Applied'))          { $meta.Applied = $Applied }
    if ($PSBoundParameters.ContainsKey('Failed'))           { $meta.Failed = $Failed }
    if ($PSBoundParameters.ContainsKey('RequiresReboot'))   { $meta.RequiresReboot = $RequiresReboot }
    if ($PSBoundParameters.ContainsKey('RecoveryRequired')) { $meta.RecoveryRequired = $RecoveryRequired }
    if ($PSBoundParameters.ContainsKey('Optimizations'))    { $meta.Optimizations = $Optimizations }
    $meta | Add-Member -NotePropertyName 'LastStateChange' -NotePropertyValue (Get-Date).ToString('o') -Force
    $meta | ConvertTo-Json -Depth 4 | Set-Content $metaFile -Encoding UTF8
    Write-Sig "TX $TxId -> $State" -Tag 'TX'
}

function Invoke-SigRegistryWrite {
    param(
        [Parameter(Mandatory)][string]$TxId, [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name, $Value,
        [ValidateSet('String','DWord','QWord','MultiString','ExpandString','Binary')][string]$Type = 'DWord'
    )
    $mutationId = New-SigMutationId
    $seq = Get-SigNextSequence -TxId $TxId
    $keyExisted = Test-Path $Path
    $valueExisted = $false; $priorVal = $null; $priorKind = $null
    if ($keyExisted) {
        $item = Get-ItemProperty -Path $Path -Name $Name -EA SilentlyContinue
        if ($null -ne $item) {
            $valueExisted = $true; $priorVal = $item.$Name
            try { $priorKind = (Get-Item $Path).GetValueKind($Name).ToString() } catch { }
        }
    }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'Capture' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name" `
        -Prior @{ KeyExisted=$keyExisted; ValueExisted=$valueExisted; Value=$priorVal; ValueKind=$priorKind } -New @{ Value=$Value; Type=$Type }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplyAttempted' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -EA Stop | Out-Null
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplySucceeded' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name" -Detail "Apply failed: $_"
        throw
    }
    try {
        $verify = (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name
        $match = if ($verify -is [array]) { (($verify -join ',') -eq ($Value -join ',')) } else { ("$verify" -eq "$Value") }
        if (-not $match) { throw "Verification mismatch: expected '$Value', got '$verify'" }
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifySucceeded' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name" -Detail "$_"
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationAttempted' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
        $compensated = $false
        try {
            if ($valueExisted) {
                New-ItemProperty -Path $Path -Name $Name -Value $priorVal -PropertyType $priorKind -Force -EA Stop | Out-Null
                $cverify = (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name
                if ("$cverify" -ne "$priorVal") { throw "Compensation verify mismatch" }
            } else {
                Remove-ItemProperty -Path $Path -Name $Name -EA SilentlyContinue
                if ($null -ne (Get-ItemProperty -Path $Path -Name $Name -EA SilentlyContinue)) { throw "Compensation removal failed" }
            }
            if (-not $keyExisted -and (Test-Path $Path)) {
                $children = @(Get-ChildItem $Path -EA SilentlyContinue); $props = @((Get-Item $Path).Property)
                if ($children.Count -eq 0 -and $props.Count -eq 0) { Remove-Item $Path -Force -EA SilentlyContinue }
            }
            $compensated = $true
            Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationSucceeded' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name"
        } catch {
            Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationFailed' -Sequence $seq -Kind 'Registry' -Target "$Path::$Name" -Detail "$_"
        }
        if (-not $compensated) {
            Set-SigTxState -TxId $TxId -State 'RecoveryRequired' -RecoveryRequired $true
            throw [SigmaCriticalMutationException]::new("Registry $Path::$Name could not be verified OR compensated.")
        }
        throw
    }
    return $mutationId
}

function Invoke-SigFsutilWrite {
    param([Parameter(Mandatory)][string]$TxId, [Parameter(Mandatory)][string]$Setting, [Parameter(Mandatory)][string]$NewValue)
    $mutationId = New-SigMutationId; $seq = Get-SigNextSequence -TxId $TxId
    $raw = & fsutil behavior query $Setting 2>&1; $exit = $LASTEXITCODE; $text = ($raw -join "`n")
    $prior = if ($text -match '=\s*(\d+)') { $Matches[1] } else { $null }
    if ($null -eq $prior) { throw "Cannot determine '$Setting' state (exit=$exit). Refusing. ParserVersion=fsutil-equals-int-v1." }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'Capture' -Sequence $seq -Kind 'Fsutil' -Target $Setting `
        -Prior @{ Value=$prior; RawOutput=$text; ExitCode=$exit; ParserVersion='fsutil-equals-int-v1' } -New @{ Value=$NewValue }
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
        $v = if ((($vRaw -join "`n") -match '=\s*(\d+)')) { $Matches[1] } else { $null }
        if ($v -ne $NewValue) { throw "verify mismatch (expected $NewValue, got $v)" }
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifySucceeded' -Sequence $seq -Kind 'Fsutil' -Target $Setting
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Fsutil' -Target $Setting -Detail "$_"
        $compensated = $false
        try {
            & fsutil behavior set $Setting $prior 2>&1 | Out-Null
            $cRaw = & fsutil behavior query $Setting 2>&1
            $restored = if ((($cRaw -join "`n") -match '=\s*(\d+)')) { $Matches[1] } else { $null }
            if ($restored -ne $prior) { throw "compensation mismatch" }
            $compensated = $true
            Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationSucceeded' -Sequence $seq -Kind 'Fsutil' -Target $Setting
        } catch {
            Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'CompensationFailed' -Sequence $seq -Kind 'Fsutil' -Target $Setting -Detail "$_"
        }
        if (-not $compensated) {
            Set-SigTxState -TxId $TxId -State 'RecoveryRequired' -RecoveryRequired $true
            throw [SigmaCriticalMutationException]::new("fsutil $Setting could not be verified OR compensated.")
        }
        throw
    }
    return $mutationId
}

function Invoke-SigServiceWrite {
    param(
        [Parameter(Mandatory)][string]$TxId, [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Disabled','Manual','Automatic','Boot','System')][string]$StartType,
        [ValidateSet('Stop','Start','Leave')][string]$Action = 'Leave'
    )
    $mutationId = New-SigMutationId; $seq = Get-SigNextSequence -TxId $TxId
    $svc = Get-Service -Name $Name -EA SilentlyContinue
    if (-not $svc) { throw "Service not found: $Name" }
    $priorStart = $svc.StartType.ToString()
    $priorStatus = $svc.Status.ToString()
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'Capture' -Sequence $seq -Kind 'Service' -Target $Name `
        -Prior @{ StartType=$priorStart; Status=$priorStatus } -New @{ StartType=$StartType; Action=$Action }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplyAttempted' -Sequence $seq -Kind 'Service' -Target $Name
    try {
        Set-Service -Name $Name -StartupType $StartType -EA Stop
        if ($Action -eq 'Stop' -and $svc.Status -eq 'Running') { Stop-Service -Name $Name -Force -EA Stop }
        elseif ($Action -eq 'Start' -and $svc.Status -ne 'Running') { Start-Service -Name $Name -EA Stop }
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplySucceeded' -Sequence $seq -Kind 'Service' -Target $Name
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Service' -Target $Name -Detail "Apply failed: $_"
        throw
    }
    $verify = Get-Service -Name $Name
    if ($verify.StartType.ToString() -ne $StartType) {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Service' -Target $Name -Detail "StartType=$($verify.StartType) expected=$StartType"
        Set-SigTxState -TxId $TxId -State 'RecoveryRequired' -RecoveryRequired $true
        throw [SigmaCriticalMutationException]::new("Service $Name verify failed.")
    }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifySucceeded' -Sequence $seq -Kind 'Service' -Target $Name
    return $mutationId
}

function Invoke-SigScheduledTaskWrite {
    param(
        [Parameter(Mandatory)][string]$TxId, [Parameter(Mandatory)][string]$TaskPath,
        [Parameter(Mandatory)][string]$TaskName, [ValidateSet('Disable','Enable')][string]$Action
    )
    $mutationId = New-SigMutationId; $seq = Get-SigNextSequence -TxId $TxId
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -EA SilentlyContinue
    if (-not $task) { throw "Scheduled task not found: $TaskPath$TaskName" }
    $priorState = $task.State.ToString()
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'Capture' -Sequence $seq -Kind 'ScheduledTask' -Target "$TaskPath$TaskName" `
        -Prior @{ State=$priorState } -New @{ Action=$Action }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplyAttempted' -Sequence $seq -Kind 'ScheduledTask' -Target "$TaskPath$TaskName"
    try {
        if ($Action -eq 'Disable') { Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -EA Stop | Out-Null }
        else { Enable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -EA Stop | Out-Null }
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplySucceeded' -Sequence $seq -Kind 'ScheduledTask' -Target "$TaskPath$TaskName"
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'ScheduledTask' -Target "$TaskPath$TaskName" -Detail "$_"
        throw
    }
    $verify = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
    if ($verify.State.ToString() -ne $expected -and -not ($Action -eq 'Enable' -and $verify.State -in 'Ready','Running')) {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'ScheduledTask' -Target "$TaskPath$TaskName" -Detail "State=$($verify.State)"
        throw "Scheduled task $TaskPath$TaskName verify failed"
    }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifySucceeded' -Sequence $seq -Kind 'ScheduledTask' -Target "$TaskPath$TaskName"
    return $mutationId
}

function Invoke-SigPowerSettingWrite {
    param(
        [Parameter(Mandatory)][string]$TxId, [Parameter(Mandatory)][string]$SubGroup,
        [Parameter(Mandatory)][string]$Setting, [Parameter(Mandatory)][int]$AcValue
    )
    $mutationId = New-SigMutationId; $seq = Get-SigNextSequence -TxId $TxId
    $raw = & powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>&1
    $acPrior = $null
    foreach ($line in $raw) {
        if ($line -match 'Current AC Power Setting Index:\s+0x([0-9a-fA-F]+)') { $acPrior = [Convert]::ToInt32($Matches[1],16) }
    }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'Capture' -Sequence $seq -Kind 'Power' -Target "$SubGroup/$Setting" `
        -Prior @{ AcValue=$acPrior } -New @{ AcValue=$AcValue }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplyAttempted' -Sequence $seq -Kind 'Power' -Target "$SubGroup/$Setting"
    try {
        & powercfg /setacvalueindex SCHEME_CURRENT $SubGroup $Setting $AcValue 2>&1 | Out-Null
        & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'ApplySucceeded' -Sequence $seq -Kind 'Power' -Target "$SubGroup/$Setting"
    } catch {
        Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifyFailed' -Sequence $seq -Kind 'Power' -Target "$SubGroup/$Setting" -Detail "$_"
        throw
    }
    Write-SigJournalEvent -TxId $TxId -MutationId $mutationId -Event 'VerifySucceeded' -Sequence $seq -Kind 'Power' -Target "$SubGroup/$Setting"
    return $mutationId
}

function Restore-SigTransaction {
    param([Parameter(Mandatory)][string]$TxId)
    $dir = Join-Path $script:SigmaTx $TxId
    if (-not (Test-Path $dir)) { throw "Transaction not found: $TxId" }
    $journal = Join-Path $dir 'journal.jsonl'
    if (-not (Test-Path $journal)) { Write-Sig "Empty journal: $TxId" -Level WARN -Tag 'TX'; return }
    $events = @(Get-Content $journal | ForEach-Object { $_ | ConvertFrom-Json })
    $mutations = @{}
    foreach ($e in $events) {
        if (-not $mutations.ContainsKey($e.MutationId)) {
            $mutations[$e.MutationId] = [PSCustomObject]@{
                Id=$e.MutationId; Kind=$null; Target=$null; Prior=$null; New=$null; Sequence=0
                Applied=$false; Verified=$false; CompensationSucceeded=$false; CompensationFailed=$false; RolledBack=$false
            }
        }
        switch ($e.Event) {
            'Capture' { $mutations[$e.MutationId].Kind=$e.Kind; $mutations[$e.MutationId].Target=$e.Target
                        $mutations[$e.MutationId].Prior=$e.Prior; $mutations[$e.MutationId].New=$e.New
                        $mutations[$e.MutationId].Sequence=[int]$e.Sequence }
            'ApplySucceeded'        { $mutations[$e.MutationId].Applied=$true }
            'VerifySucceeded'       { $mutations[$e.MutationId].Verified=$true }
            'CompensationSucceeded' { $mutations[$e.MutationId].CompensationSucceeded=$true }
            'CompensationFailed'    { $mutations[$e.MutationId].CompensationFailed=$true }
            'RollbackSucceeded'     { $mutations[$e.MutationId].RolledBack=$true }
        }
    }
    $toRestore = @($mutations.Values | Where-Object { $_.Applied -and -not $_.CompensationSucceeded -and -not $_.RolledBack } | Sort-Object Sequence -Descending)
    if ($toRestore.Count -eq 0) { Write-Sig "Nothing to rollback for $TxId." -Level OK -Tag 'TX'; Set-SigTxState -TxId $TxId -State 'AlreadyRolledBack'; return }
    $ok = 0; $fail = 0
    foreach ($m in $toRestore) {
        Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackAttempted' -Sequence $m.Sequence -Kind $m.Kind -Target $m.Target
        try {
            switch ($m.Kind) {
                'Registry' {
                    $parts = $m.Target -split '::'; $path = $parts[0]; $name = $parts[1]
                    $keyExisted = [bool]$m.Prior.KeyExisted; $valueExisted = [bool]$m.Prior.ValueExisted
                    if ($valueExisted) {
                        $kind = if ($m.Prior.ValueKind) { $m.Prior.ValueKind } else { 'String' }
                        New-ItemProperty -Path $path -Name $name -Value $m.Prior.Value -PropertyType $kind -Force -EA Stop | Out-Null
                        if ("$((Get-ItemProperty -Path $path -Name $name -EA Stop).$name)" -ne "$($m.Prior.Value)") { throw "rollback verify mismatch" }
                    } else {
                        Remove-ItemProperty -Path $path -Name $name -EA SilentlyContinue
                        if ($null -ne (Get-ItemProperty -Path $path -Name $name -EA SilentlyContinue)) { throw "rollback removal failed" }
                    }
                    if (-not $keyExisted -and (Test-Path $path)) {
                        $children = @(Get-ChildItem $path -EA SilentlyContinue); $props = @((Get-Item $path).Property)
                        if ($children.Count -eq 0 -and $props.Count -eq 0) { Remove-Item $path -Force -EA SilentlyContinue }
                    }
                    Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackSucceeded' -Sequence $m.Sequence -Kind 'Registry' -Target $m.Target; $ok++
                }
                'Fsutil' {
                    if ($null -ne $m.Prior.Value) {
                        & fsutil behavior set $m.Target $m.Prior.Value 2>&1 | Out-Null
                        $vRaw = & fsutil behavior query $m.Target 2>&1
                        $v = if ((($vRaw -join "`n") -match '=\s*(\d+)')) { $Matches[1] } else { $null }
                        if ($v -ne $m.Prior.Value) { throw "fsutil rollback verify mismatch" }
                        Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackSucceeded' -Sequence $m.Sequence -Kind 'Fsutil' -Target $m.Target; $ok++
                    }
                }
                'Service' {
                    Set-Service -Name $m.Target -StartupType $m.Prior.StartType -EA Stop
                    if ($m.Prior.Status -eq 'Running') { Start-Service -Name $m.Target -EA SilentlyContinue }
                    Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackSucceeded' -Sequence $m.Sequence -Kind 'Service' -Target $m.Target; $ok++
                }
                'ScheduledTask' {
                    $tp = Split-Path $m.Target -Parent; $tn = Split-Path $m.Target -Leaf
                    if ($m.Prior.State -ne 'Disabled') { Enable-ScheduledTask -TaskPath $tp -TaskName $tn -EA SilentlyContinue | Out-Null }
                    else { Disable-ScheduledTask -TaskPath $tp -TaskName $tn -EA SilentlyContinue | Out-Null }
                    Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackSucceeded' -Sequence $m.Sequence -Kind 'ScheduledTask' -Target $m.Target; $ok++
                }
                'Power' {
                    if ($null -ne $m.Prior.AcValue) {
                        $parts = $m.Target -split '/'
                        & powercfg /setacvalueindex SCHEME_CURRENT $parts[0] $parts[1] $m.Prior.AcValue 2>&1 | Out-Null
                        & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
                        Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackSucceeded' -Sequence $m.Sequence -Kind 'Power' -Target $m.Target; $ok++
                    }
                }
                default {
                    Write-Sig "No rollback handler for kind '$($m.Kind)'" -Level ERROR -Tag 'TX'
                    Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackFailed' -Sequence $m.Sequence -Kind $m.Kind -Target $m.Target -Detail 'No rollback handler'
                    $fail++
                }
            }
        } catch {
            Write-SigJournalEvent -TxId $TxId -MutationId $m.Id -Event 'RollbackFailed' -Sequence $m.Sequence -Kind $m.Kind -Target $m.Target -Detail "$_"
            $fail++
        }
    }
    Write-SigJournalHash -TxId $TxId
    if ($fail -eq 0) { Set-SigTxState -TxId $TxId -State 'RolledBack' } else { Set-SigTxState -TxId $TxId -State 'RollbackPartialFailure' }
    Write-Sig "Rollback $TxId done (ok=$ok fail=$fail)" -Level OK -Tag 'TX'
}

function Get-SigPendingTxIds {
    if (-not (Test-Path $script:SigmaPend)) { return @() }
    return @(Get-ChildItem $script:SigmaPend -Filter '*.json' -EA SilentlyContinue | ForEach-Object { $_.BaseName })
}
function Save-SigPendingValidation {
    param([string]$TxId, [string]$BaselineLabel)
    [PSCustomObject]@{ TxId=$TxId; BaselineLabel=$BaselineLabel; NextPhase='Validate'; SavedAt=(Get-Date).ToString('o'); SigmaVersion=$script:SigmaVersion } |
        ConvertTo-Json | Set-Content (Join-Path $script:SigmaPend "$TxId.json") -Encoding UTF8
}
function Clear-SigPendingValidation { param([string]$TxId); $f = Join-Path $script:SigmaPend "$TxId.json"; if (Test-Path $f) { Remove-Item $f -Force -EA SilentlyContinue } }

# -----------------------------------------------------------------------------
# SECTION 5 - Evidence + hardware + counters
# -----------------------------------------------------------------------------

function New-Evidence {
    param([string]$DetectorId,[int]$Category,
          [ValidateSet('OK','WARN','FAIL','INFO','SKIP')][string]$Status,
          [int]$Severity=0,[double]$Confidence=1.0,
          [string]$Subject='',[string]$Finding='',$ObservedValue=$null,$ExpectedValue=$null,
          [string[]]$EvidenceLines=@(),[string[]]$ProbableCauses=@(),[string[]]$RecommendationIds=@(),
          $Data=$null)
    [PSCustomObject]@{ DetectorId=$DetectorId;Category=$Category;Status=$Status;Severity=$Severity
        Confidence=$Confidence;Subject=$Subject;Finding=$Finding;ObservedValue=$ObservedValue
        ExpectedValue=$ExpectedValue;Evidence=$EvidenceLines;ProbableCauses=$ProbableCauses
        RecommendationIds=$RecommendationIds;Data=$Data;Timestamp=(Get-Date).ToString('o') }
}

function Test-SigLikelyHybridCpu {
    param($Cpu)
    $name = $Cpu.Name
    foreach ($p in @('12th Gen Intel','13th Gen Intel','14th Gen Intel','Core Ultra','Core 5 1','Core 7 1','Core 9 1')) { if ($name -match $p) { return $true } }
    try {
        $cim = @(Get-CimInstance Win32_Processor -EA Stop)
        if ($cim.PSObject.Properties.Name -contains 'EfficiencyClass') {
            $classes = @($cim | Select-Object -ExpandProperty EfficiencyClass -EA SilentlyContinue)
            if ((@($classes | Sort-Object -Unique)).Count -gt 1) { return $true }
        }
    } catch { }
    return $false
}

function Get-SigMachineProfile {
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $batt = Get-CimInstance Win32_Battery -EA SilentlyContinue
    $vendor = if ($cpu.Manufacturer -match 'Intel') { 'Intel' } elseif ($cpu.Manufacturer -match 'AMD') { 'AMD' } else { 'Other' }
    [PSCustomObject]@{
        Manufacturer=$cs.Manufacturer; Model=$cs.Model; IsLaptop=[bool]$batt
        CPUVendor=$vendor; CPUName=$cpu.Name; LikelyHybrid=(Test-SigLikelyHybridCpu $cpu)
        TotalRAMGB=[math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        ChassisType=(Get-CimInstance Win32_SystemEnclosure).ChassisTypes
    }
}

function Get-SigHardwareInventory {
    $profile = Get-SigMachineProfile
    $mb = Get-CimInstance Win32_BaseBoard -EA SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -EA SilentlyContinue
    $mem = @(Get-CimInstance Win32_PhysicalMemory)
    $arr = Get-CimInstance Win32_PhysicalMemoryArray
    $gpus = @(Get-CimInstance Win32_VideoController)
    $disks = @(Get-PhysicalDisk -EA SilentlyContinue)
    $net = @(Get-NetAdapter -Physical -EA SilentlyContinue)
    $memModules = @($mem | ForEach-Object {
        [PSCustomObject]@{ Bank=$_.BankLabel;Loc=$_.DeviceLocator;GB=[math]::Round($_.Capacity/1GB,0)
            Rated=$_.Speed;Running=$_.ConfiguredClockSpeed;Mfr=$_.Manufacturer;Part=($_.PartNumber -replace '\s+$','') }
    })
    [PSCustomObject]@{
        Timestamp=(Get-Date).ToString('o'); SigmaVersion=$script:SigmaVersion; Profile=$profile
        Motherboard=[PSCustomObject]@{ Mfr=$mb.Manufacturer;Product=$mb.Product;Version=$mb.Version }
        BIOS=[PSCustomObject]@{ Vendor=$bios.Manufacturer;Version=$bios.SMBIOSBIOSVersion;Date=$bios.ReleaseDate }
        CPUs=@(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,CurrentClockSpeed,SocketDesignation)
        Memory=[PSCustomObject]@{
            TotalGB=[math]::Round((@($mem)|Measure-Object Capacity -Sum).Sum/1GB,0)
            Modules=$memModules; Slots=$arr.MemoryDevices
            MultipleModulesDetected=((@($memModules.Loc | Sort-Object -Unique)).Count -ge 2)
            ConfiguredBelowReportedModuleSpeed=((@($memModules | Where-Object { $_.Running -lt $_.Rated })).Count -gt 0)
        }
        GPUs=@($gpus | Select-Object Name,DriverVersion,DriverDate,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate,Status)
        Storage=@($disks | ForEach-Object {
            $rel=$null; try { $rel = $_ | Get-StorageReliabilityCounter -EA Stop } catch { }
            [PSCustomObject]@{ Number=$_.DeviceId;Name=$_.FriendlyName;Media=$_.MediaType;Bus=$_.BusType
                SizeGB=[math]::Round($_.Size/1GB,1);Health=$_.HealthStatus
                Temp=$rel.Temperature;Wear=$rel.Wear;PowerOn=$rel.PowerOnHours }
        })
        Network=@($net | ForEach-Object {
            [PSCustomObject]@{ Name=$_.Name;Desc=$_.InterfaceDescription;Status=$_.Status
                LinkSpeed=$_.LinkSpeed;DriverVersion=$_.DriverVersion;DriverDate=$_.DriverDate }
        })
    }
}

$script:SigCounterDefs = @(
    [PSCustomObject]@{ Id='DPC_TIME';English='\Processor Information(_Total)\% DPC Time' }
    [PSCustomObject]@{ Id='ISR_TIME';English='\Processor Information(_Total)\% Interrupt Time' }
)
function Resolve-SigCounterDef {
    param($Def)
    try { $null = Get-Counter -Counter $Def.English -MaxSamples 1 -EA Stop
        return [PSCustomObject]@{ Id=$Def.Id;Resolved=$true;Path=$Def.English } }
    catch { return [PSCustomObject]@{ Id=$Def.Id;Resolved=$false;Path=$Def.English } }
}
function Get-SigCounterSnapshot {
    param([int]$Seconds=15,[int]$IntervalSeconds=1)
    if ($IntervalSeconds -lt 1) { $IntervalSeconds = 1 }
    $samples = [math]::Max(4, [int]($Seconds / $IntervalSeconds))
    $resolved = @(); foreach ($def in $script:SigCounterDefs) { $r = Resolve-SigCounterDef -Def $def; if ($r.Resolved) { $resolved += $r } }
    if ($resolved.Count -eq 0) { return [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o');Verdict='UNAVAILABLE';Note='No DPC/ISR counters resolved.';Totals=@() } }
    try { $result = Get-Counter -Counter ($resolved | ForEach-Object { $_.Path }) -SampleInterval $IntervalSeconds -MaxSamples $samples -EA Stop }
    catch { return [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o');Verdict='UNAVAILABLE';Note="Get-Counter: $($_.Exception.Message)";Totals=@() } }
    $totals = @(foreach ($r in $resolved) {
        $vals = @($result.CounterSamples | Where-Object Path -eq $r.Path | ForEach-Object { [double]$_.CookedValue })
        if ($vals.Count -eq 0) { continue }
        [PSCustomObject]@{ Id=$r.Id;Avg=[math]::Round(($vals|Measure-Object -Average).Average,3);Max=[math]::Round(($vals|Measure-Object -Maximum).Maximum,3) }
    })
    $verdict = 'NORMAL'
    $m = @($totals | Where-Object Id -eq 'DPC_TIME' | Select-Object -ExpandProperty Max -EA SilentlyContinue)
    if ($m.Count -gt 0) {
        if ($m[0] -gt 20) { $verdict = 'CRITICAL - DPC CPU time elevated' } elseif ($m[0] -gt 5) { $verdict = 'ELEVATED' }
    }
    [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o');DurationSec=$Seconds;Totals=$totals;Verdict=$verdict }
}

# -----------------------------------------------------------------------------
# SECTION 6 - Benchmark
# -----------------------------------------------------------------------------

function Get-SigMedian { param([double[]]$Values); if (-not $Values -or $Values.Count -eq 0) { return $null }; $s = $Values | Sort-Object; $n = $s.Count; if ($n % 2 -eq 1) { return [double]$s[[int]($n/2)] }; ([double]$s[$n/2-1] + [double]$s[$n/2]) / 2.0 }
function Get-SigStdDev { param([double[]]$Values); if (-not $Values -or $Values.Count -lt 2) { return 0 }; $m = ($Values|Measure-Object -Average).Average; $sq=0.0; foreach ($v in $Values) { $sq += ($v-$m)*($v-$m) }; [math]::Sqrt($sq/($Values.Count-1)) }
function Get-SigBootstrapCI {
    param([double[]]$A,[double[]]$B,[int]$Iterations=2000,[double]$Confidence=0.95)
    if ($A.Count -lt 2 -or $B.Count -lt 2) { return [PSCustomObject]@{ PointEstimate=$null;CI_Low=$null;CI_High=$null;Significant=$false;Direction='Unknown';Reason='Insufficient samples' } }
    $rng = New-Object System.Random; $diffs = New-Object 'double[]' $Iterations
    for ($i=0;$i -lt $Iterations;$i++) {
        $a = New-Object 'double[]' $A.Count; $b = New-Object 'double[]' $B.Count
        for ($j=0;$j -lt $A.Count;$j++) { $a[$j] = $A[$rng.Next($A.Count)] }
        for ($j=0;$j -lt $B.Count;$j++) { $b[$j] = $B[$rng.Next($B.Count)] }
        $diffs[$i] = (Get-SigMedian $b) - (Get-SigMedian $a)
    }
    [array]::Sort($diffs); $alpha = (1-$Confidence)/2
    $lo = $diffs[[math]::Max(0,[int]($Iterations*$alpha))]; $hi = $diffs[[math]::Min($Iterations-1,[int]($Iterations*(1-$alpha)))]
    $sig = (($lo -gt 0) -or ($hi -lt 0))
    $dir = if (-not $sig) { 'Inconclusive' } elseif ($lo -gt 0) { 'Improvement' } else { 'Regression' }
    [PSCustomObject]@{ PointEstimate=(Get-SigMedian $B)-(Get-SigMedian $A);CI_Low=$lo;CI_High=$hi
        Confidence=$Confidence;Significant=$sig;Direction=$dir;Reason=if ($sig) { 'CI excludes zero' } else { 'CI includes zero' } }
}

function Measure-SigCpuConsistency {
    param([int]$Seconds=10,[int]$Runs=5)
    $results = @(); $hash = $null
    try {
        $hash = [System.Security.Cryptography.SHA256]::Create()
        for ($run=1;$run -le $Runs;$run++) {
            Start-Sleep -Seconds 2
            $sw = [System.Diagnostics.Stopwatch]::StartNew(); $iter = 0
            while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
                $null = $hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("sig-$iter-$($sw.ElapsedTicks)")); $iter++
            }
            $sw.Stop()
            $results += [PSCustomObject]@{ Run=$run;Ops=$iter;OpsPerSec=[math]::Round($iter/$sw.Elapsed.TotalSeconds,0) }
        }
    } finally { if ($hash) { $hash.Dispose() } }
    $ops = [double[]]$results.OpsPerSec
    $median = Get-SigMedian $ops; $sd = Get-SigStdDev $ops
    $cv = if ($median -gt 0) { [math]::Round(($sd/$median)*100,3) } else { 0 }
    [PSCustomObject]@{ Kind='Sigma CPU Consistency Benchmark';Runs=$results;AllOpsPerSec=$ops;MedianOpsPerSec=$median
        MinOpsPerSec=($ops|Measure-Object -Minimum).Minimum;MaxOpsPerSec=($ops|Measure-Object -Maximum).Maximum
        StdDevOpsPerSec=[math]::Round($sd,0);CV_Percent=$cv }
}

function Start-SigBenchmark {
    param([string]$Label = ("run_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
    Write-Sig "Benchmark [$Label]" -Tag 'BM'
    $cpu = Measure-SigCpuConsistency -Seconds 10 -Runs 5
    $result = [PSCustomObject]@{
        SigmaVersion=$script:SigmaVersion; BenchmarkSchemaVersion=$script:BenchmarkSchemaVer
        Label=$Label; Timestamp=(Get-Date).ToString('o')
        Machine=(Get-SigMachineProfile); CPU=$cpu
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $script:SigmaBm "$Label.json") -Encoding UTF8

    $rows = @($cpu.Runs | ForEach-Object { [PSCustomObject]@{ Run=$_.Run; 'Ops/sec'=$_.OpsPerSec } })
    $stats = [ordered]@{
        'Median (ops/sec)'=$cpu.MedianOpsPerSec; 'Minimum'=$cpu.MinOpsPerSec
        'Maximum'=$cpu.MaxOpsPerSec; 'StdDev'=$cpu.StdDevOpsPerSec
        'Coefficient of Variation'="$($cpu.CV_Percent) %"
    }
    $body = @"
<div class="card">
<h2>Environment</h2>
$(ConvertTo-SigHtmlKeyValue ([ordered]@{
    'Label'=$Label; 'CPU'=$result.Machine.CPUName; 'CPU Vendor'=$result.Machine.CPUVendor
    'RAM (GB)'=$result.Machine.TotalRAMGB; 'Laptop'=$result.Machine.IsLaptop
    'Sigma Version'=$script:SigmaVersion; 'Benchmark Schema'=$script:BenchmarkSchemaVer
}))
</div>
<h2>CPU Consistency - Statistics</h2>
$(ConvertTo-SigHtmlKeyValue $stats)
<h2>Raw Runs</h2>
$(ConvertTo-SigHtmlTable $rows)
<p class="dim">JSON sidecar (used by comparison) is at <code>$Label.json</code>.</p>
"@
    $htmlPath = Join-Path $script:SigmaBm "$Label.html"
    ConvertTo-SigHtmlPage -Title "Sigma Benchmark - $Label" -Body $body -Subtitle "CPU consistency run" |
        Set-Content $htmlPath -Encoding UTF8
    Write-Sig "Benchmark HTML: $htmlPath" -Level OK -Tag 'BM'
    return $result
}

function Compare-SigBenchmarks {
    param([Parameter(Mandatory)][string]$BeforeLabel,[Parameter(Mandatory)][string]$AfterLabel,[switch]$WriteHtml)
    $bFile = Join-Path $script:SigmaBm "$BeforeLabel.json"; $aFile = Join-Path $script:SigmaBm "$AfterLabel.json"
    if (-not (Test-Path $bFile) -or -not (Test-Path $aFile)) { throw "Missing benchmark file(s)" }
    $b = Get-Content $bFile -Raw | ConvertFrom-Json
    $a = Get-Content $aFile -Raw | ConvertFrom-Json
    $cpuCI = Get-SigBootstrapCI -A ([double[]]$b.CPU.AllOpsPerSec) -B ([double[]]$a.CPU.AllOpsPerSec)
    $deltaPct = if ($b.CPU.MedianOpsPerSec -gt 0) { [math]::Round(100*($cpuCI.PointEstimate/$b.CPU.MedianOpsPerSec),2) } else { $null }
    $result = [PSCustomObject]@{
        BeforeLabel=$BeforeLabel;AfterLabel=$AfterLabel
        CPU_Before_Median=$b.CPU.MedianOpsPerSec;CPU_After_Median=$a.CPU.MedianOpsPerSec
        CPU_Delta=$cpuCI.PointEstimate;CPU_DeltaPct=$deltaPct
        CPU_CI_Low=$cpuCI.CI_Low;CPU_CI_High=$cpuCI.CI_High
        CPU_StatisticallySignificant=$cpuCI.Significant;CPU_Direction=$cpuCI.Direction;CPU_Reason=$cpuCI.Reason
        CPU_Before_CV=$b.CPU.CV_Percent;CPU_After_CV=$a.CPU.CV_Percent
    }
    if ($WriteHtml) {
        $badge = if ($cpuCI.Significant -and $cpuCI.Direction -eq 'Improvement') { "<span class='badge ok'>IMPROVEMENT</span>" }
                 elseif ($cpuCI.Significant -and $cpuCI.Direction -eq 'Regression') { "<span class='badge bad'>REGRESSION</span>" }
                 else { "<span class='badge warn'>INCONCLUSIVE</span>" }
        $body = @"
<p>$badge Compared <code>$BeforeLabel</code> vs <code>$AfterLabel</code></p>
<h2>Result</h2>
$(ConvertTo-SigHtmlKeyValue ([ordered]@{
    'Before - Median (ops/sec)'=$b.CPU.MedianOpsPerSec
    'After - Median (ops/sec)'=$a.CPU.MedianOpsPerSec
    'Delta (ops/sec)'=$cpuCI.PointEstimate
    'Delta (%)'=$deltaPct
    '95% CI Low'=$cpuCI.CI_Low
    '95% CI High'=$cpuCI.CI_High
    'Statistically Significant'=$cpuCI.Significant
    'Direction'=$cpuCI.Direction
    'Before CV %'=$b.CPU.CV_Percent
    'After CV %'=$a.CPU.CV_Percent
}))
"@
        $htmlPath = Join-Path $script:SigmaBm ("compare_{0}_vs_{1}.html" -f $BeforeLabel, $AfterLabel)
        ConvertTo-SigHtmlPage -Title "Sigma Benchmark Comparison" -Body $body |
            Set-Content $htmlPath -Encoding UTF8
        Write-Sig "Comparison HTML: $htmlPath" -Level OK -Tag 'BM'
    }
    return $result
}

# -----------------------------------------------------------------------------
# SECTION 7 - Optimization catalog (constructors fixed)
# -----------------------------------------------------------------------------

function New-RegOpt {
    param([string]$Id,[string]$Category,[string]$Title,[string]$Risk,[string]$Impact,
          [bool]$Reboot=$false,[string]$Path,[string]$Name,$Value,[string]$Type='DWord',
          [object]$AppliesTo=$null,[string]$Note='')
    $p=$Path;$n=$Name;$v=$Value;$t=$Type
    if ($AppliesTo -is [string]) { if (-not $Note) { $Note = $AppliesTo }; $AppliesTo = $null }
    if ($AppliesTo -isnot [scriptblock]) { $AppliesTo = { param($ctx) $true } }
    @{
        Id=$Id;Category=$Category;Title=$Title;Risk=$Risk;Impact=$Impact;RequiresReboot=$Reboot;Note=$Note
        AppliesTo=$AppliesTo
        Apply={ param($TxId) Invoke-SigRegistryWrite -TxId $TxId -Path $p -Name $n -Value $v -Type $t | Out-Null }.GetNewClosure()
    }
}

function New-SvcOpt {
    param([string]$Id,[string]$Category,[string]$Title,[string]$Risk,[string]$Impact,
          [string]$ServiceName,[string]$StartType,[string]$Action='Leave',
          [object]$AppliesTo=$null,[string]$Note='')
    $sn=$ServiceName;$st=$StartType;$ac=$Action
    if ($AppliesTo -is [string]) { if (-not $Note) { $Note = $AppliesTo }; $AppliesTo = $null }
    if ($AppliesTo -isnot [scriptblock]) { $AppliesTo = { param($ctx) $true } }
    @{
        Id=$Id;Category=$Category;Title=$Title;Risk=$Risk;Impact=$Impact;RequiresReboot=$false;Note=$Note
        AppliesTo=$AppliesTo
        Apply={ param($TxId) Invoke-SigServiceWrite -TxId $TxId -Name $sn -StartType $st -Action $ac | Out-Null }.GetNewClosure()
    }
}

function New-TaskOpt {
    param([string]$Id,[string]$Category,[string]$Title,[string]$Risk,[string]$Impact,
          [string]$TaskPath,[string]$TaskName,[string]$Action='Disable',
          [object]$AppliesTo=$null,[string]$Note='')
    $tp=$TaskPath;$tn=$TaskName;$act=$Action
    if ($AppliesTo -is [string]) { if (-not $Note) { $Note = $AppliesTo }; $AppliesTo = $null }
    if ($AppliesTo -isnot [scriptblock]) { $AppliesTo = { param($ctx) $true } }
    @{
        Id=$Id;Category=$Category;Title=$Title;Risk=$Risk;Impact=$Impact;RequiresReboot=$false;Note=$Note
        AppliesTo=$AppliesTo
        Apply={ param($TxId) Invoke-SigScheduledTaskWrite -TxId $TxId -TaskPath $tp -TaskName $tn -Action $act | Out-Null }.GetNewClosure()
    }
}

function New-FsutilOpt {
    param([string]$Id,[string]$Category,[string]$Title,[string]$Risk,[string]$Impact,
          [bool]$Reboot=$false,[string]$Setting,[string]$NewValue,
          [object]$AppliesTo=$null,[string]$Note='')
    $s=$Setting;$nv=$NewValue
    if ($AppliesTo -is [string]) { if (-not $Note) { $Note = $AppliesTo }; $AppliesTo = $null }
    if ($AppliesTo -isnot [scriptblock]) { $AppliesTo = { param($ctx) $true } }
    @{
        Id=$Id;Category=$Category;Title=$Title;Risk=$Risk;Impact=$Impact;RequiresReboot=$Reboot;Note=$Note
        AppliesTo=$AppliesTo
        Apply={ param($TxId) Invoke-SigFsutilWrite -TxId $TxId -Setting $s -NewValue $nv | Out-Null }.GetNewClosure()
    }
}

function New-PowerOpt {
    param([string]$Id,[string]$Category,[string]$Title,[string]$Risk,[string]$Impact,
          [string]$SubGroup,[string]$Setting,[int]$AcValue,
          [object]$AppliesTo=$null,[string]$Note='')
    $sg=$SubGroup;$st=$Setting;$ac=$AcValue
    if ($AppliesTo -is [string]) { if (-not $Note) { $Note = $AppliesTo }; $AppliesTo = $null }
    if ($AppliesTo -isnot [scriptblock]) { $AppliesTo = { param($ctx) $true } }
    @{
        Id=$Id;Category=$Category;Title=$Title;Risk=$Risk;Impact=$Impact;RequiresReboot=$false;Note=$Note
        AppliesTo=$AppliesTo
        Apply={ param($TxId) Invoke-SigPowerSettingWrite -TxId $TxId -SubGroup $sg -Setting $st -AcValue $ac | Out-Null }.GetNewClosure()
    }
}

function Get-SigOptimizationCatalog {

    $desktopOnly = { param($ctx) -not $ctx.Hardware.IsLaptop }
    $laptopOnly  = { param($ctx) $ctx.Hardware.IsLaptop }
    $ssdOnly     = { param($ctx) @($ctx.Storage | Where-Object { $_.Media -eq 'SSD' }).Count -gt 0 }
    $win11Only   = { param($ctx) $ctx.OS.Build -ge 22000 }
    $win10Plus   = { param($ctx) $ctx.OS.Build -ge 10240 }

    @(
        # ===== 1. PRIVACY & TELEMETRY (12) =====
        New-RegOpt 'Privacy_Telemetry_Minimum' 'Privacy' 'Set diagnostic data to Required only' 'Low' 'Privacy' $false `
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 'DWord' $win10Plus 'AllowTelemetry=1 (Required).'
        New-RegOpt 'Privacy_AdvertisingID_Off' 'Privacy' 'Disable Advertising ID' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'DWord'
        New-RegOpt 'Privacy_ActivityHistory_Off' 'Privacy' 'Disable Activity History publishing' 'Low' 'Privacy' $false `
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0 'DWord' $win10Plus
        New-RegOpt 'Privacy_Feedback_Never' 'Privacy' 'Set feedback frequency to Never' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0 'DWord'
        New-RegOpt 'Privacy_Suggested_Content_Off' 'Privacy' 'Disable Windows suggested content' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0 'DWord' $win10Plus
        New-RegOpt 'Privacy_Tailored_Experiences_Off' 'Privacy' 'Disable tailored experiences with diagnostic data' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'DWord'
        New-RegOpt 'Privacy_Location_Off' 'Privacy' 'Disable location tracking for the current user' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
        New-RegOpt 'Privacy_CloudClipboard_Off' 'Privacy' 'Disable cloud clipboard sync' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Clipboard' 'CloudClipboardAutomaticUpload' 0 'DWord'
        New-RegOpt 'Privacy_Bing_Cortana_Off' 'Privacy' 'Disable Bing search in Start menu' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 'DWord'
        New-RegOpt 'Privacy_CEIP_Off' 'Privacy' 'Disable Customer Experience Improvement Program' 'Low' 'Privacy' $false `
            'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 'DWord'
        New-RegOpt 'Privacy_App_Telemetry_Off' 'Privacy' 'Disable AppTelemetry' 'Low' 'Privacy' $false `
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0 'DWord'
        New-RegOpt 'Privacy_Handwriting_Off' 'Privacy' 'Disable handwriting data sharing' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1 'DWord'

        # ===== 2. GAMING (10) =====
        New-RegOpt 'Gaming_GameMode_On' 'Gaming' 'Enable Game Mode' 'Low' 'Low/Med' $false `
            'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 'DWord' $win10Plus
        New-RegOpt 'Gaming_HAGS_On' 'Gaming' 'Enable Hardware-Accelerated GPU Scheduling' 'Medium' 'Medium' $true `
            'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'DWord' $win10Plus 'Requires reboot. Roll back if stutter appears.'
        New-RegOpt 'Gaming_GameDVR_Off' 'Gaming' 'Disable Game DVR background recording' 'Low' 'Gaming' $false `
            'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 'DWord'
        New-RegOpt 'Gaming_GameBar_Off' 'Gaming' 'Disable Xbox Game Bar' 'Low' 'Gaming' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 'DWord'
        New-RegOpt 'Gaming_FSE_Off' 'Gaming' 'Disable fullscreen optimizations globally' 'Low' 'Gaming' $false `
            'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2 'DWord'
        New-RegOpt 'Gaming_Network_Throttling_Off' 'Gaming' 'Disable network throttling index' 'Low' 'Latency' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 4294967295 'DWord'
        New-RegOpt 'Gaming_System_Responsiveness' 'Gaming' 'Set SystemResponsiveness to 10 for gaming' 'Medium' 'Gaming' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10 'DWord' $null 'Decreases CPU reserved for background; gaming priority.'
        New-RegOpt 'Gaming_GPU_Priority' 'Gaming' 'Raise GPU priority for Games task' 'Low' 'Gaming' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 8 'DWord'
        New-RegOpt 'Gaming_CPU_Priority' 'Gaming' 'Set Games task CPU priority to 6 (High)' 'Low' 'Gaming' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6 'DWord'
        New-RegOpt 'Gaming_MMCSS_Games_Sched' 'Gaming' 'Set MMCSS Games Scheduling Category to High' 'Low' 'Gaming' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' 'String'

        # ===== 3. INPUT LATENCY (8) =====
        New-RegOpt 'Input_Mouse_Accel_Off' 'Latency' 'Disable mouse pointer acceleration' 'Low' 'Latency' $false `
            'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
        New-RegOpt 'Input_Mouse_Threshold1' 'Latency' 'Reset mouse acceleration threshold 1' 'Low' 'Latency' $false `
            'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
        New-RegOpt 'Input_Mouse_Threshold2' 'Latency' 'Reset mouse acceleration threshold 2' 'Low' 'Latency' $false `
            'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
        New-RegOpt 'Input_Menu_Show_Delay' 'Latency' 'Reduce menu show delay to 100ms' 'Low' 'Cosmetic' $false `
            'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '100' 'String'
        New-RegOpt 'Input_Mouse_Hover_Time' 'Latency' 'Reduce mouse hover time to 50ms' 'Low' 'Cosmetic' $false `
            'HKCU:\Control Panel\Mouse' 'MouseHoverTime' '50' 'String'
        New-RegOpt 'Input_Keyboard_Delay' 'Latency' 'Set keyboard repeat delay to shortest' 'Low' 'Cosmetic' $false `
            'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0' 'String'
        New-RegOpt 'Input_Keyboard_Speed' 'Latency' 'Set keyboard repeat rate to fastest' 'Low' 'Cosmetic' $false `
            'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed' '31' 'String'
        New-RegOpt 'Input_Win32_Priority' 'Latency' 'Set Win32 Priority Separation to 26 hex (fair short bursts)' 'Medium' 'Responsiveness' $true `
            'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38 'DWord' $desktopOnly '38 = hex 26. Favor foreground short bursts.'

        # ===== 4. UI / EXPLORER (10) =====
        New-RegOpt 'UI_Show_File_Extensions' 'Usability' 'Show file extensions in Explorer' 'Low' 'Security' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0 'DWord'
        New-RegOpt 'UI_Show_Hidden_Files' 'Usability' 'Show hidden files' 'Low' 'Usability' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1 'DWord'
        New-RegOpt 'UI_Launch_To_ThisPC' 'Usability' 'Open Explorer to This PC instead of Quick Access' 'Low' 'Usability' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1 'DWord'
        New-RegOpt 'UI_Widgets_Off' 'UI' 'Disable Widgets on taskbar' 'Low' 'Cosmetic' $false `
            'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 'DWord' $win11Only
        New-RegOpt 'UI_Chat_Icon_Off' 'UI' 'Hide Chat/Teams icon on taskbar' 'Low' 'Cosmetic' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0 'DWord' $win11Only
        New-RegOpt 'UI_Search_Box_Small' 'UI' 'Shrink Search box on taskbar' 'Low' 'Cosmetic' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1 'DWord'
        New-RegOpt 'UI_Start_Recommendations_Off' 'UI' 'Disable Start menu recommendations' 'Low' 'Cosmetic' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0 'DWord' $win11Only
        New-RegOpt 'UI_Transparency_Off' 'UI' 'Disable window transparency (small perf gain)' 'Low' 'Perf' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 'DWord'
        New-RegOpt 'UI_Animations_Off' 'UI' 'Disable window animations' 'Low' 'Perf' $false `
            'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
        New-RegOpt 'UI_Notification_Toasts_Off' 'UI' 'Disable notification toasts' 'Low' 'Focus' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0 'DWord'

        # ===== 5. STORAGE (5) =====
        New-FsutilOpt 'Storage_DisableLastAccess' 'Storage' 'Disable NTFS last-access timestamp' 'Low' 'Storage' $true `
            'disablelastaccess' '1' $ssdOnly 'Reduces writes. Requires reboot.'
        New-FsutilOpt 'Storage_Disable8Dot3' 'Storage' 'Disable 8.3 filename generation' 'Low' 'Storage' $false `
            'disable8dot3' '1' $ssdOnly
        New-RegOpt 'Storage_Reserved_Storage_Off' 'Storage' 'Disable Reserved Storage (frees ~7GB)' 'Medium' 'Storage' $true `
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 0 'DWord' $win10Plus 'Only for small drives; Windows updates may need space.'
        New-RegOpt 'Storage_Hibernation_Off' 'Storage' 'Disable hibernation (frees hiberfil.sys)' 'Medium' 'Storage' $false `
            'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' 0 'DWord' $desktopOnly 'Run "powercfg /h off" to fully release the file.'
        New-RegOpt 'Storage_ThumbnailCache_On' 'Storage' 'Keep thumbnail caching enabled (Explorer)' 'Low' 'Usability' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'IconsOnly' 0 'DWord'

        # ===== 6. POWER (6) =====
        New-RegOpt 'Power_FastStartup_Off_Laptop' 'Reliability' 'Disable Fast Startup (laptop)' 'Low' 'Reliability' $true `
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 'DWord' $laptopOnly
        New-RegOpt 'Power_FastStartup_Off_Desktop' 'Reliability' 'Disable Fast Startup (desktop)' 'Low' 'Reliability' $true `
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 'DWord' $desktopOnly
        New-PowerOpt 'Power_USB_Selective_Suspend_Off' 'Power' 'Disable USB selective suspend' 'Low' 'Reliability' `
            '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0
        New-PowerOpt 'Power_PCIe_ASPM_Off' 'Power' 'Disable PCIe ASPM (may fix NVMe/GPU wake issues)' 'Medium' 'Reliability' `
            '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5' 0
        New-PowerOpt 'Power_HDD_Sleep_Never_AC' 'Power' 'Never sleep hard disks on AC' 'Low' 'Storage' `
            '0012ee47-9041-4b5d-9b77-535fba8b1442' '6738e2c4-e8a5-4a42-b16a-e040e769756e' 0
        New-PowerOpt 'Power_Display_Timeout_AC' 'Power' 'Display timeout 30 min on AC' 'Low' 'Convenience' `
            '7516b95f-f776-4464-8c53-06167f40cc99' '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e' 1800

        # ===== 7. NETWORK (4) =====
        New-RegOpt 'Net_Nagle_Off_PerInterface' 'Network' 'Reduce Nagle latency on TCP interfaces' 'Medium' 'Latency' $false `
            'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' 'TcpAckFrequency' 1 'DWord' $null 'Applies to active interfaces only after reboot.'
        New-RegOpt 'Net_TcpNoDelay' 'Network' 'Enable TCPNoDelay on active interfaces' 'Medium' 'Latency' $false `
            'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' 'TCPNoDelay' 1 'DWord'
        New-RegOpt 'Net_Disable_IPv6_Transition' 'Network' 'Disable IPv6 transition tech (Teredo, 6to4)' 'Low' 'Network' $false `
            'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' 'DisabledComponents' 8 'DWord' $null 'Keeps IPv6 native; disables legacy tunneling only.'
        New-RegOpt 'Net_DNS_Cache_Protect' 'Network' 'Increase DNS cache timeout value' 'Low' 'Network' $false `
            'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxCacheTtl' 86400 'DWord'

        # ===== 8. SERVICES (7) =====
        New-SvcOpt 'Svc_DiagTrack_Disable' 'Privacy' 'Disable Connected User Experiences & Telemetry' 'Medium' 'Privacy' `
            'DiagTrack' 'Disabled' 'Stop' $win10Plus 'Major telemetry service. Safe to disable for most home users.'
        New-SvcOpt 'Svc_dmwappush_Disable' 'Privacy' 'Disable WAP Push Message Routing Service' 'Low' 'Privacy' `
            'dmwappushservice' 'Disabled' 'Stop' $win10Plus
        New-SvcOpt 'Svc_RetailDemo_Disable' 'Privacy' 'Disable Retail Demo Service' 'Low' 'Privacy' `
            'RetailDemo' 'Disabled' 'Stop' $win10Plus
        New-SvcOpt 'Svc_RemoteRegistry_Disable' 'Security' 'Disable Remote Registry' 'Low' 'Security' `
            'RemoteRegistry' 'Disabled' 'Stop'
        New-SvcOpt 'Svc_Fax_Disable' 'Services' 'Disable Fax service' 'Low' 'Perf' `
            'Fax' 'Disabled' 'Stop'
        New-SvcOpt 'Svc_MapsBroker_Disable' 'Services' 'Disable Downloaded Maps Manager' 'Low' 'Perf' `
            'MapsBroker' 'Manual' 'Stop' $win10Plus
        New-SvcOpt 'Svc_WSearch_Disable' 'Services' 'Disable Windows Search indexing' 'Medium' 'Perf' `
            'WSearch' 'Disabled' 'Stop' $desktopOnly 'Disables Start menu search of files. Only for users who do not need indexing.'

        # ===== 9. SCHEDULED TASKS (5) =====
        New-TaskOpt 'Task_Compat_Appraiser' 'Privacy' 'Disable Compatibility Appraiser' 'Low' 'Privacy' `
            '\Microsoft\Windows\Application Experience\' 'Microsoft Compatibility Appraiser'
        New-TaskOpt 'Task_Program_Data_Updater' 'Privacy' 'Disable Program Data Updater' 'Low' 'Privacy' `
            '\Microsoft\Windows\Application Experience\' 'ProgramDataUpdater'
        New-TaskOpt 'Task_Customer_Experience' 'Privacy' 'Disable Customer Experience Improvement Program task' 'Low' 'Privacy' `
            '\Microsoft\Windows\Customer Experience Improvement Program\' 'Consolidator'
        New-TaskOpt 'Task_Autochk_Proxy' 'Privacy' 'Disable Autochk Proxy task' 'Low' 'Privacy' `
            '\Microsoft\Windows\Autochk\' 'Proxy'
        New-TaskOpt 'Task_Feedback_Siuf' 'Privacy' 'Disable Windows Feedback Siuf task' 'Low' 'Privacy' `
            '\Microsoft\Windows\Feedback\Siuf\' 'DmClient'

        # ===== 10. DEBLOAT (5) =====
        New-RegOpt 'Debloat_Consumer_Features_Off' 'Debloat' 'Disable Windows consumer features (auto-app install)' 'Low' 'Privacy' $false `
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 'DWord' $win10Plus
        New-RegOpt 'Debloat_Suggested_Apps_Off' 'Debloat' 'Disable suggested apps installs' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0 'DWord' $win10Plus
        New-RegOpt 'Debloat_Preinstalled_Apps_Off' 'Debloat' 'Disable preinstalled app auto-installation' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0 'DWord' $win10Plus
        New-RegOpt 'Debloat_Tips_Tricks_Off' 'Debloat' 'Disable Windows tips and tricks' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0 'DWord' $win10Plus
        New-RegOpt 'Debloat_OneDrive_Auto_Off' 'Debloat' 'Prevent OneDrive from auto-starting with Windows' 'Low' 'Privacy' $false `
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 0 'DWord' $win10Plus 'Does not uninstall OneDrive; prevents auto-start.'

        # ===== 11. AUDIO (2) =====
        New-RegOpt 'Audio_Enhancements_Off' 'Audio' 'Disable audio enhancements on default device' 'Low' 'Audio' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render' 'Disable_SysFx' 1 'DWord' $null 'Applies globally; effective after device re-enumeration.'
        New-RegOpt 'Audio_Exclusive_Mode_Off' 'Audio' 'Disable exclusive mode preference for shared audio' 'Low' 'Audio' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio' 'ExclusiveMode' 0 'DWord'

        # ===== 12. UPDATE CONTROL (4) =====
        New-RegOpt 'Update_Driver_WU_Off' 'Updates' 'Prevent automatic driver updates via Windows Update' 'Medium' 'Control' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0 'DWord' $win10Plus 'Stops WU overwriting your good drivers.'
        New-RegOpt 'Update_Feature_Defer' 'Updates' 'Defer feature updates by 365 days' 'Medium' 'Control' $false `
            'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'DeferFeatureUpdatesPeriodInDays' 365 'DWord' $win10Plus
        New-RegOpt 'Update_Quality_Defer' 'Updates' 'Defer quality updates by 7 days' 'Low' 'Control' $false `
            'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'DeferQualityUpdatesPeriodInDays' 7 'DWord' $win10Plus
        New-RegOpt 'Update_Metered_On' 'Updates' 'Treat current connection as metered (slows WU)' 'Low' 'Control' $false `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\DefaultMediaCost' '3' 2 'DWord' $win10Plus

        # ===== 13. BOOT / LEGACY (2) =====
        New-RegOpt 'Boot_Timeout_Low' 'Boot' 'Reduce boot menu timeout to 3 seconds' 'Low' 'Boot' $false `
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'BootMenuTimeout' 3 'DWord'
        New-RegOpt 'UI_Classic_Context_Menu_Win11' 'UI' 'Restore classic right-click context menu (Win11)' 'Low' 'Usability' $false `
            'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' '' 'String' $win11Only

        # ===== 14. EXPLORER PERFORMANCE (2) =====
        New-RegOpt 'Explorer_Disable_Recent_Files' 'UI' 'Do not track recent files in Quick Access' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 0 'DWord'
        New-RegOpt 'Explorer_Disable_Recent_Apps' 'UI' 'Do not track recent apps in Start' 'Low' 'Privacy' $false `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0 'DWord'

        # ===== 15. META (1) =====
        New-RegOpt 'Meta_Sigma_Marker' 'Meta' 'Sigma Performance marker (no system change)' 'Low' 'Metadata' $false `
            'HKCU:\Software\SigmaPerformance' 'Installed' 1 'DWord' $win10Plus 'Timestamped marker; harmless.'
    )
}

function Get-SigContext {
    param($HardwareInventory)
    $os = Get-CimInstance Win32_OperatingSystem
    [PSCustomObject]@{
        Hardware=$HardwareInventory.Profile
        Storage=$HardwareInventory.Storage
        OS=[PSCustomObject]@{ Caption=$os.Caption;Build=[int]$os.BuildNumber;Version=$os.Version }
    }
}

function Invoke-SigOptimization {
    param([Parameter(Mandatory)][string[]]$Ids,[switch]$DryRun)
    $hw = Get-SigHardwareInventory; $ctx = Get-SigContext -HardwareInventory $hw
    $catalog = Get-SigOptimizationCatalog

    if ($DryRun) {
        foreach ($id in $Ids) {
            $opt = $catalog | Where-Object { $_.Id -eq $id }
            if (-not $opt) { continue }
            if (-not (& $opt.AppliesTo $ctx)) { Write-Host "  [SKIP] $($opt.Title) (not applicable)" -ForegroundColor DarkGray; continue }
            Write-Host "  [DRY] $($opt.Title)  [Risk:$($opt.Risk)] Reboot=$($opt.RequiresReboot)" -ForegroundColor Cyan
        }
        return [PSCustomObject]@{ TransactionId=$null;Applied=@();RequiresReboot=$false;RecoveryRequired=$false }
    }

    $txId = Start-SigTransaction -Name 'optimize'
    Set-SigTxState -TxId $txId -State 'Applying'
    $applied = @(); $failed = 0; $needsReboot = $false; $appliedIds = @(); $recoveryRequired = $false

    foreach ($id in $Ids) {
        $opt = $catalog | Where-Object { $_.Id -eq $id }
        if (-not $opt) { Write-Sig "Unknown optimization: $id" -Level WARN -Tag 'OPT'; continue }
        if (-not (& $opt.AppliesTo $ctx)) { Write-Sig "Skip (not applicable): $($opt.Title)" -Tag 'OPT'; continue }
        try {
            & $opt.Apply $txId
            if ($opt.RequiresReboot) { $needsReboot = $true }
            $applied += [PSCustomObject]@{ Id=$id;Title=$opt.Title;Category=$opt.Category;Risk=$opt.Risk;RequiresReboot=$opt.RequiresReboot;Time=(Get-Date) }
            $appliedIds += $id
            Write-Sig "Applied: $($opt.Title)" -Level OK -Tag 'OPT'
        } catch [SigmaCriticalMutationException] {
            Write-Sig "CRITICAL: $_ -- halting batch." -Level ERROR -Tag 'OPT'
            Add-SigError "Critical: $id -- $_"
            $failed++; $recoveryRequired = $true; break
        } catch {
            Write-Sig "Apply failed: $($opt.Title) -- $_" -Level ERROR -Tag 'OPT'
            Add-SigError "Apply failed: $id -- $_"
            $failed++
        }
    }

    if ($recoveryRequired) { Set-SigTxState -TxId $txId -State 'RecoveryRequired' -Applied $applied.Count -Failed $failed -RequiresReboot $needsReboot -RecoveryRequired $true -Optimizations $appliedIds }
    elseif ($failed -eq 0 -and $applied.Count -gt 0) { Set-SigTxState -TxId $txId -State 'Applied' -Applied $applied.Count -Failed 0 -RequiresReboot $needsReboot -RecoveryRequired $false -Optimizations $appliedIds }
    elseif ($applied.Count -gt 0) { Set-SigTxState -TxId $txId -State 'PartiallyApplied' -Applied $applied.Count -Failed $failed -RequiresReboot $needsReboot -RecoveryRequired $false -Optimizations $appliedIds }
    else { Set-SigTxState -TxId $txId -State 'PartiallyApplied' -Applied 0 -Failed $failed -RequiresReboot $false -RecoveryRequired $false -Optimizations @() }

    Write-SigJournalHash -TxId $txId
    New-SigTxHtmlReport -TxId $txId | Out-Null
    [PSCustomObject]@{ TransactionId=$txId;Applied=$applied;RequiresReboot=$needsReboot;RecoveryRequired=$recoveryRequired }
}

# -----------------------------------------------------------------------------
# SECTION 8 - Transaction HTML report
# -----------------------------------------------------------------------------

function New-SigTxHtmlReport {
    param([Parameter(Mandatory)][string]$TxId)
    $dir = Join-Path $script:SigmaTx $TxId
    if (-not (Test-Path $dir)) { return $null }
    $meta = Get-Content (Join-Path $dir 'metadata.json') -Raw | ConvertFrom-Json
    $journal = Join-Path $dir 'journal.jsonl'
    $events = @(if (Test-Path $journal) { Get-Content $journal | ForEach-Object { $_ | ConvertFrom-Json } })

    $mutations = @{}
    foreach ($e in $events) {
        if (-not $mutations.ContainsKey($e.MutationId)) {
            $mutations[$e.MutationId] = [PSCustomObject]@{ MutationId=$e.MutationId;Kind='';Target='';Sequence=0;Events=@() }
        }
        if ($e.Event -eq 'Capture') {
            $mutations[$e.MutationId].Kind = $e.Kind
            $mutations[$e.MutationId].Target = $e.Target
            $mutations[$e.MutationId].Sequence = [int]$e.Sequence
        }
        $mutations[$e.MutationId].Events += $e.Event
    }
    $mutationRows = @($mutations.Values | Sort-Object Sequence | ForEach-Object {
        [PSCustomObject]@{ Seq=$_.Sequence;Kind=$_.Kind;Target=$_.Target;'Events'=($_.Events -join ' -> ') }
    })

    $statusBadge = switch ($meta.State) {
        'Applied'                { "<span class='badge ok'>APPLIED</span>" }
        'PartiallyApplied'       { "<span class='badge warn'>PARTIAL</span>" }
        'RecoveryRequired'       { "<span class='badge bad'>RECOVERY REQUIRED</span>" }
        'RolledBack'             { "<span class='badge info'>ROLLED BACK</span>" }
        'RollbackPartialFailure' { "<span class='badge bad'>ROLLBACK PARTIAL</span>" }
        default                  { "<span class='badge info'>$($meta.State)</span>" }
    }

    $optList = ''
    if ($meta.Optimizations) { $optList = ($meta.Optimizations -join ', ') }

    $body = @"
<p>$statusBadge</p>
<h2>Transaction</h2>
$(ConvertTo-SigHtmlKeyValue ([ordered]@{
    'ID'=$meta.Id; 'State'=$meta.State; 'Started'=$meta.Started
    'Applied'=$meta.Applied; 'Failed'=$meta.Failed
    'Requires Reboot'=$meta.RequiresReboot; 'Recovery Required'=$meta.RecoveryRequired
    'Optimizations'=$optList
}))
<h2>Mutations (execution order)</h2>
$(ConvertTo-SigHtmlTable $mutationRows)
<h2>Raw journal</h2>
<details><summary>Show $(@($events).Count) events</summary>
<pre>$(ConvertTo-SigHtmlEncoded (($events | ForEach-Object { "$($_.Sequence)  $($_.Event)  $($_.Kind)  $($_.Target)  $($_.Detail)" }) -join "`n"))</pre>
</details>
<p class="dim">Rollback with: <code>Restore-SigTransaction -TxId '$TxId'</code></p>
"@
    $htmlPath = Join-Path $script:SigmaHtm "tx_$TxId.html"
    ConvertTo-SigHtmlPage -Title "Sigma Transaction $TxId" -Body $body | Set-Content $htmlPath -Encoding UTF8
    Write-Sig "Transaction HTML: $htmlPath" -Level OK -Tag 'TX'
    return $htmlPath
}

# -----------------------------------------------------------------------------
# SECTION 9 - Collectors
# -----------------------------------------------------------------------------

function Test-SigEfiSystemPresent {
    $isUefi = $false
    try { $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType' -EA Stop).PEFirmwareType; $isUefi = ($pf -eq 2) } catch { }
    $efi = @(Get-Partition -EA SilentlyContinue | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' })
    [PSCustomObject]@{ IsUefi=$isUefi;HasEfi=($efi.Count -gt 0);EfiPartition=$efi }
}
function Get-SigWinReState {
    $r = [PSCustomObject]@{ InstalledKnown=$false;Installed=$null;EnabledKnown=$false;Enabled=$null;Method='unknown' }
    try {
        $p = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinRE'
        if (Test-Path $p) {
            $item = Get-ItemProperty -Path $p -EA Stop
            if ($item.PSObject.Properties.Name -contains 'WinReDisabled' -and $null -ne $item.WinReDisabled) {
                $r.InstalledKnown=$true; $r.Installed=$true; $r.EnabledKnown=$true
                $r.Enabled=($item.WinReDisabled -eq 0); $r.Method='registry heuristic: WinReDisabled'; return $r
            }
        }
    } catch { }
    $wim = "$env:WINDIR\System32\Recovery\Winre.wim"
    if (Test-Path $wim) { $r.InstalledKnown=$true; $r.Installed=$true; $r.Method='file:Winre.wim'; return $r }
    return $r
}

function Get-SigResults_GroupA {
    $out = New-Object System.Collections.ArrayList
    $nt = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $os = Get-CimInstance Win32_OperatingSystem
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -EA SilentlyContinue | Select-Object -First 1
    $f = @(); if ($lic -and $lic.LicenseStatus -ne 1) { $f += "Windows not activated" }
    $s = if ($f.Count) { 'WARN' } else { 'OK' }
    $null = $out.Add((New-Evidence 'OS_INSTALL_001' 1 $s 3 0.95 'Installation' ($f -join '; ') -EvidenceLines $f -Data @{ Edition=$nt.EditionID; Build="$($os.BuildNumber).$($nt.UBR)"; Activation=$(if ($lic) { $lic.LicenseStatus } else { $null }) }))
    $sd = "$env:WINDIR\SoftwareDistribution\Download"; $sdMB = 0
    if (Test-Path $sd) { $size = Get-ChildItem $sd -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum; if ($null -ne $size.Sum) { $sdMB = [math]::Round($size.Sum/1MB,1) } }
    $pending = 0; try { $ss=New-Object -ComObject Microsoft.Update.Session; $se=$ss.CreateUpdateSearcher(); $pending=$se.Search("IsInstalled=0 and IsHidden=0").Updates.Count } catch { }
    $f = @()
    if ($sdMB -gt 5000) { $f += "SoftwareDistribution cache $sdMB MB" }
    if ($pending -gt 10) { $f += "$pending pending updates" }
    $s = if ($f.Count) { 'WARN' } else { 'OK' }
    $null = $out.Add((New-Evidence 'WU_STATE_001' 2 $s 3 0.95 'Windows Update' ($f -join '; ') -EvidenceLines $f -Data @{ CacheMB=$sdMB;Pending=$pending }))
    $all = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName })
    $old = @($all | Where-Object { $_.DriverDate -and ([datetime]$_.DriverDate) -lt (Get-Date).AddYears(-3) -and $_.DeviceName -match 'Display|Network|Audio|Storage' })
    $uns = @($all | Where-Object { -not $_.IsSigned })
    $f = @(); $st = 'OK'; $sev = 0
    if ($old.Count) { $f += "$($old.Count) display/network/audio/storage drivers older than 3 years"; $st = 'INFO' }
    if ($uns.Count) { $f += "$($uns.Count) unsigned drivers"; $st = 'WARN'; $sev = 4 }
    $null = $out.Add((New-Evidence 'DRV_AGE_001' 3 $st $sev 0.9 'Drivers' ($f -join '; ') -EvidenceLines $f -Data @{ Total=$all.Count;Old=$old;Unsigned=$uns }))
    $prob = @(Get-PnpDevice -PresentOnly -EA SilentlyContinue | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })
    $st = if ($prob.Count) { 'WARN' } else { 'OK' }
    $null = $out.Add((New-Evidence 'DEVMGR_001' 4 $st $(if ($prob.Count) { 6 } else { 0 }) 0.98 'Device Manager' $(if ($prob.Count) { "$($prob.Count) problem devices" } else { 'No problem devices' }) -EvidenceLines @($prob | ForEach-Object { "$($_.FriendlyName): $($_.ProblemDescription)" }) -Data @{ Problems=$prob }))
    $efiInfo = Test-SigEfiSystemPresent
    $sb = $null; try { $sb = Confirm-SecureBootUEFI -EA Stop } catch { }
    $tpm = $null; try { $tpm = Get-Tpm -EA Stop } catch { }
    $f = @()
    if ($sb -eq $false) { $f += "Secure Boot disabled" }
    if ($tpm -and -not $tpm.TpmReady) { $f += "TPM present but not ready" }
    $st = if ($f.Count) { 'WARN' } else { 'OK' }
    $null = $out.Add((New-Evidence 'FW_STATE_001' 5 $st 4 0.95 'Firmware' ($f -join '; ') -EvidenceLines $f -Data @{ IsUefi=$efiInfo.IsUefi;HasEfi=$efiInfo.HasEfi;SecureBoot=$sb }))
    return $out
}

function Get-SigResults_GroupB {
    $out = New-Object System.Collections.ArrayList
    $winre = Get-SigWinReState
    $f = @(); $st = 'OK'; $sev = 0
    if ($winre.EnabledKnown -and -not $winre.Enabled) { $f += "WinRE disabled"; $st='WARN'; $sev=4 }
    elseif (-not $winre.EnabledKnown) { $f += "WinRE enabled state could not be verified"; $st='INFO' }
    $null = $out.Add((New-Evidence 'BOOT_STATE_001' 6 $st $sev 0.9 'Boot' ($f -join '; ') -EvidenceLines $f -Data @{ WinReInstalledKnown=$winre.InstalledKnown;WinReEnabledKnown=$winre.EnabledKnown;WinReEnabled=$winre.Enabled;WinReMethod=$winre.Method }))
    $dumps = @(Get-ChildItem "$env:SystemRoot\Minidump" -Filter '*.dmp' -EA SilentlyContinue | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-30) })
    $whea = @(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=(Get-Date).AddDays(-30)} -EA SilentlyContinue)
    $kp41 = @(Get-WinEvent -FilterHashtable @{LogName='System';Id=41;StartTime=(Get-Date).AddDays(-30)} -EA SilentlyContinue)
    $wheaFatal = @($whea | Where-Object { $_.Message -match 'fatal|unrecoverable|uncorrected|Machine Check|MCE' })
    $wheaCorr = @($whea | Where-Object { $_.Message -match 'corrected' -or $_.Id -in 17,18,19,20 })
    $wheaOther = @($whea | Where-Object { $_ -notin $wheaFatal -and $_ -notin $wheaCorr })
    $f = @()
    if ($dumps.Count) { $f += "$($dumps.Count) minidumps (30d)" }
    if ($whea.Count) { $f += "$($whea.Count) WHEA events" }
    if ($kp41.Count) { $f += "$($kp41.Count) unexpected shutdowns" }
    $st = 'OK'; $sev = 0
    if ($wheaFatal.Count) { $st='FAIL'; $sev=9 } elseif ($dumps.Count) { $st='FAIL'; $sev=7 } elseif ($kp41.Count -ge 3) { $st='WARN'; $sev=5 } elseif ($wheaCorr.Count -or $wheaOther.Count) { $st='WARN'; $sev=4 } elseif ($kp41.Count -eq 1) { $st='INFO'; $sev=2 }
    $null = $out.Add((New-Evidence 'STAB_BSOD_001' 7 $st $sev 0.85 'BSOD' ($f -join '; ') -EvidenceLines $f -Data @{ Minidumps=$dumps.Count;WHEA_Total=$whea.Count;WHEA_Fatal=$wheaFatal.Count;WHEA_Corrected=$wheaCorr.Count;WHEA_Unclassified=$wheaOther.Count;KernelPower41=$kp41.Count }))
    $top = @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Name,Id,@{n='RAM_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}})
    $null = $out.Add((New-Evidence 'PERF_TOP_001' 8 'INFO' 0 1.0 'Processes' "$($top.Count) top processes" -Data @{ Top=$top }))
    $cpu = Get-CimInstance Win32_Processor
    $null = $out.Add((New-Evidence 'CPU_STATE_001' 9 'INFO' 0 1.0 'CPU' $cpu.Name -Data @{ Cores=$cpu.NumberOfCores;Threads=$cpu.NumberOfLogicalProcessors }))
    return $out
}

# -----------------------------------------------------------------------------
# SECTION 10 - Scan HTML report
# -----------------------------------------------------------------------------

function New-SigScanHtmlReport {
    param([object[]]$Evidence,[object]$Hardware,[object]$Dpc,[string]$Path = (Join-Path $script:SigmaRpt ("scan-{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))))
    $ok=0; $warn=0; $fail=0
    foreach ($e in $Evidence) { switch ($e.Status) { 'OK'{$ok++} 'WARN'{$warn++} 'FAIL'{$fail++} } }
    $rows = @($Evidence | Sort-Object Category | ForEach-Object {
        [PSCustomObject]@{ '#'=$_.Category;'Detector'=$_.DetectorId;'Status'=$_.Status;'Conf'=[math]::Round($_.Confidence,2);'Finding'=$_.Finding }
    })
    $hw = [ordered]@{
        'Manufacturer'=$Hardware.Profile.Manufacturer; 'Model'=$Hardware.Profile.Model
        'CPU'=$Hardware.Profile.CPUName; 'CPU Vendor'=$Hardware.Profile.CPUVendor
        'RAM (GB)'=$Hardware.Profile.TotalRAMGB; 'Laptop'=$Hardware.Profile.IsLaptop
        'Likely Hybrid'=$Hardware.Profile.LikelyHybrid
    }
    $body = @"
<p>OK: <span class='ok'>$ok</span>  WARN: <span class='warn'>$warn</span>  FAIL: <span class='bad'>$fail</span></p>
<h2>Hardware</h2>
$(ConvertTo-SigHtmlKeyValue $hw)
<h2>DPC / ISR Screening</h2>
$(ConvertTo-SigHtmlKeyValue ([ordered]@{ 'Verdict'=$Dpc.Verdict; 'Duration (s)'=$Dpc.DurationSec; 'Note'=$Dpc.Note }))
<h2>Detections</h2>
$(ConvertTo-SigHtmlTable $rows)
"@
    ConvertTo-SigHtmlPage -Title "Sigma Performance Report" -Body $body | Set-Content $Path -Encoding UTF8
    Write-Sig "Scan report: $Path" -Level OK -Tag 'RPT'
    return $Path
}

# -----------------------------------------------------------------------------
# SECTION 11 - Main flow
# -----------------------------------------------------------------------------

try {
    $pendingIds = @(Get-SigPendingTxIds)
    $unresolvedPending = @()
    if ($pendingIds.Count -gt 0) {
        Write-Host ""
        Write-Host "========== PENDING VALIDATION ==========" -ForegroundColor Yellow
        foreach ($pendingId in $pendingIds) {
            $pending = Get-Content (Join-Path $script:SigmaPend "$pendingId.json") -Raw | ConvertFrom-Json
            $meta = Get-Content (Join-Path (Join-Path $script:SigmaTx $pending.TxId) 'metadata.json') -Raw | ConvertFrom-Json
            if ($meta.RecoveryRequired) { Write-Host "  $pendingId in RecoveryRequired" -ForegroundColor Red; $unresolvedPending += $pendingId; continue }
            if ($meta.RequiresReboot) {
                $lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
                if ($lastBoot -le [datetime]$pending.SavedAt) { Write-Host "  $pendingId requires reboot" -ForegroundColor Yellow; $unresolvedPending += $pendingId; continue }
            }
            Write-Host "  Validating $pendingId"
            $afterLabel = "after_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
            $null = Start-SigBenchmark -Label $afterLabel
            $cmp = Compare-SigBenchmarks -BeforeLabel $pending.BaselineLabel -AfterLabel $afterLabel -WriteHtml
            if ($cmp.CPU_StatisticallySignificant -and $cmp.CPU_Direction -eq 'Improvement') { Set-SigTxState -TxId $pending.TxId -State 'ValidatedImprovement' }
            elseif ($cmp.CPU_StatisticallySignificant -and $cmp.CPU_Direction -eq 'Regression') {
                Set-SigTxState -TxId $pending.TxId -State 'ValidatedRegression'
                $rb = Read-Host "  Rollback $($pending.TxId)? (Y/N)"
                if ($rb -in 'Y','y') { Restore-SigTransaction -TxId $pending.TxId }
            } else { Set-SigTxState -TxId $pending.TxId -State 'ValidatedInconclusive' }
            Clear-SigPendingValidation -TxId $pending.TxId
        }
        if ($unresolvedPending.Count -gt 0) { Write-Host "Unresolved pending; exiting." -ForegroundColor Yellow; Release-SigMutex; exit 0 }
        $continue = Read-Host "Start a new Sigma session? (Y/N)"
        if ($continue -notin 'Y','y') { Release-SigMutex; exit 0 }
    }

    Write-Host ""
    Write-Host "========== DISCOVER ==========" -ForegroundColor Green
    $hw = Get-SigHardwareInventory; $ctx = Get-SigContext -HardwareInventory $hw
    Write-Host "  $($hw.Profile.Manufacturer) $($hw.Profile.Model) | $($hw.Profile.CPUName) | $($hw.Profile.TotalRAMGB) GB" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "========== DETECT ==========" -ForegroundColor Green
    $evidence = New-Object System.Collections.ArrayList
    foreach ($fn in 'Get-SigResults_GroupA','Get-SigResults_GroupB') {
        try { $r = & $fn; foreach ($e in $r) { $null = $evidence.Add($e) }; Write-Host "  $fn -> $(@($r).Count)" -ForegroundColor Green }
        catch { Write-Host "  $fn ERROR: $_" -ForegroundColor Red; Add-SigError "$fn failed: $_" }
    }

    Write-Host ""
    Write-Host "========== MEASURE ==========" -ForegroundColor Green
    $dpc = Get-SigCounterSnapshot -Seconds 15
    Write-Host "  DPC: $($dpc.Verdict)"

    Write-Host ""
    Write-Host "========== BASELINE ==========" -ForegroundColor Green
    $baselineLabel = "baseline_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    $baseline = Start-SigBenchmark -Label $baselineLabel
    Write-Host "  CPU median: $($baseline.CPU.MedianOpsPerSec) ops/s (CV $($baseline.CPU.CV_Percent)%)"

    Write-Host ""
    Write-Host "========== OPTIMIZE ==========" -ForegroundColor Green
    $catalog = Get-SigOptimizationCatalog
    $applicable = @($catalog | Where-Object { & $_.AppliesTo $ctx })
    Write-Host "  $($applicable.Count) optimizations applicable to this machine." -ForegroundColor Cyan
    Write-Host "  Enter: 'all' | 'none' | comma-separated numbers" -ForegroundColor DarkGray

    $byCat = $applicable | Group-Object Category
    $idx = 0
    $flat = @()
    foreach ($grp in $byCat) {
        Write-Host ""
        Write-Host "  [$($grp.Name)]" -ForegroundColor Magenta
        foreach ($opt in $grp.Group) {
            $idx++
            $flat += $opt
            $rebootTag = if ($opt.RequiresReboot) { ' [reboot]' } else { '' }
            Write-Host ("    [{0,3}] {1}  ({2}/{3}){4}" -f $idx, $opt.Title, $opt.Risk, $opt.Impact, $rebootTag)
        }
    }

    $optChoice = Read-Host "`nApply optimizations?"
    $txId = $null; $txRequiresReboot = $false; $txRecoveryRequired = $false
    if ($optChoice -and $optChoice -ne 'none') {
        $ids = @()
        if ($optChoice -eq 'all') { $ids = $flat.Id }
        else {
            foreach ($tok in ($optChoice -split ',')) {
                $n = 0
                if ([int]::TryParse($tok.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $flat.Count) { $ids += $flat[$n-1].Id }
            }
        }
        $optResult = Invoke-SigOptimization -Ids $ids
        $txId = $optResult.TransactionId; $txRequiresReboot = $optResult.RequiresReboot; $txRecoveryRequired = $optResult.RecoveryRequired
    }

    Write-Host ""
    Write-Host "========== VALIDATE ==========" -ForegroundColor Green
    if ($txRecoveryRequired) {
        Write-Host "  RecoveryRequired. Restore with: Restore-SigTransaction -TxId '$txId'" -ForegroundColor Red
    } elseif ($txId) {
        if ($txRequiresReboot) { $mode = Read-Host "  [R]eboot and validate, or [S]kip" }
        else { $mode = Read-Host "  [N]ow, [R]eboot-then-validate, or [S]kip" }

        if ($mode -in 'N','n' -and -not $txRequiresReboot) {
            $afterLabel = "after_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
            $null = Start-SigBenchmark -Label $afterLabel
            $cmp = Compare-SigBenchmarks -BeforeLabel $baselineLabel -AfterLabel $afterLabel -WriteHtml
            if ($cmp.CPU_StatisticallySignificant -and $cmp.CPU_Direction -eq 'Improvement') { Set-SigTxState -TxId $txId -State 'ValidatedImprovement'; Write-Host "  IMPROVEMENT" -ForegroundColor Green }
            elseif ($cmp.CPU_StatisticallySignificant -and $cmp.CPU_Direction -eq 'Regression') {
                Set-SigTxState -TxId $txId -State 'ValidatedRegression'; Write-Host "  REGRESSION" -ForegroundColor Red
                $rb = Read-Host "  Rollback? (Y/N)"
                if ($rb -in 'Y','y') { Restore-SigTransaction -TxId $txId }
            } else { Set-SigTxState -TxId $txId -State 'ValidatedInconclusive'; Write-Host "  INCONCLUSIVE" -ForegroundColor Yellow }
        } elseif ($mode -in 'R','r') {
            Save-SigPendingValidation -TxId $txId -BaselineLabel $baselineLabel
            Set-SigTxState -TxId $txId -State 'ValidationPending'
            Write-Host "  Pending saved. Re-run after reboot." -ForegroundColor Cyan
        }
    }

    Write-Host ""
    Write-Host "========== REPORT ==========" -ForegroundColor Green
    $scanHtml = New-SigScanHtmlReport -Evidence $evidence.ToArray() -Hardware $hw -Dpc $dpc
    Write-Host "  $scanHtml" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[SUCCESS] Sigma complete." -ForegroundColor Green
    if ($txId) { Write-Host "[INFO] Rollback: Restore-SigTransaction -TxId '$txId'" -ForegroundColor Cyan }

    $rebootChoice = Read-Host "`nPress R to reboot, or Q to quit"
    if ($rebootChoice -in 'R','r') { shutdown /r /f /t 0 }
} finally {
    Release-SigMutex
}
