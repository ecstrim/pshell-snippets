#requires -Version 5.1
<#
    Invoke-DomainAssessment.ps1
    Domain-wide migration readiness + dependency assessment for an AD estate.

    This is the layer ABOVE any per-box inventory: it works on the domain as a whole.
    It discovers the whole AD topology, finds which server holds each high-risk role
    (CA, NPS, DHCP, DNS, RDS Licensing), deep-dives those roles, checks AD health, and
    maps what depends on the box(es) you plan to retire.

    WHERE TO RUN: on a domain-joined box with the RSAT AD tools (a DC is fine), as a
    domain admin (Enterprise Admin needed to read all CA detail). Needs WinRM to the
    other servers - it uses Invoke-Command for tools that only run locally (certutil,
    netsh, dfsrmig).

    MOSTLY read-only. The ONE exception: the NPS section runs 'netsh nps export', which
    WRITES an XML file to the NPS host. That file contains RADIUS shared secrets in
    cleartext - treat it as sensitive, move it somewhere safe, don't leave it lying about.
    Disable it with -SkipNpsExport if you'd rather keep everything read-only.

    A llama could run this. Please don't let the llama run this.
#>

param(
    [string]  $OutFile          = ".\DomainAssessment_$(Get-Date -Format yyyyMMdd_HHmmss).txt",
    [string]  $NpsExportDir     = 'C:\Temp',   # where the NPS export lands on the NPS host
    [switch]  $SkipNpsExport,                  # keep it fully read-only
    [switch]  $QuickTopologyOnly,              # skip health checks + server sweep for a fast re-run
    [int]     $ActiveWithinDays = 0,           # sweep only servers seen in the last N days (0 = all)
    [int]     $ServerSweepTimeoutSec = 3       # per-server reachability timeout in the sweep
)

Start-Transcript -Path $OutFile -Force | Out-Null

# --- helpers ----------------------------------------------------------------
$Flags = [System.Collections.Generic.List[string]]::new()
function Write-Section($t) {
    Write-Host "`n=================================================================" -ForegroundColor Cyan
    Write-Host " $t" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
}
function Flag($msg) {
    Write-Host "  [FLAG] $msg" -ForegroundColor Red
    $Flags.Add($msg)
}

# Pull the installed feature names off a remote host. Returns $null if unreachable.
function Get-RemoteFeatures($computer) {
    try {
        Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {
            (Get-WindowsFeature | Where-Object Installed).Name
        }
    } catch { $null }
}

try { Import-Module ActiveDirectory -ErrorAction Stop }
catch { Write-Warning "ActiveDirectory module missing - run this on a box with RSAT-AD-PowerShell. Aborting."; Stop-Transcript | Out-Null; return }

# ----------------------------------------------------------------------------
Write-Section "1. Forest / domain overview"
try {
    $forest = Get-ADForest
    $domain = Get-ADDomain
    Write-Host ("  Forest root        : {0}" -f $forest.RootDomain)
    Write-Host ("  Forest mode        : {0}" -f $forest.ForestMode)
    Write-Host ("  Domain             : {0} ({1})" -f $domain.DNSRoot, $domain.NetBIOSName)
    Write-Host ("  Domain mode        : {0}" -f $domain.DomainMode)
    Write-Host ("  UPN suffixes       : {0}" -f (($forest.UPNSuffixes -join ', ')))
    Write-Host "`n  -- FSMO holders --"
    Write-Host ("  SchemaMaster        : {0}" -f $forest.SchemaMaster)
    Write-Host ("  DomainNamingMaster  : {0}" -f $forest.DomainNamingMaster)
    Write-Host ("  PDCEmulator         : {0}" -f $domain.PDCEmulator)
    Write-Host ("  RIDMaster           : {0}" -f $domain.RIDMaster)
    Write-Host ("  InfrastructureMaster: {0}" -f $domain.InfrastructureMaster)

    # If every FSMO role sits on one host, that host is the domain's single point of failure.
    $fsmoHosts = @($forest.SchemaMaster,$forest.DomainNamingMaster,$domain.PDCEmulator,$domain.RIDMaster,$domain.InfrastructureMaster) | Sort-Object -Unique
    if ($fsmoHosts.Count -eq 1) { Flag "All 5 FSMO roles on a single host ($fsmoHosts). Split or plan careful transfer before retiring it." }
    $forestFunctional = $forest.ForestMode
    if ("$forestFunctional" -match '2008|2012') { Flag "Forest/domain functional level is $forestFunctional - review before introducing newer DCs." }
} catch { Write-Warning ("Forest/domain query failed: {0}" -f $_.Exception.Message) }

