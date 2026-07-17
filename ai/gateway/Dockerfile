# AI Gateway — least-privilege container (FR-022).
# Build context: ai/ (parent of gateway/). Writable scope at runtime: config + log dir only.
FROM python:3.12-slim-bookworm

RUN groupadd --gid 1000 gateway \
    && useradd --uid 1000 --gid gateway --shell /usr/sbin/nologin --no-create-home gateway

WORKDIR /app

COPY gateway/pyproject.toml ./
COPY gateway/src/ ./src/

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir .

COPY dashboard/ /app/dashboard/
COPY gateway/config/gateway.example.yaml /app/config/gateway.example.yaml

# FR-022: filesystem write scope — logs + config mount only; app code and dashboard are read-only.
RUN mkdir -p /var/log/gateway /app/config \
    && chown -R gateway:gateway /var/log/gateway /app/config /app/dashboard /app \
    && chmod -R a-w /app/src /app/dashboard

USER gateway

ENV GATEWAY_PORT=8090
ENV GATEWAY_LOG_DIR=/var/log/gateway
ENV GATEWAY_CONFIG_PATH=/app/config/gateway.yaml
ENV GATEWAY_DASHBOARD_DIR=/app/dashboard

EXPOSE 8090

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/health')"

CMD ["uvicorn", "gateway.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8090"]
