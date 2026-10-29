## Context

A Encontros Tech é uma aplicação Flask servida por Gunicorn que persiste eventos em PostgreSQL via SQLAlchemy. O código fica em `src/` (`main.py` é o módulo de entrada, `main:app`), as dependências estão em `src/requirements.txt` e a configuração é lida de variáveis de ambiente em `src/core/settings.py`, que também carrega um `.env` opcional com `load_dotenv()`.

Já existiu uma containerização, removida no commit `0f5bbad`. Ela usava `FROM python` sem tag, rodava como root, fixava a porta no `CMD` (`-b 0.0.0.0:8000`) e persistia o banco em `./.postgres-data`.

Restrições acordadas:
- Só três arquivos novos: `src/Dockerfile`, `src/.dockerignore` e `docker-compose.yml`.
- Nenhuma alteração em código Python, `requirements.txt` ou outros arquivos existentes.
- Nenhum volume no Compose, nem para o banco nem para o código.
- A validação é manual, feita com build e execução via Compose e testes HTTP na aplicação. Sem script de validação, sem testes unitários e sem linter de Dockerfile.

## Goals / Non-Goals

**Goals:**
- Imagem única e portável, que roda em qualquer orquestrador recebendo a configuração só por variáveis de ambiente.
- Ambiente local completo com `docker compose up --build`, sem pré-requisitos além do Docker.
- Ambiente efêmero e reprodutível, sem estado preso ao host.
- Aceite comprovado por um plano de validação executado localmente.

**Non-Goals:**
- Manifests de Kubernetes, task definitions de ECS ou charts. A portabilidade é garantida pelo contrato da imagem, não por artefatos de cada plataforma.
- Hot reload ou montagem de código no Compose.
- Corrigir limitações do código da aplicação (ver Riscos).
- Migrações de banco (Alembic) e persistência de dados.
- Rodar testes unitários dentro do container.

## Decisions

### D1. Imagem base `python:3.12-slim` com tag fixa
A variante slim reduz bastante o tamanho em relação à imagem completa, e todas as dependências do `requirements.txt` (incluindo `psycopg2-binary` e `pydantic_core`) têm wheels prontos para 3.12. Com isso, não é preciso compilador nem `libpq-dev`.
- *Alternativa:* `python:3.12-alpine`. Descartada porque usa musl, o que pode exigir compilar wheels, e porque tem diferenças de comportamento em relação à glibc.
- *Alternativa:* multi-stage com builder. Descartada por enquanto: como não há compilação, um estágio único com `pip install --no-cache-dir` produz uma imagem equivalente com menos complexidade.

### D2. Ordem de camadas para aproveitar o cache
Copiar primeiro só `requirements.txt` e instalar as dependências; depois copiar o restante do código. Assim, uma mudança em código Python não invalida a camada de dependências, o que importa porque o fluxo de desenvolvimento exige rebuild a cada mudança.

### D3. Usuário não-root dedicado
Criar um usuário e grupo de sistema sem privilégios (por exemplo `app`, UID fixo) e usar `USER` antes do `CMD`. Os arquivos da aplicação ficam com dono root e somente leitura para o usuário da aplicação. O único diretório gravável necessário é o de métricas do Prometheus (D6), criado com permissão para esse usuário.

### D4. Gunicorn com configuração nativa por ambiente
`CMD ["gunicorn", "main:app"]` na forma exec, sem `-b` nem `-w` fixos:
- O Gunicorn faz bind em `0.0.0.0:$PORT` quando `PORT` está definida e não há `bind` explícito.
- O Gunicorn usa `WEB_CONCURRENCY` como número padrão de workers.
- Para outros parâmetros (timeout, log de acesso), o operador pode usar `GUNICORN_CMD_ARGS`, sem alterar a imagem.

O `ENV` da imagem define `PORT=8000`, `WEB_CONCURRENCY=2`, `LOG_FORMAT=simple`, `PYTHONUNBUFFERED=1` e `PYTHONDONTWRITEBYTECODE=1`. `EXPOSE 8000` funciona como documentação.
- *Alternativa:* entrypoint em shell que monta os argumentos. Descartada porque acrescenta um arquivo e um processo intermediário que atrapalharia o repasse do `SIGTERM`.
- A validação da corrida no `create_all` (R2) falhou com `2` workers, e o padrão de `WEB_CONCURRENCY` no Compose passou a ser `1`.

### D5. `.dockerignore` restritivo em `src/`
O contexto de build é `./src`, então o `.dockerignore` fica em `src/` e exclui: `.env*` (exceto `.env.example`, que é inofensivo), `tests/`, `__pycache__/`, `*.py[cod]`, `.pytest_cache/`, ambientes virtuais, `.git/`, arquivos de IDE e de SO, logs, `Dockerfile` e `.dockerignore`. Isso evita que o `load_dotenv()` encontre um `.env` de desenvolvimento dentro da imagem.

### D6. Diretório de métricas Prometheus
`PROMETHEUS_MULTIPROC_DIR` é definido no `ENV` da imagem, apontando para um diretório gravável pelo usuário não-root (por exemplo `/tmp/prometheus_multiproc`). A aplicação já cria o diretório se ele não existir, mas defini-lo no ambiente do processo é o que permite ao `prometheus_client` reconhecer o modo multiprocess. Se a agregação entre workers funciona com o `PrometheusMetrics` atual, sem alterar código, é algo a observar (R3). A validação exige apenas que `/metrics` responda.