# ----------------------------------------------------------------------------
Write-Section "2. Sites, subnets, and DC placement (Azure needs its own site)"
try {
    $dcsAll = Get-ADDomainController -Filter * -ErrorAction Stop
    Write-Host "  -- Sites and how many DCs each holds --"
    Get-ADReplicationSite -Filter * | ForEach-Object {
        $siteName = $_.Name
        $count = ($dcsAll | Where-Object { $_.Site -eq $siteName }).Count
        Write-Host ("    {0,-25} DCs: {1}" -f $siteName, $count)
    }
    Write-Host "`n  -- Subnets mapped to sites --"
    Get-ADReplicationSubnet -Filter * -Properties Site |
        Select-Object Name, @{N='Site';E={($_.Site -split ',')[0] -replace 'CN='}} |
        Format-Table -AutoSize
    Flag "Plan a dedicated AD Site + subnet(s) for Azure so new DCs replicate on a sane topology, not via the default site."
} catch { Write-Warning ("Site/subnet query failed: {0}" -f $_.Exception.Message) }

# ----------------------------------------------------------------------------
Write-Section "3. All domain controllers - roles, GC, OS, IP"
try {
    $dcsAll | Select-Object Name, Site, IsGlobalCatalog, IsReadOnly, OperatingSystem, IPv4Address,
        @{N='FSMO';E={ ($_.OperationMasterRoles -join ',') }} |
        Sort-Object Site, Name | Format-Table -AutoSize

    $gcCount = ($dcsAll | Where-Object IsGlobalCatalog).Count
    if ($gcCount -le 1) { Flag "Only $gcCount Global Catalog in the domain. Add another GC before retiring one." }
    # Old-OS DCs are their own migration item.
    $dcsAll | Where-Object { $_.OperatingSystem -match '2008|2012' } |
        ForEach-Object { Flag "DC $($_.Name) runs $($_.OperatingSystem) - end of life, factor into the rebuild." }
} catch { Write-Warning ("DC enumeration failed: {0}" -f $_.Exception.Message) }

# ----------------------------------------------------------------------------
Write-Section "4. Role location map (who holds the dangerous roles)"
# Check every DC's installed features so the deep-dives target the right host, rather
# than assuming everything sits on one box. Member servers are covered in the sweep (section 10).
$roleHosts = @{ CA=@(); NPS=@(); DHCP=@(); DNS=@(); RDSLic=@() }
foreach ($dc in $dcsAll) {
    $feat = Get-RemoteFeatures $dc.HostName
    if ($null -eq $feat) { Write-Warning "  Could not read features from $($dc.HostName) (WinRM?)"; continue }
    if ($feat -contains 'AD-Certificate')  { $roleHosts.CA     += $dc.HostName }
    if ($feat -contains 'NPAS')            { $roleHosts.NPS    += $dc.HostName }
    if ($feat -contains 'DHCP')            { $roleHosts.DHCP   += $dc.HostName }
    if ($feat -contains 'DNS')             { $roleHosts.DNS    += $dc.HostName }
    if ($feat -contains 'RDS-Licensing')   { $roleHosts.RDSLic += $dc.HostName }
}
$roleHosts.GetEnumerator() | ForEach-Object {
    Write-Host ("  {0,-8}: {1}" -f $_.Key, (($_.Value -join ', ')))
}
if ($roleHosts.CA)   { Flag "Certificate Authority on: $($roleHosts.CA -join ', '). CA migration/reissue is the tentpole task." }
if ($roleHosts.NPS)  { Flag "NPS/RADIUS on: $($roleHosts.NPS -join ', '). Find every device/service authenticating against it." }

