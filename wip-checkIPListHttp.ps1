<#

Checks a list of IPs for http reachability by running an Invoke-WebRequest  

#>


# Start with the first IP address
$ipAddresses = @("10.0.108.1")

# Define the ranges of IP addresses
$ranges = 20..29 + 37..39 + 40..45 + 48..49 + 50..57

# Iterate through the ranges and add to the IP addresses array
foreach ($number in $ranges) {
    $ipAddresses += "10.0.108.$number"
}

# Iterate through the IP addresses and make a request to each
foreach ($ip in $ipAddresses) {
    Write-Host "Checking IP address: $ip" -ForegroundColor Cyan
    
    try {
        # Running Invoke-WebRequest against the IP
        $response = Invoke-WebRequest -Uri "http://$ip" -TimeoutSec 5 -Method Head
        
        # Checking if the request was successful
        if ($response.StatusCode -eq 200) {
            Write-Host "Success: $($response.StatusCode)" -ForegroundColor Green
            Write-Host "Headers for ${ip}:`n $($response.Headers)" -ForegroundColor Green
        }
        else {
            Write-Host "Failed with status code: $($response.StatusCode)" -ForegroundColor Yellow
        }
    }
    catch {
        if ($_.Exception.Message -like "*timeout*") {
            Write-Host "Timeout connecting to $ip." -ForegroundColor Red
        }
        else {
            Write-Host "Error connecting to $ip. Details: $_" -ForegroundColor Magenta
        }
    }
}
