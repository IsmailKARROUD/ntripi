# ─────────── Stage 1: Flutter web build ───────────
FROM ghcr.io/cirruslabs/flutter:stable AS flutter_builder

WORKDIR /flutter_app

COPY social_flutter/ ./

RUN flutter pub get

RUN flutter build web \
    --release \
    --base-href=/app/ \
    --dart-define=API_BASE_URL=https://ntripi.app \
    --dart-define=SHARE_BASE_URL=https://ntripi.app \
    --dart-define=GOOGLE_MAPS_EMBED_API_KEY=AIzaSyD8gF4G_w7voK0YPHA_Y234sgXInsrU__8

# ─────────── Stage 2: Python runtime ───────────
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY social_api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY social_api/ .

COPY --from=flutter_builder /flutter_app/build/web /app/web_build

# Non-root user — the API process has no reason to run as UID 0
RUN adduser --disabled-password --gecos '' appuser \
    && chown -R appuser:appuser /app
USER appuser

ENV PORT=8000
EXPOSE 8000

# Use Python's stdlib for the health probe — curl is not guaranteed in python:3.11-slim
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT:-8000}/health')"

CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
