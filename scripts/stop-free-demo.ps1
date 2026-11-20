$fitnepProjectRoot = Split-Path -Parent $PSScriptRoot
$fitnepPidFile = Join-Path $fitnepProjectRoot '.dart_tool/free-demo-server.pid'
if (-not (Test-Path -LiteralPath $fitnepPidFile)) {
    Write-Output 'No recorded background demo. Use Ctrl+C in its terminal if you started it manually.'
    return
}
$fitnepDemoRootId = [int](Get-Content -LiteralPath $fitnepPidFile)
$fitnepProcesses = @(Get-CimInstance Win32_Process)
$fitnepExpectedScript = Join-Path $PSScriptRoot 'start-free-demo.ps1'
$fitnepRootProcess = $fitnepProcesses | Where-Object {
    $_.ProcessId -eq $fitnepDemoRootId -and $_.CommandLine -match [regex]::Escape($fitnepExpectedScript)
}
if (-not $fitnepRootProcess) { Write-Output 'The recorded background demo is no longer running.'; return }

# Keep the export within this project before asking the CLI to replace it.
$fitnepExportPath = [IO.Path]::GetFullPath((Join-Path $fitnepProjectRoot '.dart_tool/free-demo-data'))
if (-not $fitnepExportPath.StartsWith($fitnepProjectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Demo export must remain inside the project.'
}
Push-Location $fitnepProjectRoot
try {
    & firebase emulators:export $fitnepExportPath --project demo-fitnep --force
    if ($LASTEXITCODE -ne 0) { throw 'Export failed; the demo was left running to preserve its data.' }
} finally { Pop-Location }

$fitnepProcessIds = [System.Collections.Generic.List[int]]::new()
$fitnepProcessIds.Add($fitnepDemoRootId)
for ($fitnepIndex = 0; $fitnepIndex -lt $fitnepProcessIds.Count; $fitnepIndex++) {
    foreach ($fitnepChild in $fitnepProcesses) {
        if ($fitnepChild.ParentProcessId -eq $fitnepProcessIds[$fitnepIndex]) {
            $fitnepProcessIds.Add([int]$fitnepChild.ProcessId)
        }
    }
}
for ($fitnepIndex = $fitnepProcessIds.Count - 1; $fitnepIndex -ge 0; $fitnepIndex--) {
    Stop-Process -Id $fitnepProcessIds[$fitnepIndex] -Force -ErrorAction SilentlyContinue
}
Write-Output 'Saved local demo data and stopped its background processes.'
