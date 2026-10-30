@echo off
rem Suite de tests MIMIC HUNTERS : test.cmd [-SkipStudio] [-Sessions server,client,mobile,multiplayer] [-Visible]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\test-all.ps1" %*
exit /b %ERRORLEVEL%
