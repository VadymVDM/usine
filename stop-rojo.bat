@echo off
set "PORT=34850"
echo Arret de Rojo "Mon usine de boissons" (port %PORT%)...
taskkill /FI "WINDOWTITLE eq Rojo Usine :%PORT%*" /T /F >nul 2>&1
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%PORT% .*LISTENING"') do taskkill /PID %%p /F >nul 2>&1
echo Termine.
