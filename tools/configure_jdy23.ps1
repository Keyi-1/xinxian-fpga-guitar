[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^COM[0-9]+$')][string]$Port,
    [switch]$Configure
)
$ErrorActionPreference='Stop'

function Invoke-JdyCommand($Serial,[string]$Command) {
    $Serial.Write($Command + "`r`n")
    $reply=''
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $lastChange=0L
    while ($watch.ElapsedMilliseconds -lt 1500) {
        $part=$Serial.ReadExisting()
        if ($part.Length -gt 0) { $reply+=$part; $lastChange=$watch.ElapsedMilliseconds }
        if ($reply.Length -gt 0 -and ($watch.ElapsedMilliseconds-$lastChange) -ge 120) { break }
        Start-Sleep -Milliseconds 15
    }
    if ($reply.Length -eq 0) { throw "No reply to $Command at 9600/8N1. Stop and check power, wiring and module baud rate." }
    if ($reply -match '(?i)ERROR|\+ERR|FAIL') { throw "Module rejected ${Command}: $reply" }
    return $reply.Trim()
}

function Set-JdyConfiguration($Serial,[scriptblock]$Log) {
    $version=Invoke-JdyCommand $Serial 'AT+VER'
    & $Log "AT+VER => $version"
    if ($version -notmatch '(?i)JDY-23') { throw 'This script requires JDY-23 firmware; no settings changed.' }
    $state=Invoke-JdyCommand $Serial 'AT+STAT'
    & $Log "AT+STAT => $state"
    if ($state -notmatch '\+STAT:\s*0{1,2}(?:\s|$)') { throw 'Disconnect the phone before configuring the module.' }
    foreach ($command in @('AT+HOSTEN0','AT+STARTEN1','AT+ADVIN1','AT+ENLOG0','AT+MTU1','AT+NAMEXINXIAN-JDY23')) {
        $reply=Invoke-JdyCommand $Serial $command
        & $Log "$command => $reply"
        if ($reply -notmatch '(?i)(?:^|\s)\+?OK(?:\s|$)') { throw "Missing +OK for $command; configuration is incomplete." }
    }
    $name=Invoke-JdyCommand $Serial 'AT+NAME'
    & $Log "AT+NAME => $name"
    if ($name -notmatch 'XINXIAN-JDY23') { throw 'Broadcast name verification failed.' }
    & $Log 'CONFIG_OK. Keep UART at 9600/8N1. Power-cycle the module, then connect it to FPGA. No baud-rate, MAC or firmware write was performed.'
}

$serial=$null
$logPath=Join-Path $PSScriptRoot ('jdy23_config_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.txt')
function Write-JdyLog([string]$Text) {
    $line='[' + (Get-Date -Format o) + '] ' + $Text
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $line
}
try {
    $serial=New-Object System.IO.Ports.SerialPort $Port,9600,None,8,One
    $serial.DtrEnable=$false
    $serial.RtsEnable=$false
    $serial.WriteTimeout=1500
    $serial.Open()
    $serial.DiscardInBuffer()
    if ($Configure) { Set-JdyConfiguration $serial {param($message) Write-JdyLog $message} }
    else {
        foreach ($command in @('AT+VER','AT+STAT','AT+NAME','AT+BAUD','AT+MAC')) {
            Write-JdyLog ($command + ' => ' + (Invoke-JdyCommand $serial $command))
        }
        Write-JdyLog 'Queries finished. No configuration command sent. Use -Configure only with module UART disconnected from FPGA and phone disconnected.'
    }
} catch { Write-JdyLog ('FAILED: ' + $_.Exception.Message); throw }
finally {
    if ($null -ne $serial) {
        try { if ($serial.IsOpen) { $serial.Close() } } catch { Write-JdyLog ('CLOSE_FAILED: ' + $_.Exception.Message) }
        try { $serial.Dispose() } catch { Write-JdyLog ('DISPOSE_FAILED: ' + $_.Exception.Message) }
    }
    Write-Host "Saved log: $logPath"
}
