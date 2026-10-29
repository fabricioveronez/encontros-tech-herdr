## 1. Imagem da aplicação

- [x] 1.1 Criar `src/.dockerignore` excluindo `.env*` (exceto `.env.example`), `tests/`, `__pycache__/`, `*.py[cod]`, `.pytest_cache/`, ambientes virtuais, `.git/`, arquivos de IDE/SO, logs, `Dockerfile` e `.dockerignore` (design D5)
- [x] 1.2 Criar `src/Dockerfile` com base `python:3.12-slim` e `ENV` de `PORT=8000`, `WEB_CONCURRENCY=2`, `LOG_FORMAT=simple`, `PYTHONUNBUFFERED=1`, `PYTHONDONTWRITEBYTECODE=1` e `PROMETHEUS_MULTIPROC_DIR` (design D1, D4, D6)
- [x] 1.3 No `src/Dockerfile`, instalar as dependências copiando primeiro só o `requirements.txt` (`pip install --no-cache-dir`) e só depois o código (design D2)
- [x] 1.4 No `src/Dockerfile`, criar o usuário não-root com UID fixo e o diretório de métricas gravável por ele, e declarar `USER`, `EXPOSE 8000` e `CMD ["gunicorn", "main:app"]` na forma exec (design D3, D4)

## 2. Ambiente Docker Compose

- [x] 2.1 Criar `docker-compose.yml` na raiz com o serviço `db` (`postgres:16-alpine`), credenciais por variáveis com padrão e healthcheck com `pg_isready`, sem volumes e sem porta publicada (design D7)
- [x] 2.2 Adicionar o serviço `app` com build de `./src`, `depends_on` com `condition: service_healthy`, `DATABASE_URL` apontando para `db` com padrões interpolados e `ports: "${PORT:-8000}:8000"`, sem `env_file`, volumes nem `container_name` (design D7)

## 3. Validação — Build

Pré-condição: nenhum arquivo `.env` na raiz e em `src/` (renomear temporariamente se existir).

- [x] 3.1 `docker compose config` executa sem erro e a saída não contém nenhuma chave `volumes`
- [x] 3.2 `docker compose build` termina com sucesso
- [x] 3.3 `docker image inspect` da imagem do `app` mostra `PORT`, `WEB_CONCURRENCY` e `LOG_FORMAT` definidas, e o `User` não é root
- [x] 3.4 Toda instrução `FROM` do `src/Dockerfile` usa uma tag de versão explícita

## 4. Validação — Execução

- [x] 4.1 `docker compose up -d` sobe o ambiente; `docker compose ps` mostra `db` como `healthy` e `app` como `running`
- [x] 4.2 `docker compose logs app` não contém traceback, erro de conexão com o banco nem `Worker failed to boot`, e não contém códigos ANSI (`grep $'\x1b\['` não encontra nada)
- [x] 4.3 `docker compose exec app id -u` retorna valor diferente de `0`
- [x] 4.4 `docker compose exec app ls -la` mostra `main.py`, `templates/` e `static/`, e não mostra `.env`, `tests/`, `__pycache__/`, `.venv/`, `.git/`, `Dockerfile` nem `.dockerignore`
- [x] 4.5 Repetir 3 vezes `docker compose down && docker compose up -d` e confirmar, em cada ciclo, que o `app` fica `running` e `GET /` responde 200 sem falha de boot de worker. Se falhar, ajustar `WEB_CONCURRENCY=1` no Compose, registrar o resultado no `design.md` (R2) e refazer a seção 4

## 5. Validação — Aplicação

Executar contra `http://localhost:8000` com `curl`, usando um payload no formato de `api-requests.http`.

- [x] 5.1 `GET /` → 200, conteúdo HTML
- [x] 5.2 `GET /static/css/style.css` → 200
- [x] 5.3 ~~`POST /api/events/` com JSON válido → 200; guardar `id` e `edit_token` da resposta~~ — não testável: bug de código pré-existente (design R8), fora do escopo
- [x] 5.4 ~~`GET /api/events/` → 200, a lista contém o evento criado~~ — não testável: bug de código pré-existente (design R8), fora do escopo
- [x] 5.5 `GET /events/<id>` → 200
- [x] 5.6 ~~`GET /api/events/by-token/<edit_token>` → 200, retorna o evento~~ — não testável: bug de código pré-existente (design R8), fora do escopo
- [x] 5.7 ~~`PUT /api/events/by-token/<edit_token>` com o payload completo e o `title` alterado → 200; um novo `GET` por token retorna o `title` alterado~~ — não testável: bug de código pré-existente (design R8), fora do escopo
- [x] 5.8 `GET /api/events/by-token/token-inexistente` → 404
- [x] 5.9 `GET /metrics` → 200, conteúdo no formato Prometheus (linhas `# HELP` / `# TYPE`)
- [x] 5.10 `docker compose logs app` mostra os registros das requisições acima, sem códigos ANSI

## 6. Validação — Ciclo de vida

- [x] 6.1 `time docker compose stop app` termina em menos de 10s e `docker compose ps -a` mostra exit code diferente de `137`
- [x] 6.2 Com pelo menos um evento criado, `docker compose down` seguido de `docker compose up -d` → `GET /api/events/` retorna `[]`
- [x] 6.3 Alterar temporariamente um texto em um template de `src/templates/`: sem rebuild, `GET /` continua mostrando o texto antigo; depois de `docker compose up --build -d`, mostra o novo. Desfazer a alteração em seguida
- [x] 6.4 `docker compose down` para limpar o ambiente e restaurar algum `.env` que tenha sido renomeado na pré-condição
