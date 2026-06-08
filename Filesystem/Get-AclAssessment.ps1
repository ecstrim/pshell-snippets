<#
.SYNOPSIS
    Assessment permessi NTFS di un file server.
    Estrae le ACL delle cartelle e produce un CSV piatto (una riga per ACE).

.DESCRIPTION
    STADIO 1 della pipeline di assessment file server.
    Scansione di una o piu' radici, estrazione ACL, scrittura su CSV in
    streaming. Il CSV prodotto va poi passato a Convert-AclCsvToExcel.ps1
    (STADIO 2) per ottenere l'Excel un-foglio-per-share.

    Scelte di design, tutte motivate dai problemi del deliverable precedente:

    - UNA RIGA PER ACE. Lo script vecchio concatenava tutte le ACE di una
      cartella in una cella separandole con '|'. Quel formato ha reso
      invisibile per settimane un bug di accumulo (ogni cartella ereditava
      nell'output le ACE di quelle prima). Una riga per ACE: se l'accumulo
      tornasse, si vedrebbe a colpo d'occhio.

    - STREAMING su StreamWriter. Niente lista di risultati in RAM: ogni ACE
      viene scritta su disco appena letta. Il working set resta proporzionale
      alla PROFONDITA' dell'albero, non al numero totale di cartelle.
      Ripreso da exportACLS_heavy: Get-ChildItem -Recurse e l'accumulo in
      array erano "troppo affamati" su share grandi.

    - .NET diretto (System.IO.Directory) invece di Get-ChildItem: discesa
      un livello alla volta e controllo errore per-ramo. Un ramo illeggibile
      non fa morire l'intera scansione.

    - AccessControlType (Allow/Deny) SEMPRE in output. Nei file consegnati
      mancava: un Deny esplicito e' la causa classica di "utente nel gruppo
      ma che non vede la cartella", e senza quella colonna era invisibile.

    - Niente parallelismo. L'estrazione e' I/O-bound, non CPU-bound: i
      runspace renderebbero poco. E un writer condiviso fra thread e'
      esattamente la classe di bug che ha rotto il deliverable precedente.
      Un output seriale e ordinato e' verificabile; uno concorrente no.

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
          ereditata. E' la logica di assessment originale: le cartelle che
          ereditano tutto dal padre non aggiungono informazione.
      ProtectedOnly - solo cartelle con ereditarieta' disabilitata
          (AreAccessRulesProtected). Piu' restrittivo.
      All - tutte le cartelle.

.PARAMETER ExcludeSystemIdentities
    Se presente, scarta le ACE di NT AUTHORITY\*, BUILTIN\*, Everyone,
    CREATOR OWNER. Default: SPENTO (dato completo). Accendere solo se serve
    un output confrontabile con un deliverable precedente che le filtrava.

.EXAMPLE
    .\Get-AclAssessment.ps1 -Roots 'E:\Produzione','E:\Share' `
        -OutputDir 'C:\Temp\Assessment' -ServerLabel 'ITTNFS01' -Verbose

.NOTES
    Stadio 1 di 2. Per l'Excel finale lanciare poi Convert-AclCsvToExcel.ps1.
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

    [switch]$ExcludeSystemIdentities
)

$ErrorActionPreference = 'Stop'

# --- Preparazione output --------------------------------------------------
if (-not (Test-Path -LiteralPath $OutputDir)) {
    $null = New-Item -Path $OutputDir -ItemType Directory -Force
}

$ts        = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath   = Join-Path $OutputDir "ACL-$ServerLabel-$ts.csv"
$skipPath  = Join-Path $OutputDir "ACL-$ServerLabel-$ts-SKIPPED.csv"
$logPath   = Join-Path $OutputDir "ACL-$ServerLabel-$ts.log"

# StreamWriter: l'output viene scritto riga per riga, mai accumulato in RAM.
# UTF8 SENZA BOM: con il BOM la prima intestazione diventa "﻿ShareRoot"
# e qualsiasi consumatore diverso da Import-Csv (Excel "Get Data", awk...)
# vede il marcatore attaccato alla prima colonna.
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$csvOut  = [System.IO.StreamWriter]::new($csvPath, $false, $utf8NoBom)
$skipOut = [System.IO.StreamWriter]::new($skipPath, $false, $utf8NoBom)
$logOut  = [System.IO.StreamWriter]::new($logPath, $false, $utf8NoBom)

# Intestazioni. La colonna ShareRoot serve allo stadio 2 per sapere in
# quale foglio Excel mettere la riga (un foglio per share).
# Flush subito dopo ogni header: senza, i buffer dei tre StreamWriter
# possono scriversi in ordine non deterministico e l'header di un file
# finire in un altro (visto in test). Un Flush esplicito li ancora.
$csvOut.WriteLine('ShareRoot,ParentPath,FolderName,DirectoryFullName,Identity,AccessControlType,Rights,IsInherited,InheritanceFlags')
$csvOut.Flush()
$skipOut.WriteLine('Path,Reason,Detail')
$skipOut.Flush()

function Write-Log {
    param([string]$Message)
    $line = "{0} - {1}" -f (Get-Date).ToString('s'), $Message
    $logOut.WriteLine($line)
    Write-Verbose $Message
}

# Quoting CSV: raddoppia le doppie virgolette e racchiude il campo.
# I nomi cartella possono contenere virgole, spazi, apostrofi.
function Q { param([string]$s)
    if ($null -eq $s) { $s = '' }
    '"' + $s.Replace('"', '""') + '"'
}

# Identita' "di sistema" da scartare se -ExcludeSystemIdentities e' attivo.
function Test-SystemIdentity {
    param([string]$Identity)
    return ($Identity.StartsWith('NT AUTHORITY\') -or
            $Identity.StartsWith('BUILTIN\')      -or
            $Identity -eq 'Everyone'              -or
            $Identity -eq 'CREATOR OWNER')
}

# --- Enumerazione directory ----------------------------------------------
# Discesa iterativa con uno stack: niente ricorsione (niente rischio di
# stack overflow su alberi profondi) e niente Get-ChildItem -Recurse
# (che muore al primo ramo illeggibile perdendo tutto il sottoalbero).
function Get-SubTree {
    param([string]$Root)

    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($Root)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $current   # emesso sulla pipeline, non accumulato

        try {
            foreach ($child in [System.IO.Directory]::GetDirectories($current)) {
                # Salta i reparse point (junction / symlink): seguirli puo'
                # creare loop infiniti (link verso un antenato) o doppi
                # conteggi. Lo stack non tiene un set di visitati, quindi il
                # filtro va fatto qui, prima di spingere il ramo.
                # GetAttributes in un try PROPRIO: se i metadati di un ramo
                # sono illeggibili (es. cancellato nel frattempo) si salta
                # SOLO quel ramo, senza abortire l'enumerazione dei fratelli.
                try {
                    $attr = [System.IO.File]::GetAttributes($child)
                }
                catch {
                    $skipOut.WriteLine((Q $child) + ',' + (Q 'AttrUnreadable') + ',' + (Q $_.Exception.Message))
                    Write-Log "SKIP AttrUnreadable: $child"
                    continue
                }
                if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $skipOut.WriteLine((Q $child) + ',' + (Q 'ReparsePoint') + ',' + (Q 'Junction/symlink saltato'))
                    Write-Log "SKIP ReparsePoint: $child"
                    continue
                }
                $stack.Push($child)
            }
        }
        catch [System.UnauthorizedAccessException] {
            $skipOut.WriteLine((Q $current) + ',' + (Q 'Unauthorized') + ',' + (Q $_.Exception.Message))
            Write-Log "SKIP Unauthorized: $current"
        }
        catch [System.IO.PathTooLongException] {
            $skipOut.WriteLine((Q $current) + ',' + (Q 'LongPath') + ',' + (Q $_.Exception.Message))
            Write-Log "SKIP LongPath: $current"
        }
        catch [System.IO.DirectoryNotFoundException] {
            $skipOut.WriteLine((Q $current) + ',' + (Q 'NotFound') + ',' + (Q $_.Exception.Message))
            Write-Log "SKIP NotFound: $current"
        }
        catch {
            $skipOut.WriteLine((Q $current) + ',' + (Q 'Other') + ',' + (Q $_.Exception.Message))
            Write-Log "SKIP Other: $current - $($_.Exception.Message)"
        }
    }
}

# --- Elaborazione di una cartella ----------------------------------------
function Export-FolderAcl {
    param([string]$FolderPath, [string]$ShareRoot)

    try {
        $acl = Get-Acl -LiteralPath $FolderPath
    }
    catch {
        $skipOut.WriteLine((Q $FolderPath) + ',' + (Q 'AclUnreadable') + ',' + (Q $_.Exception.Message))
        Write-Log "SKIP AclUnreadable: $FolderPath"
        return 0
    }

    # Filtro di selezione: la cartella va inclusa?
    switch ($SelectionMode) {
        'NonInheritedOnly' {
            $hasExplicit = $false
            foreach ($a in $acl.Access) { if (-not $a.IsInherited) { $hasExplicit = $true; break } }
            if (-not $hasExplicit) { return 0 }
        }
        'ProtectedOnly' {
            if (-not $acl.AreAccessRulesProtected) { return 0 }
        }
        'All' { }   # nessun filtro
    }

    $dir    = [System.IO.DirectoryInfo]::new($FolderPath)
    $parent = if ($null -ne $dir.Parent) { $dir.Parent.FullName } else { '' }

    # $written e' LOCALE a questa chiamata: conta solo le ACE di QUESTA
    # cartella. Non esiste alcuna struttura condivisa che cresce: e' la
    # garanzia strutturale contro il bug di accumulo del deliverable vecchio.
    $written = 0
    foreach ($ace in $acl.Access) {
        $identity = $ace.IdentityReference.Value

        if ($ExcludeSystemIdentities -and (Test-SystemIdentity $identity)) {
            continue
        }

        $line = @(
            (Q $ShareRoot)
            (Q $parent)
            (Q $dir.Name)
            (Q $FolderPath)
            (Q $identity)
            (Q $ace.AccessControlType.ToString())   # Allow / Deny
            (Q $ace.FileSystemRights.ToString())
            (Q $ace.IsInherited.ToString())
            (Q $ace.InheritanceFlags.ToString())
        ) -join ','
        $csvOut.WriteLine($line)
        $written++
    }

    # Cartella inclusa dal filtro ma con zero ACE in output: anomalia,
    # va comunque a referto con un marcatore esplicito.
    if ($written -eq 0) {
        $line = @(
            (Q $ShareRoot), (Q $parent), (Q $dir.Name), (Q $FolderPath),
            (Q '(nessuna ACE in output)'), (Q ''), (Q ''), (Q ''), (Q '')
        ) -join ','
        $csvOut.WriteLine($line)
        Write-Log "NOTE cartella senza ACE in output: $FolderPath"
    }
    return 1
}

# --- Main -----------------------------------------------------------------
Write-Log "Avvio assessment - server $ServerLabel - modo $SelectionMode - escludiSystem=$ExcludeSystemIdentities"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$grandTotal = 0

# try/finally: un errore terminante (ErrorActionPreference = 'Stop') o un
# Ctrl-C nel mezzo di una scansione lunga deve comunque chiudere i tre
# StreamWriter. Senza, i file restano lockati e troncati - esattamente il
# fallimento che lo streaming doveva evitare.
try {
    foreach ($root in $Roots) {

        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            Write-Warning "Radice inesistente, saltata: $root"
            Write-Log "SKIP radice inesistente: $root"
            continue
        }

        Write-Log "Scansione radice: $root"
        $count = 0
        $nextFlush = 500

        # La radice stessa e poi tutto il sottoalbero, in streaming VERO:
        # la pipe a ForEach-Object processa ogni cartella appena emessa.
        # Con 'foreach ($x in (Get-SubTree ...))' la parentesi verrebbe
        # valutata per intero PRIMA del ciclo, bufferizzando in RAM l'elenco
        # completo delle directory - proprio cio' che il design vuole evitare.
        Get-SubTree -Root $root | ForEach-Object {
            $count += (Export-FolderAcl -FolderPath $_ -ShareRoot $root)
            if ($count -ge $nextFlush) {
                Write-Log "  ...$count cartelle esportate da $root"
                # Flush periodico: in caso di crash su scansione lunga,
                # il CSV su disco e' comunque coerente fino a qui.
                $csvOut.Flush(); $skipOut.Flush(); $logOut.Flush()
                $nextFlush += 500
            }
        }

        Write-Log "Radice $root completata: $count cartelle esportate."
        $grandTotal += $count
    }

    $sw.Stop()
    Write-Log "FINE. Cartelle esportate totali: $grandTotal - durata $($sw.Elapsed)"
}
finally {
    # Chiusura stream: senza questo i file restano incompleti/lockati.
    if ($csvOut)  { $csvOut.Close() }
    if ($skipOut) { $skipOut.Close() }
    if ($logOut)  { $logOut.Close() }
}

Write-Host ""
Write-Host "Stadio 1 completato - server $ServerLabel"
Write-Host "  CSV ACL  : $csvPath"
Write-Host "  CSV skip : $skipPath"
Write-Host "  Log      : $logPath"
Write-Host "  Cartelle esportate: $grandTotal  -  durata: $($sw.Elapsed)"
Write-Host ""
Write-Host "Stadio 2: convertire il CSV in Excel con"
Write-Host "  .\Convert-AclCsvToExcel.ps1 -CsvPath '$csvPath' -ServerLabel '$ServerLabel'"
