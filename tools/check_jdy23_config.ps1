$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$path=Join-Path $root 'firmware/jdy23/configure_jdy23.ps1'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Configuration script syntax errors'}
foreach($name in @('Invoke-JdyCommand','Set-JdyConfiguration')) {
    $fn=$ast.Find({param($item) $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq $name},$true)
    if($null -eq $fn){throw "Missing function $name"}
    . ([scriptblock]::Create($fn.Extent.Text))
}
# Only extracted functions execute; no SerialPort construction/Open/main script.
$mock=New-Object PSObject -Property @{Sent='';Reply="+OK`r`n"}
$mock | Add-Member ScriptMethod Write {param($s) $this.Sent=$s}
$mock | Add-Member ScriptMethod ReadExisting {$value=$this.Reply;$this.Reply='';return $value}
if((Invoke-JdyCommand $mock 'AT+TEST') -ne '+OK' -or $mock.Sent -cne "AT+TEST`r`n"){throw 'CRLF or reply parsing failed'}
$mock.Reply='+ERROR'
try{Invoke-JdyCommand $mock 'AT+TEST';throw 'Expected module rejection'}catch{if($_ -match 'Expected module rejection'){throw}}

$script:mode='ok';$script:commands=@();$script:notes=@()
function Invoke-JdyCommand($Serial,[string]$Command) {
    $script:commands+=,$Command
    if($Command -eq 'AT+VER'){if($script:mode -eq 'wrong'){return '+VER:OTHER'};return '+VER:JDY-23-V2.1'}
    if($Command -eq 'AT+STAT'){if($script:mode -eq 'connected'){return '+STAT:1'};return '+STAT:00'}
    if($Command -eq 'AT+NAME'){if($script:mode -eq 'badname'){return '+NAME:JDY-23'};return '+NAME:XINXIAN-JDY23'}
    if($script:mode -eq 'reject' -and $Command -eq 'AT+MTU1'){return '+ERROR'}
    return '+OK'
}
Set-JdyConfiguration $null {param($s) $script:notes+=,$s}
if($script:commands.Count -ne 9 -or $script:notes[-1] -notmatch '^CONFIG_OK'){throw 'Configuration sequence failed'}
if(($script:commands -join ' ') -match 'AT\+(?:BAUD|MAC|DEFAULT|RST|SLEEP)'){throw 'Unexpected destructive/unneeded command'}
foreach($mode in @('wrong','connected','reject','badname')) {
    $script:mode=$mode;$script:commands=@();$failed=$false
    try{Set-JdyConfiguration $null {param($s)}}catch{$failed=$true}
    if(-not $failed){throw "Expected rejection for $mode"}
    if($mode -eq 'wrong' -and $script:commands.Count -ne 1){throw 'Wrong model received configuration'}
    if($mode -eq 'connected' -and $script:commands.Count -ne 2){throw 'Connected module received configuration'}
}
$out=Join-Path $root 'build/jdy23/v1/config_verification.json'
@{result='PASS';hardware_tested=$false;real_serial_opened=$false;cases=7;source_sha256=(Get-FileHash $path).Hash.ToLower()} |
    ConvertTo-Json | Set-Content $out -Encoding UTF8
Write-Output 'PASS: actual configuration functions; CRLF; error replies; expected settings; wrong model/connected/rejected setting/name mismatch stop safely; no physical COM'
