FROM python:3.12-slim-bookworm

RUN groupadd --gid 1000 gateway \
    && useradd --uid 1000 --gid gateway --shell /bin/false --create-home gateway

WORKDIR /app

COPY pyproject.toml ./
COPY src/ ./src/

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir .

RUN mkdir -p /var/log/gateway /app/config \
    && chown -R gateway:gateway /app /var/log/gateway

USER gateway

ENV GATEWAY_PORT=8090
EXPOSE 8090

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/health')"

CMD ["uvicorn", "gateway.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8090"]
