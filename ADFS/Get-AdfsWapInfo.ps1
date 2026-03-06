#Requires -Version 5.1
<#
.SYNOPSIS
    WAP Assessment Script - raccoglie dati di configurazione dal Web Application Proxy.

.DESCRIPTION
    Esegue una raccolta dati read-only sul server WAP locale.
    Produce un file wap-info.json nella cartella di output specificata.
    Non apporta nessuna modifica alla configurazione.

    IMPORTANTE: questo script va copiato ed eseguito direttamente su ogni
    server WAP/ADFS Proxy. Non puo' essere eseguito in remoto dal server ADFS.

.PARAMETER OutputPath
    Cartella di destinazione per il file JSON. Default: .\output\
    Viene creata automaticamente se non esiste.

.EXAMPLE
    .\Get-AdfsWapInfo.ps1

.EXAMPLE
    .\Get-AdfsWapInfo.ps1 -OutputPath "C:\temp\assessment"

.NOTES
    - Eseguire direttamente su ogni server WAP.
    - Richiede il modulo WebApplicationProxy.
    - Read-only: nessuna modifica viene apportata.
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ".\output"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# Funzioni di supporto
# ---------------------------------------------------------------------------

function Write-AssessmentLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "INFO"  { "[INFO ]" }
        "WARN"  { "[WARN ]" }
        "ERROR" { "[ERROR]" }
    }
    Write-Host "$timestamp $prefix $Message"
}

function New-Metadata {
    param(
        [string[]]$Warnings = @(),
        [string[]]$Errors = @()
    )
    return [ordered]@{
        module      = "WapInfo"
        timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        hostname    = $env:COMPUTERNAME
        warnings    = $Warnings
        errors      = $Errors
    }
}

# ---------------------------------------------------------------------------
# Prerequisiti
# ---------------------------------------------------------------------------

function Test-Prerequisites {
    Write-AssessmentLog "Verifica prerequisiti..."
    $ok = $true

    $module = Get-Module -ListAvailable | Where-Object { $_.Name -eq "WebApplicationProxy" }
    if (-not $module) {
        Write-AssessmentLog "Modulo WebApplicationProxy non trovato. Verificare che il ruolo WAP sia installato su questo server." "ERROR"
        $ok = $false
    }
    else {
        Write-AssessmentLog "Modulo WebApplicationProxy: trovato"
        Import-Module WebApplicationProxy -ErrorAction SilentlyContinue
    }

    # Verifica permessi con un comando di test
    try {
        $null = Get-WebApplicationProxyConfiguration -ErrorAction Stop
        Write-AssessmentLog "Permessi WAP: ok"
    }
    catch {
        Write-AssessmentLog "Impossibile leggere la configurazione WAP. Verificare i permessi." "ERROR"
        $ok = $false
    }

    return $ok
}

# ---------------------------------------------------------------------------
# Raccolta dati WAP
# ---------------------------------------------------------------------------

Write-AssessmentLog "WAP Assessment - avvio"
Write-AssessmentLog "Output path: $OutputPath"

if (-not (Test-Prerequisites)) {
    Write-AssessmentLog "Prerequisiti non soddisfatti. Assessment interrotto." "ERROR"
    exit 1
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-AssessmentLog "Cartella di output creata: $OutputPath"
}

$warnings = [System.Collections.Generic.List[string]]::new()
$errors   = [System.Collections.Generic.List[string]]::new()
$data     = [ordered]@{}

# Configurazione WAP (URL ADFS, certificato trust)
try {
    $config = Get-WebApplicationProxyConfiguration -ErrorAction Stop
    $data.configuration = [ordered]@{
        adfs_url                                    = $config.ADFSUrl
        adfs_token_signing_certificate_public_key   = $config.ADFSTokenSigningCertificatePublicKey
        connected_servers_name                      = $config.ConnectedServersName
    }
}
catch {
    $errors.Add("configuration: $($_.Exception.Message)")
    $data.configuration = $null
}

# Versione OS
try {
    $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
    $data.os = [ordered]@{
        caption      = $os.Caption
        version      = $os.Version
        build_number = $os.BuildNumber
    }
}
catch {
    $errors.Add("os: $($_.Exception.Message)")
    $data.os = $null
}

# Applicazioni pubblicate
try {
    $apps = @(Get-WebApplicationProxyApplication -ErrorAction Stop)
    $data.published_applications = $apps | ForEach-Object {
        [ordered]@{
            name                          = $_.Name
            external_url                  = $_.ExternalUrl
            backend_server_url            = $_.BackendServerUrl
            external_certificate_thumbprint = $_.ExternalCertificateThumbprint
            pre_authentication_mode       = $_.ExternalPreauthentication
            relying_party_name            = $_.ADFSRelyingPartyName
            enabled                       = $_.Enabled
        }
    }
    $data.published_applications_count = $apps.Count
}
catch {
    $errors.Add("published_applications: $($_.Exception.Message)")
    $data.published_applications = $null
}

# Health check
try {
    $health = @(Get-WebApplicationProxyHealth -ErrorAction Stop)
    $data.health = $health | ForEach-Object {
        [ordered]@{
            component   = $_.Component
            status      = $_.HealthState
            heuristics  = $_.Heuristics
        }
    }

    $unhealthy = @($health | Where-Object { $_.HealthState -ne "OK" })
    if ($unhealthy.Count -gt 0) {
        $warnings.Add("Componenti WAP non in stato OK: $($unhealthy.Component -join ', ').")
    }
}
catch {
    $errors.Add("health: $($_.Exception.Message)")
    $data.health = $null
}

# Certificati SSL nel personal store
$now = Get-Date
try {
    $certs = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction Stop
    $data.ssl_certificates = $certs | ForEach-Object {
        $daysLeft = ($_.NotAfter - $now).Days
        $status   = if ($daysLeft -lt 0) { "expired" }
                    elseif ($daysLeft -le 30) { "critical" }
                    elseif ($daysLeft -le 90) { "warning" }
                    else { "ok" }

        if ($status -in @("expired", "critical")) {
            $warnings.Add("Certificato '$($_.Subject)': scadenza $($_.NotAfter.ToString('yyyy-MM-dd')) - $status")
        }

        [ordered]@{
            subject     = $_.Subject
            issuer      = $_.Issuer
            thumbprint  = $_.Thumbprint
            not_after   = $_.NotAfter.ToString("yyyy-MM-ddTHH:mm:ss")
            days_left   = $daysLeft
            status      = $status
            self_signed = ($_.Subject -eq $_.Issuer)
        }
    } | Sort-Object { $_.days_left }
}
catch {
    $errors.Add("ssl_certificates: $($_.Exception.Message)")
    $data.ssl_certificates = $null
}

$output = [ordered]@{
    _metadata = New-Metadata -Warnings $warnings -Errors $errors
    data      = $data
}

# Salva output
$filePath = Join-Path $OutputPath "wap-info.json"
$output | ConvertTo-Json -Depth 10 | Out-File -FilePath $filePath -Encoding UTF8
Write-AssessmentLog "Output salvato: $filePath"
Write-AssessmentLog "WAP Assessment completato."
