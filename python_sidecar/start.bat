@echo off
cd /d "%~dp0"

if not exist ".venv" (
    echo Creating virtual environment...
    python -m venv .venv
)

call .venv\Scripts\activate.bat

if not exist ".venv\.deps_installed" (
    echo Installing dependencies...
    pip install --upgrade pip
    pip install -r requirements.txt
    echo. > .venv\.deps_installed
)

REM Auto-install Intel OpenVINO runtime for GPU inference (one-time, silent)
if not exist ".venv\.openvino_checked" (
    echo Checking Intel GPU support...
    python -c "import onnxruntime as ort; eps=ort.get_available_providers(); print('OpenVINO:', 'OpenVINOExecutionProvider' in eps)" 2>nul
    if errorlevel 1 (
        echo Installing OpenVINO runtime for Intel GPU acceleration...
        pip install onnxruntime-openvino --quiet 2>nul
    )
    REM Install Intel GPU compute runtime if not present
    python -c "import openvino" 2>nul
    if errorlevel 1 (
        pip install openvino --quiet 2>nul
    )
    echo. > .venv\.openvino_checked
)

set SIDECAR_PORT=8765
set SIDECAR_HOST=0.0.0.0

echo Starting Weighbridge AI Sidecar on %SIDECAR_HOST%:%SIDECAR_PORT%
python main.py
