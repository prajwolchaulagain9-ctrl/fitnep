# Run from the repository root. No cloud deployment or billing setup is used.
param([switch]$Reset)
$fitnepPreviousPath = $env:PATH
$fitnepPreviousJavaOptions = $env:JAVA_TOOL_OPTIONS
try {
    if (Test-Path -LiteralPath 'D:\studio\jbr\bin\java.exe') {
        $env:PATH = 'D:\studio\jbr\bin;' + $env:PATH
    }
    $env:JAVA_TOOL_OPTIONS = '-Xmx384m -XX:ActiveProcessorCount=2'
    $fitnepDemoArgs = @('emulators:exec', '--only', 'auth,firestore', '--project', 'demo-fitnep', '--non-interactive')
    if (-not $Reset -and (Test-Path -LiteralPath '.dart_tool/free-demo-data/firebase-export-metadata.json')) {
        $fitnepDemoArgs += '--import=.dart_tool/free-demo-data'
    }
    $fitnepDemoArgs += '--export-on-exit=.dart_tool/free-demo-data'
    $fitnepDemoArgs += 'npm --prefix functions run demo:serve'
    & firebase @fitnepDemoArgs
} finally {
    $env:PATH = $fitnepPreviousPath
    $env:JAVA_TOOL_OPTIONS = $fitnepPreviousJavaOptions
}
