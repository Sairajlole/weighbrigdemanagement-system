@echo off
cd /d "%~dp0"

REM ─── Find or install Python ───────────────────────────────────────────────
set PYTHON_CMD=
where py >nul 2>nul && set PYTHON_CMD=py
if not defined PYTHON_CMD (
    where python >nul 2>nul && set PYTHON_CMD=python
)
if not defined PYTHON_CMD (
    where python3 >nul 2>nul && set PYTHON_CMD=python3
)

REM If no system Python, use embedded Python (auto-downloaded)
if not defined PYTHON_CMD (
    if exist ".python\python.exe" (
        set PYTHON_CMD=.python\python.exe
    ) else (
        echo Python not found. Downloading embedded Python 3.11...
        mkdir .python 2>nul
        powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip' -OutFile '.python\python.zip'"
        if errorlevel 1 (
            echo ERROR: Failed to download Python. Check internet connection.
            pause
            exit /b 1
        )
        powershell -NoProfile -Command "Expand-Archive -Path '.python\python.zip' -DestinationPath '.python' -Force"
        del .python\python.zip 2>nul
        REM Enable pip in embedded Python (uncomment import site in ._pth file)
        powershell -NoProfile -Command "(Get-Content '.python\python311._pth') -replace '#import site','import site' | Set-Content '.python\python311._pth'"
        REM Install pip
        powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile '.python\get-pip.py'"
        .python\python.exe .python\get-pip.py --quiet
        del .python\get-pip.py 2>nul
        echo Python 3.11 installed locally.
        set PYTHON_CMD=.python\python.exe
    )
)

REM ─── Create venv ──────────────────────────────────────────────────────────
if not exist ".venv" (
    echo Creating virtual environment...
    %PYTHON_CMD% -m venv .venv
    if errorlevel 1 (
        REM Embedded Python doesn't support venv — use it directly
        echo Using embedded Python directly...
        set USE_EMBEDDED=1
    )
)

if defined USE_EMBEDDED (
    set PIP_CMD=.python\python.exe -m pip
    set RUN_CMD=.python\python.exe
) else (
    call .venv\Scripts\activate.bat
    set PIP_CMD=pip
    set RUN_CMD=python
)

REM ─── Install dependencies ─────────────────────────────────────────────────
if not exist ".venv\.deps_installed" (
    if not defined USE_EMBEDDED (
        echo Installing dependencies...
        %PIP_CMD% install --upgrade pip --quiet
        %PIP_CMD% install -r requirements.txt
        echo. > .venv\.deps_installed
    ) else (
        if not exist ".python\.deps_installed" (
            echo Installing dependencies...
            %PIP_CMD% install --upgrade pip --quiet
            %PIP_CMD% install -r requirements.txt
            echo. > .python\.deps_installed
        )
    )
)

REM ─── Intel GPU acceleration (one-time) ────────────────────────────────────
set DEPS_FLAG=.venv\.openvino_checked
if defined USE_EMBEDDED set DEPS_FLAG=.python\.openvino_checked
if not exist "%DEPS_FLAG%" (
    echo Checking Intel GPU support...
    %PIP_CMD% install onnxruntime-openvino openvino --quiet 2>nul
    echo. > "%DEPS_FLAG%"
)

REM ─── Start sidecar ────────────────────────────────────────────────────────
set SIDECAR_PORT=8765
set SIDECAR_HOST=0.0.0.0

echo Starting Weighbridge AI Sidecar on %SIDECAR_HOST%:%SIDECAR_PORT%
%RUN_CMD% main.py
