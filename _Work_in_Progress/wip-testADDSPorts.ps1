# Define the target host and ports to check
$hostname = "YourHostName"

# List of ports and services
$ports = @(
    135, # RPC Endpoint Mapper
    389, # LDAP
    636, # LDAP SSL
    3268, # LDAP GC
    3269, # LDAP GC SSL
    53, # DNS
    88, # Kerberos
    445 # SMB
)

# Function to check if a port is open
function Test-Port {
    param (
        [string]$hostname,
        [int]$port
    )
    
    try {
        $tcpConnection = New-Object System.Net.Sockets.TcpClient($hostname, $port)
        $tcpConnection.Close()
        return $true
    }
    catch {
        return $false
    }
}

# Check individual ports
foreach ($port in $ports) {
    $isOpen = Test-Port -hostname $hostname -port $port
    if ($isOpen) {
        Write-Output "Port $port is open on $hostname"
    }
    else {
        Write-Output "Port $port is closed on $hostname"
    }
}

# Function to check a range of ports
function Test-PortRange {
    param (
        [string]$hostname,
        [int]$startPort,
        [int]$endPort
    )
    
    for ($port = $startPort; $port -le $endPort; $port++) {
        $isOpen = Test-Port -hostname $hostname -port $port
        if ($isOpen) {
            Write-Output "Port $port is open on $hostname"
        }
        else {
            Write-Output "Port $port is closed on $hostname"
        }
    }
}

# Check port ranges
#Test-PortRange -hostname $hostname -startPort 1024 -endPort 65535
