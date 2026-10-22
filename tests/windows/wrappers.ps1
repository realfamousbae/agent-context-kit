# Windows: ctx.ps1 and ctx.cmd find Git Bash and run ctx from PowerShell and cmd.
# Run from the kit root: ./tests/windows/wrappers.ps1 (PowerShell 5.1 or 7).
$ErrorActionPreference = 'Stop'
$kit = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ctx-win-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$script:failed = 0

function Check([string]$name, [bool]$cond, [string]$detail = '') {
    if ($cond) { Write-Host "ok   wrappers: $name" }
    else { Write-Host "FAIL wrappers: $name`n$detail"; $script:failed++ }
}

Push-Location $tmp
try {
    $ErrorActionPreference = 'Continue'
    git init -q 2>&1 | Out-Null
    git config user.name 'Test User'; git config user.email 'test.user@example.invalid'
    git config commit.gpgsign false; git config ctx.author alice; git config ctx.initials aa
    Set-Content -Path README.md -Value '# demo'
    git add README.md; git commit -q -m initial 2>&1 | Out-Null

    if (Test-Path (Join-Path $kit 'install.ps1')) {
        & (Join-Path $kit 'install.ps1') --author alice --initials aa --language en | Out-Host
        Check 'install.ps1 exit code' ($LASTEXITCODE -eq 0)
    } else {
        Copy-Item -Recurse (Join-Path $kit 'template\.context') '.context'
        New-Item -ItemType Directory -Force -Path '.context\templates', '.context\journal' | Out-Null
        Copy-Item -Recurse (Join-Path $kit 'template\i18n\en') '.context\templates\en'
        Copy-Item '.context\templates\en\*.md' '.context\'
    }

    $out = & .\.context\bin\ctx.ps1 brief | Out-String
    Check 'ctx.ps1 brief exit 0' ($LASTEXITCODE -eq 0) $out
    Check 'ctx.ps1 brief output' ($out -match '# ctx brief') $out

    $out = cmd /c '.context\bin\ctx.cmd brief' | Out-String
    Check 'ctx.cmd brief exit 0' ($LASTEXITCODE -eq 0) $out
    Check 'ctx.cmd brief output' ($out -match '# ctx brief') $out

    $out = (cmd /c '.context\bin\ctx.cmd id T' | Out-String).Trim()
    Check 'ctx.cmd id T' ($out -match '^T-\d{8}-aa-1$') $out

    $out = & .\.context\bin\ctx.ps1 claim --new 'Windows task' --area 'src/ docs/' --no-push | Out-String
    Check 'ctx.ps1 claim with spaces in arguments' ($LASTEXITCODE -eq 0 -and $out -match 'Claimed T-') $out
    $tasks = Get-Content '.context\TASKS.md' -Raw
    Check 'claim written to TASKS.md' ($tasks -match 'Windows task — @alice/') $tasks

    $out = cmd /c '.context\bin\ctx.cmd entry --agent codex --model test-model' 2>&1 | Out-String
    Check 'ctx.cmd entry' ($LASTEXITCODE -eq 0 -and $out -match 'alice-codex\.md') $out

    if (Test-Path '.codex\hooks.json') {
        $hooks = Get-Content '.codex\hooks.json' -Raw | ConvertFrom-Json
        New-Item -ItemType Directory -Force -Path 'src\deep' | Out-Null
        Push-Location 'src\deep'
        $out = '{}' | cmd /c $hooks.hooks.SessionStart[0].hooks[0].commandWindows | Out-String
        Pop-Location
        $ok = $false; try { $j = $out | ConvertFrom-Json; $ok = $j.hookSpecificOutput.additionalContext -match '# ctx brief' } catch { }
        Check 'Codex commandWindows SessionStart gives JSON with the brief' $ok $out
        $out = ('{}' | cmd /c $hooks.hooks.Stop[0].hooks[0].commandWindows | Out-String).Trim()
        Check 'Codex commandWindows Stop runs ({} or a reminder with exit 2)' (($LASTEXITCODE -eq 0 -and $out -eq '{}') -or $LASTEXITCODE -eq 2) $out
    }

    $env:CTX_BASH_EXE = 'C:\does\not\exist\bash.exe'
    $out = & .\.context\bin\ctx.ps1 version | Out-String
    Check 'bad CTX_BASH_EXE falls back to discovery' ($LASTEXITCODE -eq 0) $out
    Remove-Item Env:\CTX_BASH_EXE

    $out = & .\.context\bin\ctx.ps1 no-such-command 2>&1 | Out-String
    Check 'exit code is propagated' ($LASTEXITCODE -eq 2) $out
} finally {
    Pop-Location
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($script:failed -gt 0) { Write-Host "wrappers: $script:failed failed"; exit 1 }
Write-Host 'wrappers: all passed'
exit 0
