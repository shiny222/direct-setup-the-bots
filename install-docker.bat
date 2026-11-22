@echo off
setlocal
cd /d "%~dp0" || exit /b 1
set "profile="
if "%~1"=="1" set "profile=rubika"
if "%~1"=="2" set "profile=bale"
if "%~1"=="3" set "profile=both"
if "%~1"=="4" set "profile=all"
if not defined profile (
    echo Usage: install-docker.bat 1^|2^|3^|4
    exit /b 2
)
if not exist sources mkdir sources || exit /b 1
if not exist config mkdir config || exit /b 1
call :clone telegram-bot-api || exit /b 1
if not "%profile%"=="bale" (
    call :clone telegram-to-rubika || exit /b 1
)
if not "%profile%"=="rubika" (
    call :clone telegram-to-bale || exit /b 1
)
if "%profile%"=="all" (
    call :clone dashbord-bale-rubika || exit /b 1
)
if not exist .env copy .env.example .env >nul
if not "%profile%"=="bale" if not exist config\rubika.json (
    echo Create config/rubika.json from the Rubika repo's documented settings.
    exit /b 1
)
if not "%profile%"=="rubika" if not exist config\bale.json (
    echo Create config/bale.json from the Bale repo's documented settings.
    exit /b 1
)
docker compose --profile "%profile%" up -d --build --remove-orphans --wait
exit /b %errorlevel%

:clone
if exist "sources\%~1\" exit /b 0
git clone "https://github.com/shiny222/%~1.git" "sources\%~1"
exit /b %errorlevel%
