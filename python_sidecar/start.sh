#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="$SCRIPT_DIR/.venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

if [ ! -f "$VENV_DIR/.deps_installed" ]; then
    echo "Installing dependencies..."
    pip install --upgrade pip
    pip install -r requirements.txt
    touch "$VENV_DIR/.deps_installed"
fi

export SIDECAR_PORT="${SIDECAR_PORT:-8765}"
export SIDECAR_HOST="${SIDECAR_HOST:-0.0.0.0}"

# Prevent SIGSEGV from dual libomp (FAISS vs PyTorch) on macOS ARM64
export KMP_DUPLICATE_LIB_OK=TRUE
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

echo "Starting Weighbridge AI Sidecar on $SIDECAR_HOST:$SIDECAR_PORT"
python main.py
