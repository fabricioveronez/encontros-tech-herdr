## ADDED Requirements

### Requirement: Imagem base com versão fixa
A imagem da aplicação SHALL ser construída a partir de uma imagem base oficial do Python, variante slim, com tag de versão explícita. As tags `latest` e a ausência de tag MUST NOT ser usadas.

#### Scenario: Tag da imagem base explícita
- **WHEN** o `src/Dockerfile` é inspecionado
- **THEN** toda instrução `FROM` referencia uma imagem com tag de versão explícita (por exemplo `python:3.12-slim`), sem `latest` e sem tag omitida

#### Scenario: Build reproduzível a partir de clone limpo
- **WHEN** `docker compose build` é executado em um clone limpo do repositório, sem arquivo `.env`
- **THEN** o build da imagem da aplicação termina com sucesso

### Requirement: Execução como usuário não-root
O processo da aplicação no container MUST rodar com um usuário diferente de root.

#### Scenario: UID do processo diferente de zero
- **WHEN** `docker compose exec app id -u` é executado com a aplicação em execução
- **THEN** o valor retornado é diferente de `0`

### Requirement: Configuração exclusivamente por variáveis de ambiente
A imagem SHALL obter toda a sua configuração de variáveis de ambiente, sem depender de arquivos de configuração montados nem de nomes de serviço de um orquestrador específico. A imagem MUST definir valores padrão para `PORT` (8000), `WEB_CONCURRENCY` e `LOG_FORMAT` (`simple`). A conexão com o banco MUST vir somente de `DATABASE_URL`.

#### Scenario: Porta definida por variável de ambiente
- **WHEN** o container inicia com a variável `PORT` definida
- **THEN** o Gunicorn escuta em `0.0.0.0:$PORT`

#### Scenario: Valores padrão presentes na imagem
- **WHEN** a configuração da imagem é inspecionada (`docker image inspect`)
- **THEN** as variáveis `PORT`, `WEB_CONCURRENCY` e `LOG_FORMAT` estão definidas com valores padrão

#### Scenario: Banco configurado apenas por DATABASE_URL
- **WHEN** o `src/Dockerfile` é inspecionado
- **THEN** ele não contém hostname, usuário ou senha do banco; esses valores chegam apenas por `DATABASE_URL` em tempo de execução

### Requirement: Conteúdo da imagem restrito ao necessário
A imagem MUST conter o código da aplicação, os templates e os arquivos estáticos, e MUST NOT conter arquivos `.env`, o diretório `tests/`, caches Python (`__pycache__`, `*.pyc`), ambientes virtuais, metadados de VCS ou o próprio `Dockerfile`/`.dockerignore`. A exclusão SHALL ser feita via `src/.dockerignore`.

#### Scenario: Arquivos sensíveis e de desenvolvimento ausentes
- **WHEN** o diretório de trabalho da aplicação é listado dentro do container em execução
- **THEN** não existem `.env`, `tests/`, `__pycache__/`, `.venv/`, `.git/`, `Dockerfile` nem `.dockerignore`

#### Scenario: Templates e estáticos presentes
- **WHEN** o diretório de trabalho da aplicação é listado dentro do container em execução
- **THEN** existem `main.py`, `templates/` e `static/`

### Requirement: Logs no stdout sem formatação de terminal
A aplicação no container SHALL escrever logs no stdout, sem códigos de escape ANSI, para que qualquer agregador de logs consiga consumi-los.

#### Scenario: Logs legíveis pelo runtime de container
- **WHEN** a aplicação atende requisições e `docker compose logs app` é executado
- **THEN** os logs da aplicação e as requisições aparecem na saída, sem sequências de escape ANSI

### Requirement: Encerramento gracioso
O Gunicorn MUST ser o processo principal do container (forma exec do `CMD`/`ENTRYPOINT`) para receber o `SIGTERM` diretamente e encerrar sem precisar de `SIGKILL`.

#### Scenario: Stop sem SIGKILL
- **WHEN** `docker compose stop app` é executado com a aplicação em execução
- **THEN** o container encerra em menos de 10 segundos e o exit code é diferente de `137`
