@echo off
    cd /d "%~dp0"
    start "AI Chat Proxy" /B node .\api_proxy.js
    rem
    timeout /t 2 /nobreak >nul
    cd ..
    cd ..
    start "" wxstart.exe