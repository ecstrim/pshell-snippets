# Replace 'COM3' with your actual port number and set the correct baud rate
$portName = "COM3"
$baudRate = 115200 # The baud rate should match your 3D printer's configuration

$parity = [System.IO.Ports.Parity]::None
$dataBits = 8
$stopBits = [System.IO.Ports.StopBits]::One


# Create and configure the serial port
$serialPort = new-Object System.IO.Ports.SerialPort $portName, $baudRate, $parity, $dataBits, $stopBits
$serialPort.DtrEnable = $true # Enable DTR (Data Terminal Ready)
$serialPort.RtsEnable = $true # Enable RTS (Request to Send)
$serialPort.NewLine = "`r`n" # Set the new line value if it's different for your printer
$serialPort.ReadTimeout = 500 # Set the read timeout if needed

try {
    # Open the serial  
    $serialPort.Open()

    # Send a G-code command to the printer
    $gcodeCommand = "M503" # Example G-code command for homing the printer
    $serialPort.WriteLine($gcodeCommand)

    # Give the printer some time to process the command
    Start-Sleep -Milliseconds 500

    # Read the response from the printer
    $response = $serialPort.ReadLine()
    Write-Host "Response: $response"
}
catch {
    Write-Error "An error occurred: $_"
}
finally {
    # Close the serial port
    if ($serialPort -and $serialPort.IsOpen) {
        $serialPort.Close()
    }
}
