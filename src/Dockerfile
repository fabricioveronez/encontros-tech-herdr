FROM python:3.12-slim

# Configuração padrão; toda ela pode ser sobrescrita em tempo de execução.
# O Gunicorn faz bind em 0.0.0.0:$PORT e usa $WEB_CONCURRENCY como número de workers.
ENV PORT=8000 \
    WEB_CONCURRENCY=2 \
    LOG_FORMAT=simple \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc

WORKDIR /app

# Dependências primeiro, para aproveitar o cache de camadas
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Usuário sem privilégios; o código fica com dono root e somente leitura para ele
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app \
    && mkdir -p "$PROMETHEUS_MULTIPROC_DIR" \
    && chown app:app "$PROMETHEUS_MULTIPROC_DIR"

USER app

EXPOSE 8000

CMD ["gunicorn", "main:app"]
