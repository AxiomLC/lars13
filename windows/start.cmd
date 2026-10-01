@echo off
rem lars13 voice pipeline start (Windows port of server/scripts/jarvis-start.sh)
setlocal
set ROOT=%~dp0..

rem Optional provider override test: set LARS13_TTS=<provider> before running (persist by editing server\config\server.yaml voice.provider)
if defined LARS13_TTS echo TTS provider override: %LARS13_TTS%

echo [lars13] starting voice pipeline (first run downloads Whisper small.en ~460MB, 60-90s warmup)...
cd /d "%ROOT%\server"
"%ROOT%\.venv\Scripts\python.exe" server.py %*
echo.
echo Voice pipeline exited.
pause
