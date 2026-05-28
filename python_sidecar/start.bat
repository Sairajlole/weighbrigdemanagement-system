@echo off
cd /d "%~dp0"

REM Find Python: try py launcher, then python, then python3
set PYTHON_CMD=
where py >nul 2>nul && set PYTHON_CMD=py
if not defined PYTHON_CMD (
    where python >nul 2>nul && set PYTHON_CMD=python
)
if not defined PYTHON_CMD (
    where python3 >nul 2>nul && set PYTHON_CMD=python3
)
if not defined PYTHON_CMD (
    echo ERROR: Python not found. Install Python 3.10+ from https://python.org
    echo Make sure to check "Add Python to PATH" during installation.
    pause
    exit /b 1
)

if not exist ".venv" (
    echo Creating virtual environment...
    %PYTHON_CMD% -m venv .venv
    if errorlevel 1 (
        echo ERROR: Failed to create virtual environment.
        pause
        exit /b 1
    )
)

call .venv\Scripts\activate.bat

if not exist ".venv\.deps_installed" (
    echo Installing dependencies...
    pip install --upgrade pip --quiet
    pip install -r requirements.txt
    echo. > .venv\.deps_installed
)

REM Auto-install Intel OpenVINO runtime for GPU inference (one-time, silent)
if not exist ".venv\.openvino_checked" (
    echo Checking Intel GPU support...
    pip install onnxruntime-openvino openvino --quiet 2>nul
    echo. > .venv\.openvino_checked
)

set SIDECAR_PORT=8765
set SIDECAR_HOST=0.0.0.0

echo Starting Weighbridge AI Sidecar on %SIDECAR_HOST%:%SIDECAR_PORT%
python main.py
