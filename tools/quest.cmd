@echo off
rem Quest 3 one-click entry. Usage: tools\quest.cmd all ^| build ^| install ^| run ^| logdump ^| shot ^| key ENTER ^| mirror ^| wake
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0quest.ps1" %*
