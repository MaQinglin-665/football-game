param(
 [ValidateSet('3v3','5v5','6v6','9v9','11v11')][string]$Mode='11v11',
 [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
try {
 $project=Join-Path $PSScriptRoot 'source'
 $engine=Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime/Godot.exe'
 if ($env:GODOT_EXE) { $engine=$env:GODOT_EXE }
 if (!(Test-Path -LiteralPath $engine)) {
  $found=Get-Command godot,Godot.exe,godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
  if (!$found) { throw 'Godot 4.6.3 not found. Set GODOT_EXE to the engine executable.' }
  $engine=$found.Source
 }
 $scenes=@{'3v3'='training_3v3.tscn';'5v5'='match_5v5.tscn';'6v6'='match_6v6_small.tscn';'9v9'='match_9v9.tscn';'11v11'='match.tscn'}
 $logs=Join-Path $PSScriptRoot 'verification'
 New-Item -ItemType Directory -Force -Path $logs | Out-Null
 $importLog=Join-Path $logs ('startup-import-'+$PID+'.log')
 Write-Host 'Preparing Godot resources and script index. First launch may take a moment...'
 $importArgs=@('--headless','--path',('"'+$project+'"'),'--editor','--import','--quit','--log-file',('"'+$importLog+'"'))
 $process=Start-Process -FilePath $engine -ArgumentList $importArgs -PassThru -Wait -WindowStyle Hidden
 if ($process.ExitCode -ne 0) { throw "Resource import failed. See $importLog" }
 if (!(Test-Path -LiteralPath $importLog)) { throw 'Import log was not created.' }
 if (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { throw "Resource import reported errors. See $importLog" }
 if (!(Test-Path -LiteralPath (Join-Path $project '.godot/global_script_class_cache.cfg'))) { throw 'Godot script index is missing.' }
 if ($PrepareOnly) { Write-Host 'Resource preparation passed.'; exit 0 }
 $gameLog=Join-Path $logs ('play-'+$Mode+'-'+$PID+'.log')
 $gameArgs=@('--path',('"'+$project+'"'),('res://scenes/'+$scenes[$Mode]),'--rendering-method','forward_plus','--log-file',('"'+$gameLog+'"'))
 Start-Process -FilePath $engine -ArgumentList $gameArgs -WorkingDirectory $project | Out-Null
} catch {
 Write-Host $_.Exception.Message -ForegroundColor Red
 if (!$PrepareOnly) { Read-Host 'Press Enter to close' | Out-Null }
 exit 1
}
