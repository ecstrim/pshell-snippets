<#
.SYNOPSIS
    Converte il CSV piatto prodotto da Get-AclAssessment.ps1 in un file
    Excel: un foglio Summary piu' un foglio per ogni share.

.DESCRIPTION
    STADIO 2 della pipeline di assessment file server.

    Questo e' il punto in cui il deliverable precedente si era rotto: la
    versione di Valter, ripivotando il CSV in Excel, accumulava le ACL
    (ogni cartella ereditava nell'output le ACE di quelle elaborate prima).
    Causa tipica: una variabile collezione riusata fra iterazioni.

    Qui l'accumulo e' reso strutturalmente impossibile:
    - si scrive UNA RIGA PER ACE, esattamente come arrivano dal CSV;
    - ogni riga del CSV diventa una e una sola riga di foglio;
    - non esiste nessuna variabile che concatena ACE fra cartelle diverse.
    Lo script non interpreta ne' raggruppa: copia righe. Se il CSV e'
    corretto (e lo stadio 1 garantisce che lo sia), l'Excel lo e'.

    Richiede il modulo ImportExcel (PowerShell Gallery). Se assente:
        Install-Module ImportExcel -Scope CurrentUser

.PARAMETER CsvPath
    Il CSV prodotto dallo stadio 1.

.PARAMETER ServerLabel
    Etichetta server, usata nel nome del file Excel.

.PARAMETER OutputDir
    Cartella di destinazione dell'Excel. Default: cartella del CSV.

.EXAMPLE
    .\Convert-AclCsvToExcel.ps1 -CsvPath 'C:\Temp\ACL-ITTNFS01-20260526_101500.csv' `
        -ServerLabel 'ITTNFS01'

.NOTES
    Stadio 2 di 2. Eseguire dopo Get-AclAssessment.ps1.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [string]$ServerLabel,

    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CsvPath)) {
    Write-Error "CSV non trovato: $CsvPath"; exit 1
}

if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Error ("Modulo ImportExcel non installato. " +
                 "Eseguire: Install-Module ImportExcel -Scope CurrentUser")
    exit 1
}
Import-Module ImportExcel

if (-not $OutputDir) { $OutputDir = Split-Path -Parent $CsvPath }
$xlsxPath = Join-Path $OutputDir "Assessment-$ServerLabel-$(Get-Date -Format 'yyyyMMdd').xlsx"
if (Test-Path -LiteralPath $xlsxPath) { Remove-Item -LiteralPath $xlsxPath -Force }

Write-Host "Lettura CSV: $CsvPath"
$rows = Import-Csv -LiteralPath $CsvPath -Encoding UTF8
Write-Host "  righe ACE lette: $($rows.Count)"

if ($rows.Count -eq 0) {
    Write-Warning "CSV vuoto: nessun Excel prodotto."
    exit 0
}

# Raggruppamento per share. Group-Object NON accumula: ogni gruppo
# contiene esattamente le proprie righe, e ogni riga sta in un solo gruppo.
$byShare = $rows | Group-Object -Property ShareRoot

# Excel non ammette nomi foglio > 31 caratteri o con \ / ? * [ ] :
# Si deriva un nome foglio leggibile e univoco dalla share.
# 'Summary' e' pre-occupato: una share la cui foglia si chiama "Summary"
# altrimenti genererebbe lo stesso nome del foglio riassuntivo e lo
# sovrascriverebbe (i nomi foglio Excel sono case-insensitive).
$usedNames = @{ 'Summary' = $true }
function Get-SheetName {
    param([string]$ShareRoot)
    # ultimo segmento del path, ripulito
    $leaf = Split-Path -Leaf $ShareRoot
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = $ShareRoot }
    $clean = ($leaf -replace '[\\/\?\*\[\]:]', '_')
    if ($clean.Length -gt 31) { $clean = $clean.Substring(0, 31) }
    # garanzia di univocita': se collide, suffisso numerico
    $base = $clean; $i = 1
    while ($usedNames.ContainsKey($clean)) {
        $suffix = "_$i"
        $clean = $base.Substring(0, [Math]::Min($base.Length, 31 - $suffix.Length)) + $suffix
        $i++
    }
    $usedNames[$clean] = $true
    return $clean
}

# --- Foglio Summary -------------------------------------------------------
# Una riga per share: conteggi di base. Niente di ricavato dalle altre
# share, ogni riga si calcola solo dal proprio gruppo.
$summary = foreach ($g in $byShare) {
    $folders = ($g.Group | Select-Object -ExpandProperty DirectoryFullName -Unique).Count
    $denyCnt = ($g.Group | Where-Object { $_.AccessControlType -eq 'Deny' }).Count
    [PSCustomObject]@{
        Share          = $g.Name
        Foglio         = Get-SheetName $g.Name
        CartelleEsportate = $folders
        RigheACE       = $g.Count
        ACE_Deny       = $denyCnt
    }
}

# -PassThru tiene aperto il pacchetto Excel in memoria invece di salvarlo
# su disco a ogni foglio. Con 60 share, salvare il file intero 60 volte e'
# lento e, riusando nomi-tabella auto-generati uguali fra fogli, produce
# il classico "trovato un problema con il contenuto" all'apertura.
# Un nome tabella esplicito e univoco per foglio elimina quel rischio.
$pkg = $summary | Export-Excel -Path $xlsxPath -WorksheetName 'Summary' `
    -AutoSize -FreezeTopRow -BoldTopRow -TableStyle 'Medium2' `
    -TableName 'TblSummary' -PassThru

# --- Un foglio per share --------------------------------------------------
# Reset dei nomi (con 'Summary' di nuovo pre-occupato): la fase Summary ha
# gia' chiamato Get-SheetName, quindi si rigenerano gli stessi nomi nello
# stesso ordine -> coerenza garantita.
$usedNames = @{ 'Summary' = $true }
$cols = 'ParentPath','FolderName','DirectoryFullName','Identity',
        'AccessControlType','Rights','IsInherited','InheritanceFlags'

$tableIdx = 0
foreach ($g in $byShare) {

    $sheet = Get-SheetName $g.Name
    $tableIdx++

    # $sheetRows e' una proiezione del SOLO gruppo corrente. Viene creata
    # da zero a ogni iterazione: nessun residuo della share precedente.
    $sheetRows = $g.Group | Select-Object -Property $cols

    $pkg = $sheetRows | Export-Excel -ExcelPackage $pkg -WorksheetName $sheet `
        -AutoSize -FreezeTopRow -BoldTopRow -TableStyle 'Light1' `
        -TableName ("Tbl$tableIdx") -PassThru

    Write-Host ("  foglio '{0}' <- {1} righe" -f $sheet, $g.Count)
}

# Un solo salvataggio su disco, alla fine.
Close-ExcelPackage $pkg

Write-Host ""
Write-Host "Stadio 2 completato."
Write-Host "  Excel: $xlsxPath"
Write-Host "  Share: $($byShare.Count)  -  righe ACE totali: $($rows.Count)"
