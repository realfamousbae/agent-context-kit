# install.ps1 - run install.sh from Windows PowerShell or PowerShell 7 through Git for Windows' bash.
# Usage (in the project repository): & <kit>\install.ps1 --language en --author alice --initials aa
# All arguments are passed to install.sh unchanged; see install.sh --help.
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

$script = (Join-Path $PSScriptRoot 'install.sh') -replace '\\', '/'
$ErrorActionPreference = 'Continue'
if ($null -ne $IsWindows -and -not $IsWindows) {
    & sh $script @args
    exit $LASTEXITCODE
}
$bash = Find-GitBash
if (-not $bash) {
    [Console]::Error.WriteLine('install.ps1: Git Bash not found. Install Git for Windows (https://git-scm.com) or set CTX_BASH_EXE.')
    exit 1
}
& $bash $script @args
exit $LASTEXITCODE