if (-not $QuickTopologyOnly) {
    # ------------------------------------------------------------------------
    Write-Section "5. AD replication health (repadmin)"
    try {
        Write-Host "  -- repadmin /replsummary --"
        repadmin /replsummary 2>&1 | Out-Host
    } catch { Write-Warning ("repadmin failed: {0}" -f $_.Exception.Message) }

    # ------------------------------------------------------------------------
    Write-Section "6. Per-DC health (dcdiag - pass/fail lines only)"
    foreach ($dc in $dcsAll) {
        Write-Host "`n  -- dcdiag /s:$($dc.HostName) --" -ForegroundColor Yellow
        try {
            $out = dcdiag /s:$($dc.HostName) 2>&1
            $results = $out | Select-String 'passed test|failed test'
            $results | ForEach-Object { Write-Host ("    " + $_.ToString().Trim()) }
            # Extract the names of failed tests. SystemLog just scans the event log for any
            # error and is notoriously benign, so don't treat it as a migration blocker on
            # its own - only flag if something that actually matters failed.
            $failed = $out | Select-String 'failed test' | ForEach-Object { ($_.ToString() -split 'failed test')[-1].Trim() }
            $real   = @($failed | Where-Object { $_ -ne 'SystemLog' })
            if ($real.Count) {
                Flag "dcdiag failures on $($dc.HostName): $($real -join ', ') - review before migrating."
            } elseif ($failed) {
                Write-Host "    Note: only SystemLog failed - event-log noise, not a DC health problem." -ForegroundColor DarkYellow
            }
        } catch { Write-Warning ("dcdiag failed for $($dc.HostName): {0}" -f $_.Exception.Message) }
    }

    # ------------------------------------------------------------------------
    Write-Section "7. SYSVOL replication type (FRS is a hard blocker)"
    # New (2019+) DCs cannot use FRS for SYSVOL. If this isn't 'Eliminated', DFSR migration
    # of SYSVOL must happen BEFORE you promote any new DC in Azure.
    try {
        $pdc = $domain.PDCEmulator
        $state = Invoke-Command -ComputerName $pdc -ScriptBlock { dfsrmig /getglobalstate } -ErrorAction Stop 2>&1
        $state | Out-Host
        if ("$state" -notmatch "Eliminated") {
            Flag "SYSVOL is NOT fully on DFSR (state not 'Eliminated'). Complete FRS->DFSR migration before adding new DCs."
        }
    } catch { Write-Warning ("dfsrmig check failed: {0}" -f $_.Exception.Message) }
}

# ----------------------------------------------------------------------------
Write-Section "8. Certificate Authority deep-dive"
# Determines whether the CA is a simple backup/restore migration or a full reissue.
foreach ($caHost in $roleHosts.CA) {
    Write-Host "`n  === CA host: $caHost ===" -ForegroundColor Yellow
    try {
        Invoke-Command -ComputerName $caHost -ErrorAction Stop -ScriptBlock {
            Write-Host "  -- CA info --"
            certutil -cainfo 2>&1 | Select-String 'CA name|CA type|CA cert|CRL|DNS Name|Provider|template' | ForEach-Object { "    $_" }

            Write-Host "`n  -- Published templates (what this CA issues) --"
            certutil -CATemplates 2>&1 | ForEach-Object { "    $_" }

            Write-Host "`n  -- CRL distribution points (CDP) --"
            certutil -getreg CA\CRLPublicationURLs 2>&1 | Select-String 'http|ldap|file|=' | ForEach-Object { "    $_" }

            Write-Host "`n  -- CA cert publication (AIA) --"
            certutil -getreg CA\CACertPublicationURLs 2>&1 | Select-String 'http|ldap|file|=' | ForEach-Object { "    $_" }

            Write-Host "`n  -- CA database location (for backup planning) --"
            $cfg = 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration'
            $db  = Get-ItemProperty $cfg -ErrorAction SilentlyContinue
            "    DBDirectory    : $($db.DBDirectory)"
            "    DBLogDirectory : $($db.DBLogDirectory)"
            "    Active CA      : $($db.Active)"
            # CSP / key provider / hash - decides whether keys are exportable and how to move them.
            if ($db.Active) {
                $csp = Get-ItemProperty "$cfg\$($db.Active)\CSP" -ErrorAction SilentlyContinue
                "    Provider       : $($csp.Provider)"
                "    HashAlgorithm  : $($csp.HashAlgorithm)"
            }
        }
        Flag "CA on $caHost - if CDP/AIA point at this host's name/IP, clients must be repointed or the names preserved on the new CA. Plan CA backup (certutil -backup) + private key handling."
    } catch { Write-Warning ("CA deep-dive failed on $caHost : {0}" -f $_.Exception.Message) }
}
if (-not $roleHosts.CA) { Write-Host "  No CA found on the DCs (check member servers in the sweep)." }