### D7. Compose: `app` + `db`, sem volumes, com padrões embutidos
- `db`: `postgres:16-alpine`, credenciais por variáveis com padrão (`${POSTGRES_USER:-encontros_tech}` etc.), healthcheck com `pg_isready -U ... -d ...`, intervalo curto e algumas tentativas. Sem `volumes`, então os dados vivem só na camada gravável do container.
- `app`: `build: { context: ./src, dockerfile: Dockerfile }`, `depends_on: { db: { condition: service_healthy } }`, `DATABASE_URL` montada a partir das mesmas variáveis apontando para o host `db`, e `ports: "${PORT:-8000}:8000"`.
- Sem `env_file` obrigatório: o ambiente sobe em um clone limpo. Um `.env` na raiz continua funcionando, porque o Compose o lê automaticamente para a interpolação.
- A porta 5432 do banco não é publicada no host. Para inspecionar o banco, usar `docker compose exec db psql`. Isso evita conflito com um Postgres local.
- Sem `container_name` fixo, para permitir várias cópias do projeto em paralelo (por exemplo, em worktrees).
- *Alternativa:* `develop.watch` com `action: rebuild` para reconstruir automaticamente. Fica como possibilidade futura; não é requisito.

### D8. Validação manual por Compose como critério de aceite
O aceite é o checklist da seção de validação do `tasks.md`, que cobre build, subida, inspeção do container, testes HTTP (com `curl`, seguindo os payloads de `api-requests.http`) e ciclo de vida. Todos os itens precisam passar. A portabilidade fora do Compose (K8s/ECS) não é testada diretamente: ela decorre do contrato da imagem (D1–D6).

## Risks / Trade-offs

- **R1. `SECRET_KEY` fixo no `main.py`** → A imagem não consegue sobrescrevê-lo, e todas as instâncias compartilham a mesma chave. Aceito nesta change; a correção exige alterar código e fica para uma change futura.
- **R2. `create_all` no import do módulo, em cada worker** → Com o banco vazio e vários workers, há uma janela de disputa no `CREATE TABLE` que pode derrubar um worker no boot. Mitigação: o `depends_on: service_healthy` garante que o banco esteja pronto, e a validação repete `down`/`up` 3 vezes. Se houver falha, `WEB_CONCURRENCY` passa a `1` no Compose e isso fica registrado aqui. `--preload` foi descartado porque compartilharia o pool de conexões do SQLAlchemy entre processos forkados.
  - **Resultado da validação (2026-10-29):** a disputa ocorreu já na primeira subida com `WEB_CONCURRENCY=2`. Os dois workers executaram `CREATE TABLE events` ao mesmo tempo, um falhou com `UniqueViolation` em `pg_class_relname_nsp_index` (`events_id_seq`) e o Gunicorn encerrou com `Worker failed to boot`. O Compose passou a definir `WEB_CONCURRENCY: ${WEB_CONCURRENCY:-1}`. A imagem mantém o padrão `2`, então qualquer orquestrador que suba vários workers com o banco vazio está sujeito à mesma falha até o `create_all` sair do import (exige alteração de código).
- **R3. Métricas com vários workers** → O `PrometheusMetrics` padrão pode expor só os números do worker que atendeu a requisição. `/metrics` funciona, mas os valores podem ficar parciais. Aceito; a correção (`GunicornPrometheusMetrics` ou equivalente) exige alterar código.
- **R4. Sem endpoint de health dedicado** → Os orquestradores devem usar `/metrics` como liveness (não acessa o banco) e `GET /api/events/?limit=1` como readiness (acessa o banco). Funciona, mas gera log de negócio a cada probe.
- **R5. `pytest` no `requirements.txt`** → Vai para a imagem final, que fica um pouco maior. Aceito porque o arquivo não pode ser alterado.
- **R6. Banco não disponível no boot fora do Compose** → Sem o `depends_on`, o `create_all` falha no import, o worker não sobe e o Gunicorn encerra. Em K8s e ECS, o reinício automático resolve, o que é aceitável.
- **R7. Rebuild a cada mudança** → Mais lento que hot reload, mas é uma escolha explícita: o Compose roda a mesma imagem que vai para os orquestradores. O cache de camadas (D2) reduz o custo.
- **R8. Endpoints JSON da API retornam 500** → `src/routers/api_router.py` chama `.model_dump()` sobre os objetos SQLAlchemy devolvidos por `event_service`, e eles não têm esse método. Criar, listar (com eventos) e consultar/atualizar por token respondem 500, embora a gravação no banco aconteça. O bug existe desde o commit inicial e não tem relação com a containerização. Os itens 5.3, 5.4, 5.6 e 5.7 da validação ficaram não testáveis. A 6.2 foi validada pelo registro gravado no banco. A correção fica para uma change de código.

## Migration Plan

Não há deploy em produção nesta change. Para usar: `docker compose up --build -d` na raiz; para remover: `docker compose down`. O rollback é apagar os três arquivos; nada no código da aplicação depende deles.

## Open Questions

- ~~A disputa no `create_all` (R2) aparece na prática com `WEB_CONCURRENCY=2`?~~ Sim. Ver R2.
