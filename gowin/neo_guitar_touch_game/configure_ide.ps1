# Close the project before running: an open IDE can save its cached old settings.
$ErrorActionPreference='Stop'
$configPath=Join-Path $PSScriptRoot 'impl\neo_guitar_touch_game_process_config.json'
$body=Get-Content -Raw -LiteralPath $configPath
# Gowin stores both Show_All_Warnings and show_all_warnings. Preserve casing
# and all unrelated settings; PS's case-insensitive JSON object loses this data.
$settings=[ordered]@{
    Place_Option='"4"';Route_Option='"2"';Clock_Route_Order='1';
    Correct_Hold_Violation='true';TopModule='"neo_guitar_touch_game_top"';
    OUTPUT_BASE_NAME='"neo_guitar_touch_game"';JTAG='false';SSPI='true';I2C='true';CPU='true'
}
foreach($name in $settings.Keys){
    $pattern='(?m)(^\s*"'+[regex]::Escape($name)+'"\s*:\s*)(?:true|false|-?\d+|"[^"\r\n]*")'
    if([regex]::Matches($body,$pattern).Count -ne 1){throw "Missing or ambiguous IDE setting: $name"}
    $value=$settings[$name]
    $body=[regex]::Replace($body,$pattern,{param($match)$match.Groups[1].Value+$value})
}
[IO.File]::WriteAllText($configPath,$body,[Text.UTF8Encoding]::new($false))
Write-Output 'IDE configuration saved: Place=4, Route=2, Clock Route Order=1, hold repair enabled.'
Write-Output 'Reopen neo_guitar_touch_game.gprj, then confirm these options in Configuration > Place & Route.'
