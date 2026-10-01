@echo off
rem lars13 stop (Windows port of server/scripts/jarvis-stop.sh): kill uvicorn listeners
setlocal
set PORTS=443 8765 8766 9443
echo Stopping lars13 (ports: %PORTS%)...
for %%p in (%PORTS%) do (
  for /f "tokens=5" %%i in ('netstat -ano ^| findstr /r ":%%p .*LISTENING"') do (
    if not "%%i"=="0" taskkill /PID %%i /F >nul 2>&1
  )
)
echo Done.