# ----------------------------------------------------------------------------
Write-Section "9. NPS / RADIUS deep-dive"
foreach ($npsHost in $roleHosts.NPS) {
    Write-Host "`n  === NPS host: $npsHost ===" -ForegroundColor Yellow
    if ($SkipNpsExport) {
        Write-Host "  Export skipped (-SkipNpsExport). Role present; open the NPS console on $npsHost for clients/policies."
        continue
    }
    try {
        $stamp   = Get-Date -Format yyyyMMdd_HHmmss
        $target  = Join-Path $NpsExportDir "NPS-export_${npsHost}_$stamp.xml"
        Invoke-Command -ComputerName $npsHost -ErrorAction Stop -ScriptBlock {
            param($dir, $file)
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            # exportPSK=YES puts shared secrets in the XML in CLEARTEXT. Sensitive file.
            netsh nps export filename="$file" exportPSK=YES | Out-Null
            if (Test-Path $file) {
                Write-Host "    Exported NPS config to: $file (on $env:COMPUTERNAME)"
                # Best-effort quick peek at RADIUS clients so you don't have to open the XML.
                try {
                    [xml]$x = Get-Content $file
                    $clients = $x.SelectNodes("//*[local-name()='RadiusClients']//*[local-name()='Children']/*")
                    if ($clients.Count) {
                        Write-Host "    -- RADIUS clients (best-effort parse) --"
                        foreach ($c in $clients) {
                            $ip = ($c.SelectSingleNode(".//*[local-name()='Address']")).'#text'
                            Write-Host ("      {0}  {1}" -f $c.name, $ip)
                        }
                    } else { Write-Host "    (Could not parse clients from XML - open it manually.)" }
                } catch { Write-Host "    (XML parse skipped: $($_.Exception.Message))" }
            }
        } -ArgumentList $NpsExportDir, $target
        Flag "NPS config exported on $npsHost. File holds shared secrets in cleartext - secure it, and enumerate what authenticates via those RADIUS clients."
    } catch { Write-Warning ("NPS export failed on $npsHost : {0}" -f $_.Exception.Message) }
}
if (-not $roleHosts.NPS) { Write-Host "  No NPS role found on the DCs." }

# ----------------------------------------------------------------------------
Write-Section "10. DNS forwarders + DHCP dependency map (who points at what)"
foreach ($dnsHost in $roleHosts.DNS) {
    try {
        $fwd = (Get-DnsServerForwarder -ComputerName $dnsHost -ErrorAction Stop).IPAddress -join ', '
        Write-Host ("  [$dnsHost] DNS forwarders: {0}" -f $fwd)
    } catch { Write-Warning ("Forwarder read failed on $dnsHost : {0}" -f $_.Exception.Message) }
}
foreach ($dhcpHost in $roleHosts.DHCP) {
    try {
        Write-Host "`n  [$dhcpHost] DHCP-handed DNS servers (option 6) - shows who clients depend on:"
        $srvOpt = (Get-DhcpServerv4OptionValue -ComputerName $dhcpHost -OptionId 6 -ErrorAction SilentlyContinue).Value
        Write-Host ("    Server-level option 6: {0}" -f ($srvOpt -join ', '))
        Get-DhcpServerv4Scope -ComputerName $dhcpHost -ErrorAction Stop | ForEach-Object {
            $so = (Get-DhcpServerv4OptionValue -ComputerName $dhcpHost -ScopeId $_.ScopeId -OptionId 6 -ErrorAction SilentlyContinue).Value
            Write-Host ("    Scope {0} ({1}) option 6: {2}" -f $_.ScopeId, $_.Name, ($so -join ', '))
        }
        Flag "Check the option-6 DNS IPs above - any that match a server you're retiring means clients must be repointed before it goes."
    } catch { Write-Warning ("DHCP dependency read failed on $dhcpHost : {0}" -f $_.Exception.Message) }
}

