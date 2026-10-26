param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^COM[0-9]+$')]
    [string]$Port,
    [ValidateSet('none', 'ble_start', 'ble_keepcap')]
    [string]$BleCommand = 'none'
)
$ErrorActionPreference = 'Stop'
$logPath = Join-Path $PSScriptRoot ('diagnostic_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.txt')
$diagnosticLog = New-Object System.IO.StreamWriter($logPath, $false, [System.Text.Encoding]::UTF8)
$diagnosticLog.AutoFlush = $true
$diagnosticPort = New-Object System.IO.Ports.SerialPort $Port,115200,None,8,One
$diagnosticPort.DtrEnable = $true
$diagnosticPort.ReadTimeout = 2000
try {
    $diagnosticPort.Open()
    Write-Host "Reading $Port. Log: $logPath. Ctrl+C to stop."
    $diagnosticLog.WriteLine("Port=$Port Command=$BleCommand Started=$(Get-Date -Format o)")
    if ($BleCommand -ne 'none') {
        Start-Sleep -Milliseconds 1000
        $diagnosticPort.Write($BleCommand + [char]13 + [char]10)
        Write-Host "Sent $BleCommand."
    }
    while ($true) {
        try {
            $diagnosticText = $diagnosticPort.ReadExisting()
        } catch {
            $diagnosticLog.WriteLine("`r`nPORT_READ_FAILED $(Get-Date -Format o): $($_.Exception.Message)")
            Write-Warning "USB port reading stopped. Saved log: $logPath"
            break
        }
        if ($diagnosticText.Length -gt 0) {
            $diagnosticLog.Write($diagnosticText)
            Write-Host -NoNewline $diagnosticText
        }
        Start-Sleep -Milliseconds 100
    }
} finally {
    if ($diagnosticPort.IsOpen) { $diagnosticPort.Close() }
    $diagnosticPort.Dispose()
    $diagnosticLog.Dispose()
}
