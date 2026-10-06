@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "DAI_EXIT_CODE=0"
set "DAI_NO_PAUSE="

if not "%~2"=="" goto usage
if "%~1"=="" goto build
if /i "%~1"=="--no-pause" (
  set "DAI_NO_PAUSE=1"
  goto build
)

:usage
echo Aufruf: "%~nx0" [--no-pause]
endlocal & exit /b 2

:build
for %%V in (11 12 13) do (
  echo.
  echo === Delphi %%V ===
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build.ps1" -Configuration Release -Platform IDE -DelphiVersion %%V -Register -SkipMissing
  if errorlevel 1 set "DAI_EXIT_CODE=1"
)

echo.
if "%DAI_EXIT_CODE%"=="0" (
  echo Build und Registrierung fuer alle gefundenen Delphi-Installationen abgeschlossen.
) else (
  echo Mindestens ein Build oder eine Registrierung ist fehlgeschlagen.
)
if not defined DAI_NO_PAUSE pause
endlocal & exit /b %DAI_EXIT_CODE%
