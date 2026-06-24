# Stage 1: Build/Install stage
FROM python:3.14-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Final/Runtime stage
FROM python:3.14-slim

WORKDIR /app

# Run as non-root
RUN useradd --create-home --shell /bin/bash appuser
COPY --from=builder /root/.local /home/appuser/.local
COPY src/ /app/src/
COPY config/ /app/config/

ENV PATH=/home/appuser/.local/bin:$PATH
RUN chown -R appuser:appuser /app /home/appuser/.local
USER appuser

EXPOSE 8501

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8501/_stcore/health')" || exit 1

CMD ["streamlit", "run", "src/app.py", "--server.address=0.0.0.0", "--server.port=8501"]
