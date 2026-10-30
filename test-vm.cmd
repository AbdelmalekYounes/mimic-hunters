@echo off
rem Tests Studio visibles dans la VM de test : test-vm.cmd [-Vmx chemin.vmx] [-Sessions ...] [-KeepRunning]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\vm-tests.ps1" %*
exit /b %ERRORLEVEL%
