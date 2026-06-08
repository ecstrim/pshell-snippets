<#
.SYNOPSIS
    Assessment permessi NTFS di un file server.
    Estrae le ACL delle cartelle e produce un CSV piatto (una riga per ACE).

.DESCRIPTION
    STADIO 1 della pipeline di assessment file server.
    Scansione di una o piu' radici, estrazione ACL, scrittura su CSV. Il CSV
    prodotto va poi passato a Convert-AclCsvToExcel.ps1 (STADIO 2) per
    ottenere l'Excel un-foglio-per-share.

    Scelte di design, tutte motivate dai problemi del deliverable precedente:

    - UNA RIGA PER ACE. Lo script vecchio concatenava tutte le ACE di una
      cartella in una cella separandole con '|'. Quel formato ha reso
      invisibile per settimane un bug di accumulo (ogni cartella ereditava
      nell'output le ACE di quelle prima). Una riga per ACE: se l'accumulo
      tornasse, si vedrebbe a colpo d'occhio.

    - STREAMING su StreamWriter. Ogni ACE viene scritta su disco appena
      letta; non si accumula una lista di risultati in RAM. Il working set
      e' limitato alla frontiera dello stack di discesa (DFS) piu' la cache
      SID, non al numero totale di cartelle.

    - .NET diretto (System.IO.Directory / FileSystemAclExtensions) invece di
      Get-ChildItem / Get-Acl: discesa un livello alla volta, controllo
      errore per-ramo, niente overhead del provider PowerShell per cartella.
      Un ramo illeggibile non fa morire l'intera scansione.

    - CACHE SID -> nome. Lo stesso gruppo compare su migliaia di cartelle:
      tradurre il suo SID una volta sola (hashtable per-radice) invece che a
      ogni cartella e' la singola ottimizzazione piu' grande, e mette al
      riparo dal blocco classico su SID orfani (account cancellati o domini
      irraggiungibili che vanno in timeout a ogni lookup).

    - SID ORFANI a referto. Le ACE il cui SID non si risolve in un nome sono
      marcate (colonna IdentityUnresolved): sono un reperto tipico
      dell'assessment (permessi residui di utenti cancellati).

    - OWNER in output. Il proprietario di una cartella e' un fatto ACL di
      prima classe (owner inattesi dopo una migrazione, CREATOR OWNER).

    - PERCORSI LUNGHI. I rami che superano i 248 caratteri vengono letti via
      prefisso \\?\ invece di essere saltati: niente buchi negli alberi
      profondi.

    - PARALLELISMO PER-RADICE (opt-in, -MaxParallel). Le radici sono
      indipendenti, quindi ognuna gira nel proprio runspace scrivendo i
      PROPRI file temporanei: nessun writer condiviso fra thread (era quella
      la classe di bug del deliverable vecchio). Alla fine il padre fonde i
      file parziali in un unico CSV. Su file server ad alta latenza (SMB)
      l'estrazione ACL e' latency-bound, e i carichi latency-bound traggono
      beneficio dalla concorrenza. Richiede PowerShell 7+; su 5.1 si degrada
      automaticamente a seriale.

.PARAMETER Roots
    Una o piu' cartelle radice da scansionare ricorsivamente.
    Tipicamente le share di primo livello del server.

.PARAMETER OutputDir
    Cartella dove scrivere CSV e log. Creata se non esiste.

.PARAMETER ServerLabel
    Etichetta del server, usata nei nomi file (es. 'ITTNFS01').

.PARAMETER SelectionMode
    Quali cartelle includere nell'export:
      NonInheritedOnly (default) - solo cartelle con almeno una ACE non
          ereditata. Le cartelle che ereditano tutto dal padre non
          aggiungono informazione.
      ProtectedOnly - solo cartelle con ereditarieta' disabilitata
          (AreAccessRulesProtected). Piu' restrittivo.
      All - tutte le cartelle.

.PARAMETER ExcludeSystemIdentities
    Se presente, scarta le ACE di NT AUTHORITY\*, BUILTIN\*, Everyone,
    CREATOR OWNER. I SID orfani NON vengono mai scartati (sono un reperto).
    Default: SPENTO (dato completo).

.PARAMETER MaxParallel
    Numero di radici elaborate in parallelo. Default 4. Valore 1 = seriale.
    Valori > 1 richiedono PowerShell 7+ (altrimenti fallback a seriale).

.PARAMETER MaxSkippedListed
    Quante cartelle saltate elencare a console nel riepilogo finale.
    Default 50. L'elenco completo e' sempre nel CSV -SKIPPED.

.EXAMPLE
    .\Get-AclAssessment.ps1 -Roots 'E:\Produzione','E:\Share' `
        -OutputDir 'C:\Temp\Assessment' -ServerLabel 'ITTNFS01' -MaxParallel 6

.NOTES
    Stadio 1 di 2. Per l'Excel finale lanciare poi Convert-AclCsvToExcel.ps1.
    Seriale: PowerShell 5.1+. Parallelo (-MaxParallel > 1): PowerShell 7+.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Roots,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$ServerLabel,

    [ValidateSet('NonInheritedOnly', 'ProtectedOnly', 'All')]
    [string]$SelectionMode = 'NonInheritedOnly',

    [switch]$ExcludeSystemIdentities,

    [int]$MaxParallel = 4,

    [int]$MaxSkippedListed = 50
)

$ErrorActionPreference = 'Stop'

# --- Capacita' runtime ----------------------------------------------------
$isPs7 = $PSVersionTable.PSVersion.Major -ge 7
if ($MaxParallel -gt 1 -and -not $isPs7) {
    Write-Warning "Parallelismo richiede PowerShell 7+. Esecuzione seriale."
    $MaxParallel = 1
}

# FileSystemAclExtensions: lettura ACL diretta senza overhead del provider.
# Se l'assembly non c'e' (alcune installazioni 5.1), si ripiega su Get-Acl.
$useExtAcl = $false
try { Add-Type -AssemblyName System.IO.FileSystem.AccessControl -ErrorAction SilentlyContinue } catch { }
try { $null = [System.IO.FileSystemAclExtensions]; $useExtAcl = $true } catch { $useExtAcl = $false }

# --- Preparazione output --------------------------------------------------
if (-not (Test-Path -LiteralPath $OutputDir)) {
    $null = New-Item -Path $OutputDir -ItemType Directory -Force
}

$ts         = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvHeader  = 'ShareRoot,ParentPath,FolderName,DirectoryFullName,Owner,Identity,IdentityUnresolved,AccessControlType,Rights,IsInherited,InheritanceFlags,PropagationFlags'
$skipHeader = 'Path,Reason,Detail'

$finalCsv  = Join-Path $OutputDir "ACL-$ServerLabel-$ts.csv"
$finalSkip = Join-Path $OutputDir "ACL-$ServerLabel-$ts-SKIPPED.csv"
$finalLog  = Join-Path $OutputDir "ACL-$ServerLabel-$ts.log"

# ==========================================================================
#  WORKER: scansione di UNA radice, autosufficiente.
#  Scrive i propri file temporanei e ritorna un oggetto di riepilogo. Tutte
#  le dipendenze passano per parametro: la funzione viene ricostituita tale
#  quale dentro i runspace di ForEach-Object -Parallel, dove lo scope dello
#  script padre non e' visibile. Gli helper sono annidati: l'ambito dinamico
#  di PowerShell li fa vedere variabili e parametri di Invoke-RootScan.
# ==========================================================================
function Invoke-RootScan {
    param(
        [pscustomobject]$Job,           # { Index; Root }
        [string]$OutputDir,
        [string]$ServerLabel,
        [string]$Ts,
        [string]$SelectionMode,
        [bool]$ExcludeSystemIdentities,
        [bool]$IsPs7,
        [bool]$UseExtAcl,
        [string]$CsvHeader,
        [string]$SkipHeader
    )

    $root  = $Job.Root
    $index = $Job.Index

    # --- helper: quoting CSV ---
    function Q { param([string]$s)
        if ($null -eq $s) { $s = '' }
        '"' + $s.Replace('"', '""') + '"'
    }

    # --- helper: percorsi lunghi (prefisso solo quando serve davvero) ---
    function ConvertTo-LongPath { param([string]$p)
        if ([string]::IsNullOrEmpty($p) -or $p.Length -lt 248 -or $p.StartsWith('\\?\')) { return $p }
        if ($p.StartsWith('\\')) { return '\\?\UNC\' + $p.Substring(2) }
        return '\\?\' + $p
    }
    function ConvertFrom-LongPath { param([string]$p)
        if ([string]::IsNullOrEmpty($p)) { return $p }
        if ($p.StartsWith('\\?\UNC\')) { return '\\' + $p.Substring(8) }
        if ($p.StartsWith('\\?\'))     { return $p.Substring(4) }
        return $p
    }

    # --- helper: cache SID -> nome (la chiave e' la stringa SID) ---
    $sidCache = @{}
    function Resolve-Sid { param($SidObj, [string]$SidStr)
        if ($sidCache.ContainsKey($SidStr)) { return $sidCache[$SidStr] }
        $name = $SidStr; $resolved = $false
        try   { $name = $SidObj.Translate([System.Security.Principal.NTAccount]).Value; $resolved = $true }
        catch { $name = $SidStr; $resolved = $false }
        $o = [pscustomobject]@{ Name = $name; Resolved = $resolved }
        $sidCache[$SidStr] = $o
        return $o
    }

    function Test-SystemIdentity { param([string]$Identity)
        return ($Identity.StartsWith('NT AUTHORITY\') -or
                $Identity.StartsWith('BUILTIN\')      -or
                $Identity -eq 'Everyone'              -or
                $Identity -eq 'CREATOR OWNER')
    }

    # --- helper: diritti leggibili (decodifica le maschere numeriche) ---
    function Convert-RightsToText { param($Rights)
        $s = $Rights.ToString()
        if ($s -notmatch '^-?\d+$') { return $s }   # gia' leggibile
        $val = [int]$Rights
        $names = foreach ($n in [System.Enum]::GetNames([System.Security.AccessControl.FileSystemRights])) {
            $fv = [int]([System.Security.AccessControl.FileSystemRights]$n)
            if ($fv -ne 0 -and ($val -band $fv) -eq $fv) { $n }
        }
        if ($names) { return (($names -join ', ') + (' (0x{0:X})' -f $val)) }
        return ('0x{0:X}' -f $val)
    }

    # --- helper: lettura ACL directory (veloce dove disponibile) ---
    function Get-DirAcl { param([string]$Path)
        $lp = ConvertTo-LongPath $Path
        if ($UseExtAcl)      { return [System.IO.FileSystemAclExtensions]::GetAccessControl([System.IO.DirectoryInfo]::new($lp)) }
        elseif (-not $IsPs7) { return (New-Object System.IO.DirectoryInfo $lp).GetAccessControl() }
        else                 { return (Get-Acl -LiteralPath $lp) }
    }

    function Write-Log { param([string]$Message)
        $logOut.WriteLine(("{0} - {1}" -f (Get-Date).ToString('s'), $Message))
    }
    function Write-Skip { param([string]$Path, [string]$Reason, [string]$Detail)
        $skipOut.WriteLine((Q $Path) + ',' + (Q $Reason) + ',' + (Q $Detail))
        Write-Log "SKIP ${Reason}: $Path"
    }

    # --- discesa iterativa con stack: niente ricorsione, errore per-ramo ---
    function Get-SubTree { param([string]$Start)
        $stack = [System.Collections.Generic.Stack[string]]::new()
        $stack.Push($Start)
        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            $current   # emesso sulla pipeline, non accumulato
            try {
                foreach ($childRaw in [System.IO.Directory]::GetDirectories((ConvertTo-LongPath $current))) {
                    $child = ConvertFrom-LongPath $childRaw
                    # GetAttributes in un try proprio: metadati di un ramo
                    # illeggibili saltano SOLO quel ramo, non i fratelli.
                    try { $attr = [System.IO.File]::GetAttributes((ConvertTo-LongPath $child)) }
                    catch { Write-Skip $child 'AttrUnreadable' $_.Exception.Message; continue }
                    # Reparse point (junction/symlink): saltati, altrimenti
                    # un link verso un antenato darebbe discesa infinita.
                    if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                        Write-Skip $child 'ReparsePoint' 'Junction/symlink saltato'; continue
                    }
                    $stack.Push($child)
                }
            }
            catch [System.UnauthorizedAccessException]  { Write-Skip $current 'Unauthorized' $_.Exception.Message }
            catch [System.IO.PathTooLongException]       { Write-Skip $current 'LongPath'     $_.Exception.Message }
            catch [System.IO.DirectoryNotFoundException] { Write-Skip $current 'NotFound'     $_.Exception.Message }
            catch                                        { Write-Skip $current 'Other'        $_.Exception.Message }
        }
    }

    # --- elaborazione di una cartella -> righe ACE su csvOut ---
    function Export-FolderAcl { param([string]$FolderPath)
        try { $acl = Get-DirAcl $FolderPath }
        catch {
            Write-Skip $FolderPath 'AclUnreadable' $_.Exception.Message
            return [pscustomobject]@{ Folders = 0; Aces = 0; Unresolved = 0 }
        }

        # Regole con target SID: niente traduzione automatica (la facciamo
        # noi, via cache). Una sola lettura, riusata per filtro e output.
        $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])

        switch ($SelectionMode) {
            'NonInheritedOnly' {
                $hasExplicit = $false
                foreach ($a in $rules) { if (-not $a.IsInherited) { $hasExplicit = $true; break } }
                if (-not $hasExplicit) { return [pscustomobject]@{ Folders = 0; Aces = 0; Unresolved = 0 } }
            }
            'ProtectedOnly' {
                if (-not $acl.AreAccessRulesProtected) { return [pscustomobject]@{ Folders = 0; Aces = 0; Unresolved = 0 } }
            }
            'All' { }
        }

        # Nome/parent via stringa: nessun I/O, immune ai percorsi lunghi.
        $folderName = [System.IO.Path]::GetFileName($FolderPath)
        if ([string]::IsNullOrEmpty($folderName)) { $folderName = $FolderPath }   # radice tipo 'E:\'
        $parent = [System.IO.Path]::GetDirectoryName($FolderPath)
        if ($null -eq $parent) { $parent = '' }

        $ownerName = ''
        try {
            $ownerRef  = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
            $ownerName = (Resolve-Sid $ownerRef $ownerRef.Value).Name
        } catch { $ownerName = '(owner illeggibile)' }

        $aces = 0; $unres = 0
        foreach ($ace in $rules) {
            $sidObj = $ace.IdentityReference
            $res    = Resolve-Sid $sidObj $sidObj.Value
            $identity = $res.Name

            if ($ExcludeSystemIdentities -and $res.Resolved -and (Test-SystemIdentity $identity)) { continue }

            $isUnres = -not $res.Resolved
            if ($isUnres) { $unres++ }

            $line = @(
                (Q $root)
                (Q $parent)
                (Q $folderName)
                (Q $FolderPath)
                (Q $ownerName)
                (Q $identity)
                (Q $isUnres.ToString())
                (Q $ace.AccessControlType.ToString())
                (Q (Convert-RightsToText $ace.FileSystemRights))
                (Q $ace.IsInherited.ToString())
                (Q $ace.InheritanceFlags.ToString())
                (Q $ace.PropagationFlags.ToString())
            ) -join ','
            $csvOut.WriteLine($line)
            $aces++
        }

        if ($aces -eq 0) {
            $line = @(
                (Q $root), (Q $parent), (Q $folderName), (Q $FolderPath), (Q $ownerName),
                (Q '(nessuna ACE in output)'), (Q ''), (Q ''), (Q ''), (Q ''), (Q ''), (Q '')
            ) -join ','
            $csvOut.WriteLine($line)
            Write-Log "NOTE cartella senza ACE in output: $FolderPath"
        }
        return [pscustomobject]@{ Folders = 1; Aces = $aces; Unresolved = $unres }
    }

    # --- file temporanei per QUESTA radice (unici grazie all'indice) ---
    $safe = ($root -replace '[^A-Za-z0-9]', '_')
    $tag  = '{0:D3}-{1}' -f $index, $safe
    $csvPath  = Join-Path $OutputDir "ACL-$ServerLabel-$tag-$Ts.part.csv"
    $skipPath = Join-Path $OutputDir "ACL-$ServerLabel-$tag-$Ts.skip.csv"
    $logPath  = Join-Path $OutputDir "ACL-$ServerLabel-$tag-$Ts.part.log"

    $enc     = [System.Text.UTF8Encoding]::new($false)   # UTF-8 senza BOM
    $csvOut  = [System.IO.StreamWriter]::new($csvPath, $false, $enc)
    $skipOut = [System.IO.StreamWriter]::new($skipPath, $false, $enc)
    $logOut  = [System.IO.StreamWriter]::new($logPath, $false, $enc)

    # Header in cima a ogni parte: la fusione salta la prima riga di ognuna.
    $csvOut.WriteLine($CsvHeader)
    $skipOut.WriteLine($SkipHeader)

    $stats   = @{ Folders = 0; Aces = 0; Unresolved = 0 }
    $existed = $true
    $sw      = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not [System.IO.Directory]::Exists((ConvertTo-LongPath $root))) {
            Write-Log "SKIP radice inesistente: $root"
            $existed = $false
        }
        else {
            Write-Log "Scansione radice: $root"
            $nextFlush = 500
            Get-SubTree -Start $root | ForEach-Object {
                $r = Export-FolderAcl -FolderPath $_
                $stats['Folders']    += $r.Folders
                $stats['Aces']       += $r.Aces
                $stats['Unresolved'] += $r.Unresolved
                if ($stats['Folders'] -ge $nextFlush) {
                    $csvOut.Flush(); $skipOut.Flush(); $logOut.Flush()
                    $rate = $stats['Folders'] / [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
                    Write-Log ("  ...{0} cartelle, {1} ACE - {2:N0} cart/s" -f $stats['Folders'], $stats['Aces'], $rate)
                    $nextFlush += 500
                }
            }
            Write-Log ("Radice completata: {0} cartelle, {1} ACE, {2} SID non risolti" -f $stats['Folders'], $stats['Aces'], $stats['Unresolved'])
        }
    }
    finally {
        $csvOut.Close(); $skipOut.Close(); $logOut.Close()
    }
    $sw.Stop()

    return [pscustomobject]@{
        Root            = $root
        Existed         = $existed
        Index           = $index
        CsvPath         = $csvPath
        SkipPath        = $skipPath
        LogPath         = $logPath
        FoldersExported = $stats['Folders']
        AceWritten      = $stats['Aces']
        AceUnresolved   = $stats['Unresolved']
        ElapsedSeconds  = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
    }
}

# ==========================================================================
#  Fusione dei file parziali in un unico file finale (streaming, no RAM).
# ==========================================================================
function Merge-Parts { param([string[]]$Parts, [string]$Dest, [string]$Header)
    $enc = [System.Text.UTF8Encoding]::new($false)
    $out = [System.IO.StreamWriter]::new($Dest, $false, $enc)
    try {
        $out.WriteLine($Header)
        foreach ($p in $Parts) {
            if ([string]::IsNullOrEmpty($p) -or -not (Test-Path -LiteralPath $p)) { continue }
            $reader = [System.IO.StreamReader]::new($p)
            try {
                $null = $reader.ReadLine()   # scarta l'header della parte
                while ($null -ne ($l = $reader.ReadLine())) { $out.WriteLine($l) }
            }
            finally { $reader.Close() }
        }
    }
    finally { $out.Close() }
}

function Merge-Logs { param([string[]]$Parts, [string]$Dest)
    $enc = [System.Text.UTF8Encoding]::new($false)
    $out = [System.IO.StreamWriter]::new($Dest, $false, $enc)
    try {
        foreach ($p in $Parts) {
            if ([string]::IsNullOrEmpty($p) -or -not (Test-Path -LiteralPath $p)) { continue }
            $out.WriteLine("===== $p =====")
            $reader = [System.IO.StreamReader]::new($p)
            try { while ($null -ne ($l = $reader.ReadLine())) { $out.WriteLine($l) } }
            finally { $reader.Close() }
        }
    }
    finally { $out.Close() }
}

# ==========================================================================
#  MAIN
# ==========================================================================
$rootJobs = 0..($Roots.Count - 1) | ForEach-Object { [pscustomobject]@{ Index = $_; Root = $Roots[$_] } }

Write-Host "Avvio assessment - server $ServerLabel - modo $SelectionMode - parallelismo $MaxParallel - lettura ACL $(if ($useExtAcl) {'diretta'} else {'Get-Acl'})"
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

if ($MaxParallel -gt 1) {
    # La funzione viene ricostituita identica in ogni runspace via $using.
    $workerDef = ${function:Invoke-RootScan}.ToString()
    $done = 0
    $summaries = $rootJobs | ForEach-Object -ThrottleLimit $MaxParallel -Parallel {
        ${function:Invoke-RootScan} = $using:workerDef
        Invoke-RootScan -Job $_ -OutputDir $using:OutputDir -ServerLabel $using:ServerLabel `
            -Ts $using:ts -SelectionMode $using:SelectionMode `
            -ExcludeSystemIdentities ([bool]$using:ExcludeSystemIdentities) `
            -IsPs7 $true -UseExtAcl $using:useExtAcl `
            -CsvHeader $using:csvHeader -SkipHeader $using:skipHeader
    } | ForEach-Object {
        $done++
        Write-Progress -Activity 'Assessment ACL (parallelo)' `
            -Status ("Radici completate {0}/{1} - ultima: {2} ({3} cartelle, {4:N0} cart/s)" -f `
                $done, $rootJobs.Count, $_.Root, $_.FoldersExported, ($_.FoldersExported / [Math]::Max($_.ElapsedSeconds, 0.001))) `
            -PercentComplete ($done / $rootJobs.Count * 100)
        $_
    }
    Write-Progress -Activity 'Assessment ACL (parallelo)' -Completed
}
else {
    $summaries = foreach ($job in $rootJobs) {
        Write-Progress -Activity 'Assessment ACL (seriale)' `
            -Status ("Radice {0}/{1}: {2}" -f ($job.Index + 1), $rootJobs.Count, $job.Root) `
            -PercentComplete ($job.Index / $rootJobs.Count * 100)
        Invoke-RootScan -Job $job -OutputDir $OutputDir -ServerLabel $ServerLabel `
            -Ts $ts -SelectionMode $SelectionMode `
            -ExcludeSystemIdentities ([bool]$ExcludeSystemIdentities) `
            -IsPs7 $isPs7 -UseExtAcl $useExtAcl `
            -CsvHeader $csvHeader -SkipHeader $skipHeader
    }
    Write-Progress -Activity 'Assessment ACL (seriale)' -Completed
}

