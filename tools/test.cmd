@echo off
rem Run the whole automated suite headlessly. Exit code 0 = every check passed.
rem Its own save slot, so it never touches real progress.
setlocal
set GODOT=D:\Program Files\Portables\Godot_v4.7.2-stable_win64_console.exe
"%GODOT%" --headless --xr-mode off --path "%~dp0.." res://tests/smoke_test.tscn -- --slot=smoke_test
exit /b %ERRORLEVEL%
