<#

Checks a list of IPs for http reachability by running an Invoke-WebRequest  

#>
$ipPrefix = "10.0.109"

$ipAddresses = @()

# non contigous ranges
$ranges = 20..29 + 37..39 + 40..45 + 48..49 + 50..57

# compose the ip list
foreach ($n in $ranges) {
    $ipAddresses += "${ipPrefix}.$n"
}

foreach ($ip in $ipAddresses) {
    Write-Host "IP: $ip" -ForegroundColor Cyan
    
    try {
        # 
        $response = Invoke-WebRequest -Uri "http://$ip" -TimeoutSec 5 #-Method Head
        
        # check the request was successful
        if ($response.StatusCode -eq 200) {
            Write-Host "   Success: $($response.StatusCode)" -ForegroundColor Green
            Write-Host "   Headers for ${ip}:`n $($response.Headers)" -ForegroundColor Green
        }
        else {
            Write-Host "   Failed with status code: $($response.StatusCode)" -ForegroundColor Yellow
        }
    }
    catch {
        if ($_.Exception.Message -like "*timeout*") {
            Write-Host "   Timeout connecting to $ip." -ForegroundColor Red
        }
        else {
            Write-Host "   Error connecting to $ip. Details: $_" -ForegroundColor Magenta
        }
    }
}
