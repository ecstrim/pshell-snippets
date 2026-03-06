#Requires -Version 5.1
<#
.SYNOPSIS
    ADFS Assessment Script - raccoglie dati di configurazione e utilizzo da un ambiente ADFS.

.DESCRIPTION
    Esegue una raccolta dati read-only sull'ambiente ADFS locale.
    Produce un file JSON per ogni modulo nella cartella di output specificata.
    Non apporta nessuna modifica alla configurazione.

.PARAMETER Modules
    Lista dei moduli da eseguire. Default: tutti.
    Valori validi: Inventory, RelyingParties, ClaimsRules, Certificates, UsageAnalytics

.PARAMETER OutputPath
    Cartella di destinazione per i file JSON. Default: .\output\
    Viene creata automaticamente se non esiste.

.EXAMPLE
    # Esegue tutti i moduli
    .\Invoke-AdfsAssessment.ps1

.EXAMPLE
    # Esegue solo inventory e certificati
    .\Invoke-AdfsAssessment.ps1 -Modules Inventory, Certificates

.EXAMPLE
    # Specifica cartella di output
    .\Invoke-AdfsAssessment.ps1 -OutputPath "C:\temp\assessment"

.NOTES
    - Eseguire sul server ADFS primario.
    - Richiede il modulo ADFS e il ruolo ADFS Administrators (o equivalente).
    - Tutti i moduli sono read-only: nessuna modifica viene apportata.
#>

[CmdletBinding()]
param(
    [ValidateSet("Inventory", "RelyingParties", "ClaimsRules", "Certificates", "UsageAnalytics")]
    [string[]]$Modules = @("Inventory", "RelyingParties", "ClaimsRules", "Certificates", "UsageAnalytics"),

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
    # Blocco _metadata comune a ogni JSON prodotto
    param(
        [string]$ModuleName,
        [string]$AdfsVersion,
        [string[]]$Warnings = @(),
        [string[]]$Errors = @()
    )
    return [ordered]@{
        module          = $ModuleName
        timestamp       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        hostname        = $env:COMPUTERNAME
        adfs_version    = $AdfsVersion
        warnings        = $Warnings
        errors          = $Errors
    }
}

function Save-JsonOutput {
    param(
        [string]$FileName,
        [hashtable]$Data,
        [string]$OutputPath
    )
    $filePath = Join-Path $OutputPath $FileName
    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $filePath -Encoding UTF8
    Write-AssessmentLog "Output salvato: $filePath"
}

function Get-AdfsVersion {
    # Restituisce la versione ADFS come stringa, o "unknown" in caso di errore
    try {
        $svc = Get-WmiObject -Class Win32_Product -ErrorAction Stop |
            Where-Object { $_.Name -like "*Federation Services*" } |
            Select-Object -First 1
        if ($svc) { return $svc.Version }

        # Fallback: leggi la versione dal file binario del servizio
        $exePath = (Get-WmiObject Win32_Service -Filter "Name='adfssrv'" -ErrorAction Stop).PathName
        if ($exePath) {
            $exePath = $exePath.Trim('"').Split(' ')[0]
            $version = (Get-Item $exePath -ErrorAction Stop).VersionInfo.ProductVersion
            return $version
        }
    }
    catch {
        # Ignora - restituisce unknown
    }
    return "unknown"
}

function Test-IsAdfsModule {
    # Verifica che il modulo ADFS sia disponibile
    $module = Get-Module -ListAvailable | Where-Object { $_.Name -eq "ADFS" }
    return ($null -ne $module)
}

function Test-IsAdfsServiceRunning {
    try {
        $svc = Get-Service -Name "adfssrv" -ErrorAction Stop
        return ($svc.Status -eq "Running")
    }
    catch {
        return $false
    }
}