$summaries = @($summaries)

# --- Fusione parti -> file finali, poi pulizia dei temporanei ---
Merge-Parts -Parts $summaries.CsvPath  -Dest $finalCsv  -Header $csvHeader
Merge-Parts -Parts $summaries.SkipPath -Dest $finalSkip -Header $skipHeader
Merge-Logs  -Parts $summaries.LogPath  -Dest $finalLog
foreach ($p in ($summaries.CsvPath + $summaries.SkipPath + $summaries.LogPath)) {
    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
}

$swAll.Stop()

# --- Riepilogo copertura --------------------------------------------------
$totFolders = ($summaries | Measure-Object -Property FoldersExported -Sum).Sum
$totAces    = ($summaries | Measure-Object -Property AceWritten      -Sum).Sum
$totUnres   = ($summaries | Measure-Object -Property AceUnresolved   -Sum).Sum
$missing    = @($summaries | Where-Object { -not $_.Existed })
$skipRows   = @(Import-Csv -LiteralPath $finalSkip -Encoding UTF8)

Write-Host ""
Write-Host "Stadio 1 completato - server $ServerLabel"
Write-Host "  CSV ACL  : $finalCsv"
Write-Host "  CSV skip : $finalSkip"
Write-Host "  Log      : $finalLog"
Write-Host ("  Cartelle esportate: {0}  -  ACE: {1}  -  durata: {2}" -f $totFolders, $totAces, $swAll.Elapsed)
if ($totUnres -gt 0) {
    Write-Host ("  ATTENZIONE: {0} ACE con SID NON risolto (account orfani?) - colonna IdentityUnresolved" -f $totUnres) -ForegroundColor Yellow
}
if ($missing.Count -gt 0) {
    Write-Host ("  Radici inesistenti saltate ({0}):" -f $missing.Count) -ForegroundColor Yellow
    foreach ($m in $missing) { Write-Host "    $($m.Root)" -ForegroundColor Yellow }
}

