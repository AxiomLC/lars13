@echo off
rem lars13 health check (Windows port of server/scripts/jarvis-health.sh)
setlocal
set OK=1
for %%p in (443 8765 8766 9443) do (
  netstat -ano | findstr /r ":%%p .*LISTENING" >nul 2>&1
  if errorlevel 1 (echo [MISS] port %%p not listening & set OK=0) else echo [ OK ] port %%p listening
)
curl -sk https://127.0.0.1:443/api/health >nul 2>&1
if errorlevel 1 (echo [MISS] https API health no response & set OK=0) else echo [ OK ] API health responds
if "%OK%"=="1" (echo HEALTH: ALL GOOD) else (echo HEALTH: PROBLEMS FOUND & exit /b 1)
