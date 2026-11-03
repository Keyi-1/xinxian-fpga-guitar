param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^COM[0-9]+$')]
    [string]$Port,
    [switch]$StartBle
)
$ErrorActionPreference = 'Stop'
$diagnosticPort = New-Object System.IO.Ports.SerialPort $Port,115200,None,8,One
$diagnosticPort.DtrEnable = $true
$diagnosticPort.ReadTimeout = 2000
try {
    $diagnosticPort.Open()
    Write-Host "Reading $Port. Ctrl+C to stop."
    if ($StartBle) {
        Start-Sleep -Milliseconds 500
        $diagnosticPort.Write('ble_start' + [char]13 + [char]10)
        Write-Host 'Sent ble_start to begin RF/BLE initialization.'
    }
    while ($true) {
        $diagnosticText = $diagnosticPort.ReadExisting()
        if ($diagnosticText.Length -gt 0) { Write-Host -NoNewline $diagnosticText }
        Start-Sleep -Milliseconds 200
    }
}
finally {
    if ($diagnosticPort.IsOpen) { $diagnosticPort.Close() }
    $diagnosticPort.Dispose()
}