function Test-AdfsReadPermission {
    try {
        $null = Get-AdfsProperties -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-AdfsPrimaryRole {
    # Restituisce il ruolo del server corrente (PrimaryComputer / SecondaryComputer)
    try {
        $sync = Get-AdfsSyncProperties -ErrorAction Stop
        return $sync.Role
    }
    catch {
        return "unknown"
    }
}

# ---------------------------------------------------------------------------
# Prerequisiti
# ---------------------------------------------------------------------------

function Test-Prerequisites {
    Write-AssessmentLog "Verifica prerequisiti..."
    $ok = $true

    if (-not (Test-IsAdfsModule)) {
        Write-AssessmentLog "Modulo ADFS non trovato. Eseguire questo script su un server ADFS." "ERROR"
        $ok = $false
    }
    else {
        Write-AssessmentLog "Modulo ADFS: trovato"
        # Importa il modulo esplicitamente
        Import-Module ADFS -ErrorAction SilentlyContinue
    }

    if (-not (Test-IsAdfsServiceRunning)) {
        Write-AssessmentLog "Servizio ADFS (adfssrv) non in esecuzione." "ERROR"
        $ok = $false
    }
    else {
        Write-AssessmentLog "Servizio ADFS: in esecuzione"
    }

    if (-not (Test-AdfsReadPermission)) {
        Write-AssessmentLog "Permessi insufficienti per leggere la configurazione ADFS. Verificare di avere il ruolo ADFS Administrators." "ERROR"
        $ok = $false
    }
    else {
        Write-AssessmentLog "Permessi ADFS: ok"
    }

    $role = Get-AdfsPrimaryRole
    if ($role -eq "SecondaryComputer") {
        Write-AssessmentLog "Questo server e' un nodo SECONDARIO. I dati raccolti potrebbero essere incompleti. Si consiglia di eseguire lo script sul server primario." "WARN"
    }
    elseif ($role -eq "PrimaryComputer") {
        Write-AssessmentLog "Ruolo server: primario"
    }
    else {
        Write-AssessmentLog "Impossibile determinare il ruolo del server (WID non in uso o errore)." "WARN"
    }

    return $ok
}

# ---------------------------------------------------------------------------
# Modulo: Inventory
# ---------------------------------------------------------------------------

function Invoke-ModuleInventory {
    param([string]$AdfsVersion, [string]$OutputPath)
    Write-AssessmentLog "--- Modulo: Inventory ---"

    $warnings = [System.Collections.Generic.List[string]]::new()
    $errors   = [System.Collections.Generic.List[string]]::new()
    $data     = [ordered]@{}

    # Versione OS
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        $data.os = [ordered]@{
            caption        = $os.Caption
            version        = $os.Version
            build_number   = $os.BuildNumber
        }
    }
    catch {
        $errors.Add("os: $($_.Exception.Message)")
        $data.os = $null
    }

    # Proprieta' ADFS base
    try {
        $props = Get-AdfsProperties -ErrorAction Stop
        $data.adfs_properties = [ordered]@{
            host_name                       = $props.HostName
            federation_passive_address      = $props.FederationPassiveAddress
            https_port                      = $props.HttpsPort
            http_port                       = $props.HttpPort
            auto_certificate_rollover       = $props.AutoCertificateRollover
            certificate_duration_days       = $props.CertificateDuration
            audit_level                     = $props.AuditLevel
        }
    }
    catch {
        $errors.Add("adfs_properties: $($_.Exception.Message)")
        $data.adfs_properties = $null
    }

    # Topologia farm
    try {
        $farm = Get-AdfsFarmInformation -ErrorAction Stop
        $data.farm = [ordered]@{
            farm_nodes           = @($farm.FarmNodes) | ForEach-Object {
                [ordered]@{
                    fqdn            = $_.FQDN
                    node_type       = $_.NodeType
                    behavior_level  = $_.BehaviorLevel
                }
            }
            behavior_level       = $farm.CurrentFarmBehavior
        }
    }
    catch {
        $errors.Add("farm_information: $($_.Exception.Message)")
        $data.farm = $null
    }

    # Sync properties
    try {
        $sync = Get-AdfsSyncProperties -ErrorAction Stop
        $data.sync = [ordered]@{
            role                 = $sync.Role
        }
    }
    catch {
        $errors.Add("sync_properties: $($_.Exception.Message)")
        $data.sync = $null
    }

    # Tipo database
    try {
        $props = Get-AdfsProperties -ErrorAction Stop
        $connString = $props.ArtifactDbConnection
        $dbType = if ($connString -like "*microsoft##wid*") { "WID" } else { "SQL" }
        $data.database = [ordered]@{
            type              = $dbType
            artifact_db_connection = $connString
        }
    }
    catch {
        $errors.Add("database: $($_.Exception.Message)")
        $data.database = $null
    }

    # Account di servizio
    try {
        $svc = Get-WmiObject Win32_Service -Filter "Name='adfssrv'" -ErrorAction Stop
        $accountName = $svc.StartName
        $accountType = if ($accountName -match '\$$') { "gMSA" }
                       elseif ($accountName -match "^NT ") { "BuiltIn" }
                       else { "StandardUser" }
        $data.service_account = [ordered]@{
            name = $accountName
            type = $accountType
        }
        if ($accountType -eq "StandardUser") {
            $warnings.Add("Account di servizio e' un account utente standard. Preferibile usare un gMSA.")
        }
    }
    catch {
        $errors.Add("service_account: $($_.Exception.Message)")
        $data.service_account = $null
    }

    # Endpoint abilitati
    try {
        $endpoints = Get-AdfsEndpoint -ErrorAction Stop
        $data.endpoints = [ordered]@{
            enabled_count  = ($endpoints | Where-Object { $_.Enabled }).Count
            disabled_count = ($endpoints | Where-Object { -not $_.Enabled }).Count
            enabled        = $endpoints | Where-Object { $_.Enabled } |
                             Select-Object -ExpandProperty FullUrl
        }
    }
    catch {
        $errors.Add("endpoints: $($_.Exception.Message)")
        $data.endpoints = $null
    }

    # Claims Provider Trusts (oltre AD - indica multi-forest o partner B2B)
    try {
        $cpt = Get-AdfsClaimsProviderTrust -ErrorAction Stop |
               Where-Object { $_.Name -ne "Active Directory" }
        $data.external_claims_providers = $cpt | ForEach-Object {
            [ordered]@{
                name                        = $_.Name
                enabled                     = $_.Enabled
                organizational_account_suffix = $_.OrganizationalAccountSuffix
                metadata_url                = $_.MetadataUrl
            }
        }
    }
    catch {
        $errors.Add("claims_provider_trusts: $($_.Exception.Message)")
        $data.external_claims_providers = $null
    }

    $output = [ordered]@{
        _metadata = New-Metadata -ModuleName "Inventory" -AdfsVersion $AdfsVersion -Warnings $warnings -Errors $errors
        data      = $data
    }

    Save-JsonOutput -FileName "01-inventory.json" -Data $output -OutputPath $OutputPath
}

# ---------------------------------------------------------------------------
# Modulo: RelyingParties
# ---------------------------------------------------------------------------

function Invoke-ModuleRelyingParties {
    param([string]$AdfsVersion, [string]$OutputPath)
    Write-AssessmentLog "--- Modulo: RelyingParties ---"

    $warnings = [System.Collections.Generic.List[string]]::new()
    $errors   = [System.Collections.Generic.List[string]]::new()
    $data     = [ordered]@{}

    try {
        $allRp = @(Get-AdfsRelyingPartyTrust -ErrorAction Stop)

        $data.summary = [ordered]@{
            total    = $allRp.Count
            enabled  = @($allRp | Where-Object { $_.Enabled }).Count
            disabled = @($allRp | Where-Object { -not $_.Enabled }).Count
        }

        $data.relying_parties = $allRp | ForEach-Object {
            $rp = $_

            # Rileva il protocollo in uso
            $protocols = [System.Collections.Generic.List[string]]::new()
            if ($rp.WSFedEndpoint) { $protocols.Add("WS-Federation") }
            if (@($rp.SamlEndpoints).Count -gt 0) { $protocols.Add("SAML") }
            # OAuth/OIDC: le RP non hanno un campo diretto, ma sono identificabili dall'identifier
            if ($rp.Identifier -like "*oauth*" -or $rp.Identifier -like "*oidc*") { $protocols.Add("OAuth/OIDC") }
            if ($protocols.Count -eq 0) { $protocols.Add("unknown") }

            # Segnala RP Microsoft 365 / Entra ID
            $isMicrosoft365 = @($rp.Identifier | Where-Object {
                $_ -like "*microsoft.com*" -or $_ -like "*microsoftonline*"
            }).Count -gt 0

            [ordered]@{
                name                    = $rp.Name
                enabled                 = $rp.Enabled
                identifier              = $rp.Identifier
                protocols               = $protocols -join ", "
                is_microsoft365         = $isMicrosoft365
                access_control_policy   = $rp.AccessControlPolicyName
                has_issuance_rules      = (-not [string]::IsNullOrWhiteSpace($rp.IssuanceTransformRules))
                has_authorization_rules = (-not [string]::IsNullOrWhiteSpace($rp.IssuanceAuthorizationRules))
                last_update_time        = if ($rp.LastUpdateTime) { $rp.LastUpdateTime.ToString("yyyy-MM-ddTHH:mm:ss") } else { $null }
                notes                   = $rp.Notes
            }
        }

        # Segnala se M365 e' presente - impatto critico sulla dismissione
        $m365Rp = $data.relying_parties | Where-Object { $_.is_microsoft365 }
        if ($m365Rp) {
            $warnings.Add("Microsoft 365 / Entra ID rilevato come Relying Party. La dismissione di ADFS richiede la migrazione degli utenti federati (PHS o PTA).")
        }
    }
    catch {
        $errors.Add("relying_parties: $($_.Exception.Message)")
        $data.relying_parties = $null
    }

    # OAuth clients
    try {
        $clients = Get-AdfsClient -ErrorAction Stop
        $data.oauth_clients = $clients | ForEach-Object {
            [ordered]@{
                name         = $_.Name
                enabled      = $_.Enabled
                client_id    = $_.ClientId
                redirect_uri = $_.RedirectUri
            }
        }
    }
    catch {
        # Get-AdfsClient non disponibile su ADFS 3.0 - non e' un errore critico
        $warnings.Add("Get-AdfsClient non disponibile (probabilmente ADFS 3.0). OAuth clients non raccolti.")
        $data.oauth_clients = $null
    }

    $output = [ordered]@{
        _metadata = New-Metadata -ModuleName "RelyingParties" -AdfsVersion $AdfsVersion -Warnings $warnings -Errors $errors
        data      = $data
    }

    Save-JsonOutput -FileName "02-relying-parties.json" -Data $output -OutputPath $OutputPath
}

# ---------------------------------------------------------------------------
# Modulo: ClaimsRules
# ---------------------------------------------------------------------------

function Invoke-ModuleClaimsRules {
    param([string]$AdfsVersion, [string]$OutputPath)
    Write-AssessmentLog "--- Modulo: ClaimsRules ---"

    $warnings = [System.Collections.Generic.List[string]]::new()
    $errors   = [System.Collections.Generic.List[string]]::new()
    $data     = [ordered]@{}

    # Attribute stores
    try {
        $stores = @(Get-AdfsAttributeStore -ErrorAction Stop)
        $data.attribute_stores = $stores | ForEach-Object {
            [ordered]@{
                name            = $_.Name
                store_type      = $_.StoreClassification
                configuration   = $_.Configuration
            }
        }

        $externalStores = @($stores | Where-Object { $_.Name -ne "Active Directory" })
        if ($externalStores.Count -gt 0) {
            $warnings.Add("Attribute stores esterni rilevati: $($externalStores.Name -join ', '). Dipendenze critiche per la migrazione.")
        }

        $customStores = @($stores | Where-Object { $_.StoreClassification -notin @("ActiveDirectory", "LDAP", "SQL") })
        if ($customStores.Count -gt 0) {
            $warnings.Add("Attribute store custom (.NET plugin) rilevati: $($customStores.Name -join ', '). Rischio critico per la migrazione.")
        }
    }
    catch {
        $errors.Add("attribute_stores: $($_.Exception.Message)")
        $data.attribute_stores = $null
    }

    # Claim rules per RP
    try {
        $allRp = @(Get-AdfsRelyingPartyTrust -ErrorAction Stop)
        $data.relying_party_rules = $allRp | ForEach-Object {
            $rp = $_
            $hasTransformRules = -not [string]::IsNullOrWhiteSpace($rp.IssuanceTransformRules)
            $hasAuthzRules     = -not [string]::IsNullOrWhiteSpace($rp.IssuanceAuthorizationRules)

            # Rileva dipendenze su store esterni nelle claim rules
            $storeRefs = [System.Collections.Generic.List[string]]::new()
            if ($hasTransformRules) {
                $matches = [regex]::Matches($rp.IssuanceTransformRules, 'store\s*=\s*"([^"]+)"')
                foreach ($m in $matches) { $storeRefs.Add($m.Groups[1].Value) }
            }

            # Stima complessita' della regola
            $complexity = "none"
            if ($hasTransformRules) {
                $ruleText = $rp.IssuanceTransformRules
                $complexity = if ($storeRefs.Count -gt 0) { "high" }
                              elseif ($ruleText -match "regexp|RegexReplace|split|join") { "high" }
                              elseif ($ruleText -match "&&|\|\|") { "medium" }
                              elseif (($ruleText -split "=>").Count -gt 3) { "medium" }
                              else { "low" }
            }

            [ordered]@{
                name                        = $rp.Name
                enabled                     = $rp.Enabled
                has_issuance_transform_rules = $hasTransformRules
                has_authorization_rules     = $hasAuthzRules
                external_store_references   = if ($storeRefs.Count -gt 0) { $storeRefs -join ", " } else { $null }
                estimated_complexity        = $complexity
                issuance_transform_rules    = if ($hasTransformRules) { $rp.IssuanceTransformRules } else { $null }
                issuance_authorization_rules = if ($hasAuthzRules) { $rp.IssuanceAuthorizationRules } else { $null }
            }
        }

        # Segnala RP con store esterni
        $rpWithStores = $data.relying_party_rules | Where-Object { $_.external_store_references }
        if ($rpWithStores) {
            $warnings.Add("RP con dipendenze su attribute stores esterni: $($rpWithStores.name -join ', ').")
        }
    }
    catch {
        $errors.Add("relying_party_rules: $($_.Exception.Message)")
        $data.relying_party_rules = $null
    }

    # Claim type non standard
    try {
        $customClaims = Get-AdfsClaimDescription -ErrorAction Stop | Where-Object {
            $_.ClaimType -notlike "*microsoft.com*" -and
            $_.ClaimType -notlike "*xmlsoap.org*"   -and
            $_.ClaimType -notlike "*oasis*"
        }
        $data.custom_claim_types = $customClaims | ForEach-Object {
            [ordered]@{
                name        = $_.Name
                claim_type  = $_.ClaimType
                is_offered  = $_.IsOffered
                is_accepted = $_.IsAccepted
            }
        }
        if ($customClaims) {
            $warnings.Add("Claim type non standard rilevati: $($customClaims.Count). Verificare se sono necessari nella soluzione target.")
        }
    }
    catch {
        $errors.Add("claim_descriptions: $($_.Exception.Message)")
        $data.custom_claim_types = $null
    }

    $output = [ordered]@{
        _metadata = New-Metadata -ModuleName "ClaimsRules" -AdfsVersion $AdfsVersion -Warnings $warnings -Errors $errors
        data      = $data
    }

    Save-JsonOutput -FileName "03-claims-rules.json" -Data $output -OutputPath $OutputPath
}

# ---------------------------------------------------------------------------
# Modulo: Certificates
# ---------------------------------------------------------------------------

function Invoke-ModuleCertificates {
    param([string]$AdfsVersion, [string]$OutputPath)
    Write-AssessmentLog "--- Modulo: Certificates ---"

    $warnings = [System.Collections.Generic.List[string]]::new()
    $errors   = [System.Collections.Generic.List[string]]::new()
    $data     = [ordered]@{}

    $now = Get-Date

    # Token-signing e token-decrypting
    foreach ($certType in @("Token-Signing", "Token-Decrypting")) {
        $key = $certType.ToLower().Replace("-", "_")
        try {
            $certs = Get-AdfsCertificate -CertificateType $certType -ErrorAction Stop
            $data[$key] = $certs | ForEach-Object {
                $daysLeft = ($_.Certificate.NotAfter - $now).Days
                $status   = if ($daysLeft -lt 0) { "expired" }
                            elseif ($daysLeft -le 30) { "critical" }
                            elseif ($daysLeft -le 90) { "warning" }
                            else { "ok" }

                if ($status -in @("expired", "critical")) {
                    $warnings.Add("$certType (thumbprint: $($_.Thumbprint)): scadenza $($_.Certificate.NotAfter.ToString('yyyy-MM-dd')) - $status")
                }

                [ordered]@{
                    is_primary   = $_.IsPrimary
                    thumbprint   = $_.Thumbprint
                    subject      = $_.Certificate.Subject
                    issuer       = $_.Certificate.Issuer
                    not_before   = $_.Certificate.NotBefore.ToString("yyyy-MM-ddTHH:mm:ss")
                    not_after    = $_.Certificate.NotAfter.ToString("yyyy-MM-ddTHH:mm:ss")
                    days_left    = $daysLeft
                    status       = $status
                    self_signed  = ($_.Certificate.Subject -eq $_.Certificate.Issuer)
                }
            }
        }
        catch {
            $errors.Add("${certType}: $($_.Exception.Message)")
            $data[$key] = $null
        }
    }

    # Auto-rollover
    try {
        $props = Get-AdfsProperties -ErrorAction Stop
        $data.auto_rollover = [ordered]@{
            enabled           = $props.AutoCertificateRollover
            certificate_duration_days = $props.CertificateDuration
        }
        if (-not $props.AutoCertificateRollover) {
            $warnings.Add("AutoCertificateRollover e' disabilitato. Il rinnovo dei certificati token-signing e' manuale.")
        }
    }
    catch {
        $errors.Add("auto_rollover: $($_.Exception.Message)")
        $data.auto_rollover = $null
    }

    # Certificato SSL dal personal store
    try {
        $allCerts = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction Stop
        $data.ssl_certificates = $allCerts | ForEach-Object {
            $daysLeft = ($_.NotAfter - $now).Days
            $status   = if ($daysLeft -lt 0) { "expired" }
                        elseif ($daysLeft -le 30) { "critical" }
                        elseif ($daysLeft -le 90) { "warning" }
                        else { "ok" }

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

    # Certificati di cifratura nelle RP (SAML encryption)
    try {
        $rpCerts = Get-AdfsRelyingPartyTrust -ErrorAction Stop |
                   Where-Object { $_.EncryptionCertificate -ne $null }

        $data.rp_encryption_certificates = $rpCerts | ForEach-Object {
            $daysLeft = ($_.EncryptionCertificate.NotAfter - $now).Days
            $status   = if ($daysLeft -lt 0) { "expired" }
                        elseif ($daysLeft -le 30) { "critical" }
                        elseif ($daysLeft -le 90) { "warning" }
                        else { "ok" }

            if ($status -in @("expired", "critical")) {
                $warnings.Add("RP '$($_.Name)': certificato di cifratura in scadenza $($_.EncryptionCertificate.NotAfter.ToString('yyyy-MM-dd')) - $status")
            }

            [ordered]@{
                rp_name    = $_.Name
                subject    = $_.EncryptionCertificate.Subject
                not_after  = $_.EncryptionCertificate.NotAfter.ToString("yyyy-MM-ddTHH:mm:ss")
                days_left  = $daysLeft
                status     = $status
            }
        }
    }
    catch {
        $errors.Add("rp_encryption_certificates: $($_.Exception.Message)")
        $data.rp_encryption_certificates = $null
    }

    $output = [ordered]@{
        _metadata = New-Metadata -ModuleName "Certificates" -AdfsVersion $AdfsVersion -Warnings $warnings -Errors $errors
        data      = $data
    }

    Save-JsonOutput -FileName "04-certificates.json" -Data $output -OutputPath $OutputPath
}

# ---------------------------------------------------------------------------
# Modulo: UsageAnalytics
# ---------------------------------------------------------------------------

function Invoke-ModuleUsageAnalytics {
    param([string]$AdfsVersion, [string]$OutputPath)
    Write-AssessmentLog "--- Modulo: UsageAnalytics ---"

    $warnings = [System.Collections.Generic.List[string]]::new()
    $errors   = [System.Collections.Generic.List[string]]::new()
    $data     = [ordered]@{}

    # Stato del logging
    try {
        $props = Get-AdfsProperties -ErrorAction Stop
        $auditLevel = $props.AuditLevel
        $logLevel   = $props.LogLevel

        $data.logging_status = [ordered]@{
            audit_level = $auditLevel
            log_level   = $logLevel
            verbose_available = ($auditLevel -contains "Verbose" -or $logLevel -contains "Verbose")
        }

        if (-not ($auditLevel -contains "Verbose" -or $logLevel -contains "Verbose")) {
            $warnings.Add("Logging verbose non attivo (AuditLevel: $($auditLevel -join ',')). I dati per-RP non sono disponibili. Per abilitarlo (ADFS 4.0+): Set-AdfsProperties -AuditLevel Verbose. Per ADFS 3.0: Set-AdfsProperties -LogLevel Verbose.")
        }
    }
    catch {
        $errors.Add("logging_status: $($_.Exception.Message)")
        $data.logging_status = $null
    }

    # Dimensione e retention log
    try {
        $logInfo = Get-WinEvent -ListLog "AD FS/Admin" -ErrorAction Stop
        $oldestEvent = Get-WinEvent -LogName "AD FS/Admin" -MaxEvents 1 -Oldest -ErrorAction Stop
        $data.log_info = [ordered]@{
            file_size_mb       = [math]::Round($logInfo.FileSize / 1MB, 2)
            max_size_mb        = [math]::Round($logInfo.MaximumSizeInBytes / 1MB, 2)
            record_count       = $logInfo.RecordCount
            oldest_event_date  = $oldestEvent.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
            days_covered       = ($oldestEvent.TimeCreated - (Get-Date)).Days * -1
        }
    }
    catch {
        $errors.Add("log_info: $($_.Exception.Message)")
        $data.log_info = $null
    }

    # Volume autenticazioni per giorno (ultime 2 settimane)
    # Event ID 1200 = token emesso con successo
    try {
        $start = (Get-Date).AddDays(-14)
        $successEvents = @(Get-WinEvent -LogName "AD FS/Admin" -ErrorAction Stop |
            Where-Object { $_.Id -eq 1200 -and $_.TimeCreated -gt $start })

        $data.daily_auth_volume = @($successEvents |
            Group-Object { $_.TimeCreated.Date.ToString("yyyy-MM-dd") } |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{ date = $_.Name; count = $_.Count }
            })

        $data.auth_summary = [ordered]@{
            total_last_14_days  = $successEvents.Count
            avg_per_day         = if ($data.daily_auth_volume.Count -gt 0) {
                                      [math]::Round($successEvents.Count / $data.daily_auth_volume.Count, 0)
                                  } else { 0 }
        }
    }
    catch {
        $errors.Add("daily_auth_volume: $($_.Exception.Message)")
        $data.daily_auth_volume = $null
        $data.auth_summary      = $null
    }

    # Autenticazioni fallite (ultime 2 settimane)
    # Event ID 364 = autenticazione fallita
    try {
        $start = (Get-Date).AddDays(-14)
        $failedEvents = @(Get-WinEvent -LogName "AD FS/Admin" -ErrorAction Stop |
            Where-Object { $_.Id -eq 364 -and $_.TimeCreated -gt $start })

        $data.failed_auth_summary = [ordered]@{
            total_last_14_days = $failedEvents.Count
        }
    }
    catch {
        $errors.Add("failed_auth: $($_.Exception.Message)")
        $data.failed_auth_summary = $null
    }

    # Utilizzo per RP (solo se logging verbose attivo)
    # NOTA: il pattern regex per estrarre il nome RP e' valido su ADFS 4.0+.
    # Su ADFS 3.0 il formato del messaggio puo' differire - verificare manualmente.
    try {
        $loggingStatus = $data.logging_status
        if ($loggingStatus -and $loggingStatus.verbose_available) {
            $start = (Get-Date).AddDays(-14)
            $rpUsage = Get-WinEvent -LogName "AD FS/Admin" -ErrorAction Stop |
                Where-Object { $_.Id -eq 1200 -and $_.TimeCreated -gt $start } |
                ForEach-Object {
                    if ($_.Message -match "Relying party:\s*(.+)") { $Matches[1].Trim() }
                } |
                Where-Object { $_ } |
                Group-Object |
                Sort-Object Count -Descending |
                ForEach-Object {
                    [ordered]@{ relying_party = $_.Name; auth_count = $_.Count }
                }

            $data.rp_usage = $rpUsage

            # RP abilitate ma assenti dai log = potenziali zombie
            $enabledRp = (Get-AdfsRelyingPartyTrust -ErrorAction Stop |
                Where-Object { $_.Enabled } |
                Select-Object -ExpandProperty Name)
            $activeRp  = $rpUsage | Select-Object -ExpandProperty relying_party
            $zombieRp  = $enabledRp | Where-Object { $_ -notin $activeRp }

            $data.potential_zombie_rp = $zombieRp
            if ($zombieRp) {
                $warnings.Add("$($zombieRp.Count) RP abilitate non presenti nei log degli ultimi 14 giorni. Potrebbero essere inattive - verificare con il cliente prima di rimuoverle.")
            }
        }
        else {
            $warnings.Add("Dati per-RP non disponibili: logging verbose non attivo. Vedere warning logging_status.")
            $data.rp_usage            = $null
            $data.potential_zombie_rp = $null
        }
    }
    catch {
        $errors.Add("rp_usage: $($_.Exception.Message)")
        $data.rp_usage            = $null
        $data.potential_zombie_rp = $null
    }

    $output = [ordered]@{
        _metadata = New-Metadata -ModuleName "UsageAnalytics" -AdfsVersion $AdfsVersion -Warnings $warnings -Errors $errors
        data      = $data
    }

    Save-JsonOutput -FileName "05-usage-analytics.json" -Data $output -OutputPath $OutputPath
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

Write-AssessmentLog "ADFS Assessment - avvio"
Write-AssessmentLog "Moduli selezionati: $($Modules -join ', ')"
Write-AssessmentLog "Output path: $OutputPath"

# Prerequisiti
if (-not (Test-Prerequisites)) {
    Write-AssessmentLog "Prerequisiti non soddisfatti. Assessment interrotto." "ERROR"
    exit 1
}

# Crea cartella di output
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-AssessmentLog "Cartella di output creata: $OutputPath"
}

# Rileva versione ADFS una volta sola
$adfsVersion = Get-AdfsVersion
Write-AssessmentLog "Versione ADFS rilevata: $adfsVersion"

# Esegui i moduli selezionati
foreach ($module in $Modules) {
    try {
        switch ($module) {
            "Inventory"       { Invoke-ModuleInventory       -AdfsVersion $adfsVersion -OutputPath $OutputPath }
            "RelyingParties"  { Invoke-ModuleRelyingParties  -AdfsVersion $adfsVersion -OutputPath $OutputPath }
            "ClaimsRules"     { Invoke-ModuleClaimsRules     -AdfsVersion $adfsVersion -OutputPath $OutputPath }
            "Certificates"    { Invoke-ModuleCertificates    -AdfsVersion $adfsVersion -OutputPath $OutputPath }
            "UsageAnalytics"  { Invoke-ModuleUsageAnalytics  -AdfsVersion $adfsVersion -OutputPath $OutputPath }
        }
    }
    catch {
        Write-AssessmentLog "Errore non gestito nel modulo $module`: $($_.Exception.Message)" "ERROR"
    }
}

Write-AssessmentLog "Assessment completato. File JSON disponibili in: $OutputPath"
