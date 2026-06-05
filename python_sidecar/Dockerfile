FROM python:3.11-slim

WORKDIR /app

# System deps for OpenCV and ONNX
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-glx libglib2.0-0 libsm6 libxrender1 libxext6 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .
COPY anpr/ anpr/
COPY static/ static/
COPY scripts/ scripts/

# Copy models (mounted or baked in)
COPY models/anpr/ models/anpr/
COPY models/face/ models/face/
COPY models/parseq/ models/parseq/

ENV SIDECAR_PORT=8765
ENV SIDECAR_HOST=0.0.0.0

EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8765/health')" || exit 1

CMD ["python", "main.py"]
