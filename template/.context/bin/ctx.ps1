# ctx.ps1 - run .context/bin/ctx (POSIX sh) from PowerShell.
# On Windows it uses Git for Windows' bash, never a bare "bash" (System32\bash.exe is the WSL launcher).
$ErrorActionPreference = 'Stop'

function Find-GitBash {
    if ($env:CTX_BASH_EXE -and (Test-Path -LiteralPath $env:CTX_BASH_EXE)) { return $env:CTX_BASH_EXE }
    $candidates = @()
    try {
        $exec = (& git --exec-path 2>$null)
        if ($exec) {
            $candidates += (Join-Path $exec '..\..\..\bin\bash.exe')
            $candidates += (Join-Path $exec '..\..\..\usr\bin\bash.exe')
        }
    } catch { }
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) { $candidates += (Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe') }
    foreach ($root in @($env:ProgramFiles, $env:ProgramW6432, $env:LOCALAPPDATA + '\Programs')) {
        if ($root) { $candidates += (Join-Path $root 'Git\bin\bash.exe') }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

$script = (Join-Path $PSScriptRoot 'ctx') -replace '\\', '/'
if ($null -ne $IsWindows -and -not $IsWindows) {
    & sh $script @args
    exit $LASTEXITCODE
}
$bash = Find-GitBash
if (-not $bash) {
    [Console]::Error.WriteLine('ctx: Git Bash not found. Install Git for Windows or set CTX_BASH_EXE to its bin\bash.exe.')
    exit 1
}
& $bash $script @args
exit $LASTEXITCODE