# ----------------------------------------------------------------------------
if (-not $QuickTopologyOnly) {
    Write-Section "11. Member server light inventory (roles per server)"
    # Everything with a Server OS in AD. Reachability-tested, roles listed. This is where
    # a stray DHCP/CA/file server on a member box shows up.
    try {
        $servers = Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' -Properties OperatingSystem, IPv4Address, LastLogonDate |
                   Sort-Object Name
        # Optional: skip long-dead objects. AD hoards stale computer accounts (a 2003 boneyard
        # is normal), and pinging 40 corpses is slow and noisy. 0 = sweep everything.
        if ($ActiveWithinDays -gt 0) {
            $cutoff = (Get-Date).AddDays(-$ActiveWithinDays)
            $servers = $servers | Where-Object { $_.LastLogonDate -and $_.LastLogonDate -gt $cutoff }
            Write-Host "  (Showing only servers with a logon in the last $ActiveWithinDays days.)" -ForegroundColor DarkGray
        }
        foreach ($s in $servers) {
            # Stale objects can have a null DNSHostName, which blows up Test-Connection with a
            # parameter-binding error that -ErrorAction can't catch. Guard the input first.
            $target = if ($s.DNSHostName) { $s.DNSHostName } else { $s.Name }
            if ([string]::IsNullOrWhiteSpace($target)) {
                Write-Host ("  {0,-18} [no hostname - stale object?]" -f $s.Name) -ForegroundColor DarkGray
                continue
            }
            $reachable = Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue
            if (-not $reachable) {
                Write-Host ("  {0,-18} [unreachable]  {1}" -f $s.Name, $s.OperatingSystem) -ForegroundColor DarkGray
                continue
            }
            $feat = Get-RemoteFeatures $target
            $roles = if ($feat) { ($feat | Where-Object { $_ -in 'AD-Certificate','NPAS','DHCP','DNS','RDS-Licensing','Remote-Desktop-Services','FileAndStorage-Services','Web-Server','AD-Domain-Services','Print-Server','WDS','Hyper-V' }) -join ', ' } else { '(features unreadable)' }
            Write-Host ("  {0,-18} {1,-38} {2}" -f $s.Name, $s.OperatingSystem, $roles)
        }
    } catch { Write-Warning ("Server sweep failed: {0}" -f $_.Exception.Message) }
}

# ----------------------------------------------------------------------------
Write-Section "SUMMARY - migration flags in priority-ish order"
if ($Flags.Count) {
    $i = 1
    foreach ($f in $Flags) { Write-Host ("  {0}. {1}" -f $i++, $f) -ForegroundColor Red }
} else { Write-Host "  No flags raised (or the checks that raise them didn't run)." }

Write-Host "`nSuggested read order for the plan:"
Write-Host "  1. CA (backup/restore vs reissue)   2. FSMO/GC/AD DS sequencing   3. SYSVOL/DFSR state"
Write-Host "  4. DNS + DHCP dependency repoint     5. NPS/RADIUS client remediation   6. RDS licensing"

Write-Section "Done"
Write-Host "Report: $OutFile"
Write-Host "Read-only EXCEPT the NPS export (if it ran). Everything else just looked."
Stop-Transcript | Out-Null
