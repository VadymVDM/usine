@echo off
set "PORT=34850"
echo Arret de Rojo "Mon usine de boissons" (port %PORT%)...
rem 1) Tue la boucle de start-rojo.bat (et son Rojo) en la cherchant par sa ligne de commande.
rem    Le filtre par titre de fenetre ne marche pas avec le Terminal Windows de Windows 11.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'cmd.exe' -and $_.CommandLine -like '*%~dp0start-rojo.bat*' } | ForEach-Object { taskkill /PID $_.ProcessId /T /F }" >nul 2>&1
rem 2) Ancienne methode par titre (console classique), au cas ou
taskkill /FI "WINDOWTITLE eq Rojo Usine :%PORT%*" /T /F >nul 2>&1
rem 3) Libere le port si un Rojo lance a la main le garde encore
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%PORT% .*LISTENING"') do taskkill /PID %%p /F >nul 2>&1
echo Termine.
