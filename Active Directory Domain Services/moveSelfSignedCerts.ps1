$sourceCertStore = "Cert:\LocalMachine\CA"
$sourceCertStoreObject = Get-Item $sourceCertStore
$targetCertStore = "Cert:\LocalMachine\Root"
$targetCertStoreObject = Get-Item $targetCertStore

Get-ChildItem $sourceCertStore | ?{$_.Issuer -eq $_.Subject} | %{
    $thumbprint = $null
    $thumbprint = $_.Thumbprint
    $cert = $null
    $cert = Get-Item $sourceCertStore\$thumbprint
    If (!(Test-Path $targetCertStore\$thumbprint)) {
        Write-Host ""
        Write-Host "Adding Certificate With Thumbprint '$thumbprint' To '$targetCertStore'" -ForegroundColor green
        $targetCertStoreObject.Open("ReadWrite")
        $targetCertStoreObject.Add($cert)
        $targetCertStoreObject.Close()
    } Else {
        Write-Host ""
        Write-Host "Certificate With Thumbprint '$thumbprint' Already Exists In '$targetCertStore'" -ForegroundColor Red
    }
    If (Test-Path $targetCertStore\$thumbprint) {
        Write-Host "Removing Certificate With Thumbprint '$thumbprint' From '$sourceCertStore'" -ForegroundColor green
        $sourceCertStoreObject.Open("ReadWrite")
        $sourceCertStoreObject.Remove($cert)
        $sourceCertStoreObject.Close()
    }
}