# --- Cartelle saltate: conteggio per motivo + elenco nomi/percorsi ---
if ($skipRows.Count -gt 0) {
    Write-Host ""
    Write-Host ("Cartelle saltate: {0} totali" -f $skipRows.Count) -ForegroundColor Yellow
    $skipRows | Group-Object Reason | Sort-Object Count -Descending | ForEach-Object {
        Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Count) -ForegroundColor Yellow
    }
    Write-Host ("  Elenco (primi {0}):" -f [Math]::Min($MaxSkippedListed, $skipRows.Count))
    foreach ($s in ($skipRows | Select-Object -First $MaxSkippedListed)) {
        Write-Host ("    [{0,-14}] {1}" -f $s.Reason, $s.Path)
    }
    if ($skipRows.Count -gt $MaxSkippedListed) {
        Write-Host ("    ... e altre {0}. Elenco completo in: {1}" -f ($skipRows.Count - $MaxSkippedListed), $finalSkip)
    }
}
else {
    Write-Host ""
    Write-Host "Nessuna cartella saltata: copertura completa."
}

Write-Host ""
Write-Host "Stadio 2: convertire il CSV in Excel con"
Write-Host "  .\Convert-AclCsvToExcel.ps1 -CsvPath '$finalCsv' -ServerLabel '$ServerLabel'"
