@echo off
setlocal
title Rojo Usine :34850 (auto-restart)
cd /d "%~dp0"
set "PORT=34850"

rem Rojo : d'abord Rokit (installe sur ce PC), sinon l'ancien emplacement, sinon le PATH
set "ROJO=%USERPROFILE%\.rokit\bin\rojo.exe"
if not exist "%ROJO%" set "ROJO=%LOCALAPPDATA%\Rojo\rojo.exe"
if not exist "%ROJO%" (
  where rojo >nul 2>&1
  if errorlevel 1 (
    echo Rojo introuvable. Installe-le ou ajoute-le au PATH.
    pause
    exit /b 1
  )
  set "ROJO=rojo"
)

rem Libere le port si un ancien Rojo (plante ou oublie) le garde encore
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%PORT% .*LISTENING"') do (
  echo Port %PORT% deja utilise par le PID %%p, arret...
  taskkill /PID %%p /F >nul 2>&1
)

rem Installe / met a jour le plugin Studio "UsineTools" (bouton Factory Preview) dans le dossier
rem Plugins local de Studio. Doc : docs/systems/apercu-edit.md
"%ROJO%" build tools\studio-plugin\plugin.project.json --plugin UsineTools.rbxm
if errorlevel 1 echo Plugin UsineTools pas installe (erreur au-dessus). Rojo demarre quand meme.

echo Studio : plugin Rojo ^> Connect ^> localhost:%PORT%
echo Arreter : fermer cette fenetre ou lancer stop-rojo.bat

rem Boucle : si Rojo plante ou se ferme, il est relance tout seul
:loop
echo.
echo [%date% %time%] Demarrage de Rojo "Mon usine de boissons" sur le port %PORT%...
"%ROJO%" serve default.project.json --port %PORT%
echo.
echo [%date% %time%] Rojo s'est arrete (code %errorlevel%). Relance dans 3 secondes...
echo Ferme cette fenetre pour arreter definitivement.
timeout /t 3 /nobreak >nul
goto loop
