## Why

A aplicação Encontros Tech (Flask + Gunicorn + PostgreSQL) não tem hoje nenhuma forma de execução containerizada. O setup anterior foi removido (commit `0f5bbad`) e tinha problemas: imagem base sem versão fixa, execução como root, porta fixa no comando e banco persistido em volume do host. Precisamos de uma imagem portável, que rode em qualquer orquestrador (Docker Compose, Kubernetes, ECS etc.), e de um ambiente local de desenvolvimento autocontido em Docker Compose.

## What Changes

- Novo `src/Dockerfile` que gera uma imagem OCI portável: base com versão fixa, usuário não-root, configuração exclusivamente por variáveis de ambiente (`PORT`, `WEB_CONCURRENCY`, `LOG_FORMAT`, `DATABASE_URL` etc.), Gunicorn como processo principal em forma exec e logs no stdout.
- Novo `src/.dockerignore` que impede a entrada na imagem de `.env`, testes, caches, ambientes virtuais e metadados de VCS/IDE.
- Novo `docker-compose.yml` na raiz com o serviço `app` (build de `./src`) e o serviço `db` (PostgreSQL com healthcheck). Não usa nenhum volume: nem para o banco, que é efêmero, nem para o código, que roda a partir da imagem construída.
- Plano de validação manual como critério de aceite: build e execução via Compose e testes funcionais da aplicação em execução.
- **Sem alteração** no código Python, no `requirements.txt` ou em outros arquivos existentes do projeto.

## Capabilities

### New Capabilities
- `container-image`: contrato da imagem da aplicação. Define como ela é configurada, executada, encerrada e o que ela pode e não pode conter, de forma independente do orquestrador.
- `local-compose-environment`: ambiente local de desenvolvimento via Docker Compose com a aplicação e suas dependências (PostgreSQL), efêmero e sem volumes, que precisa ser validado de ponta a ponta para a change ser aceita.

### Modified Capabilities
<!-- Nenhuma: não existem specs anteriores em openspec/specs/. -->

## Impact

- **Arquivos novos:** `src/Dockerfile`, `src/.dockerignore`, `docker-compose.yml`.
- **Código da aplicação:** nenhuma alteração. Limitações do código atual que afetam a execução em container (`SECRET_KEY` fixo, `create_all` no import, ausência de endpoint de health dedicado, métricas Prometheus com vários workers) ficam registradas como riscos aceitos no design.
- **Dependências externas:** imagem base oficial do Python (slim) e imagem oficial do PostgreSQL.
- **Fora do escopo:** manifests de Kubernetes e ECS, scripts de validação automatizada, testes unitários, migrações de banco e consolidação dos arquivos `.env.example`.
