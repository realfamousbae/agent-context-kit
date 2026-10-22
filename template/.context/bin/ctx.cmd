@echo off
rem ctx.cmd - run .context/bin/ctx (POSIX sh) from cmd.exe through Git for Windows' bash.
rem Never uses a bare "bash": in System32 that is the WSL launcher with a different file system.
setlocal
set "CTX_BASH="
if defined CTX_BASH_EXE call :try "%CTX_BASH_EXE%"
set "CTX_GITEXEC="
for /f "delims=" %%G in ('git --exec-path 2^>nul') do set "CTX_GITEXEC=%%G"
if defined CTX_GITEXEC call :try "%CTX_GITEXEC%\..\..\..\bin\bash.exe"
if defined CTX_GITEXEC call :try "%CTX_GITEXEC%\..\..\..\usr\bin\bash.exe"
for /f "delims=" %%G in ('where git 2^>nul') do call :try "%%~dpG..\bin\bash.exe"
call :try "%ProgramFiles%\Git\bin\bash.exe"
call :try "%ProgramW6432%\Git\bin\bash.exe"
call :try "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined CTX_BASH (
  echo ctx: Git Bash not found. Install Git for Windows or set CTX_BASH_EXE to its bin\bash.exe. 1>&2
  exit /b 1
)
set "CTX_SCRIPT=%~dp0ctx"
set "CTX_SCRIPT=%CTX_SCRIPT:\=/%"
"%CTX_BASH%" "%CTX_SCRIPT%" %*
exit /b %ERRORLEVEL%

:try
if defined CTX_BASH exit /b 0
if exist "%~f1" set "CTX_BASH=%~f1"
exit /b 0
