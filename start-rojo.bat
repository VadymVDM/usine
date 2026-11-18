@echo off
setlocal
cd /d "%~dp0"
set "PORT=34850"

set "ROJO=%LOCALAPPDATA%\Rojo\rojo.exe"
if not exist "%ROJO%" (
  where rojo >nul 2>&1
  if errorlevel 1 (
    echo Rojo introuvable. Installe-le ou ajoute-le au PATH.
    pause
    exit /b 1
  )
  set "ROJO=rojo"
)

netstat -ano | findstr ":%PORT% .*LISTENING" >nul
if not errorlevel 1 (
  echo Le port %PORT% est deja utilise. Lance stop-rojo.bat ou ferme l'autre serveur.
  pause
  exit /b 1
)

echo Demarrage de Rojo "Mon usine de boissons" sur le port %PORT%...
start "Rojo Usine :%PORT%" "%ROJO%" serve default.project.json --port %PORT%

echo.
echo OK - fenetre Rojo ouverte.
echo   Studio : plugin Rojo ^> Connect ^> localhost:%PORT%
echo   Arreter : fermer la fenetre ou lancer stop-rojo.bat
endlocal
