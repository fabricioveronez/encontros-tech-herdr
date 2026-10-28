## ADDED Requirements

### Requirement: Ambiente Compose com aplicação e dependências
O repositório SHALL ter um `docker-compose.yml` na raiz que define o serviço `app`, construído a partir de `./src` com o `src/Dockerfile`, e o serviço `db`, com a imagem oficial do PostgreSQL e tag de versão explícita. O serviço `app` MUST receber `DATABASE_URL` apontando para o serviço `db` e MUST publicar a porta da aplicação no host.

#### Scenario: Subida completa do ambiente
- **WHEN** `docker compose up --build -d` é executado na raiz do repositório
- **THEN** os serviços `app` e `db` ficam em execução e a aplicação responde em `http://localhost:8000`

### Requirement: Ordem de inicialização baseada em healthcheck
O serviço `db` MUST ter um healthcheck (`pg_isready`), e o serviço `app` MUST depender dele com `condition: service_healthy`, para que a aplicação só inicie com o banco pronto para conexões.

#### Scenario: App inicia depois do banco saudável
- **WHEN** o ambiente é iniciado do zero
- **THEN** o serviço `db` fica `healthy` antes de o serviço `app` iniciar, e os logs do `app` não têm erro de conexão com o banco, traceback nem `Worker failed to boot`

#### Scenario: Inicialização estável em ciclos repetidos
- **WHEN** o ciclo `docker compose down` seguido de `docker compose up -d` é executado 3 vezes seguidas
- **THEN** em todas as execuções o `app` fica em execução e responde em `GET /`, sem falha de boot de worker

### Requirement: Ambiente sem volumes e efêmero
O `docker-compose.yml` MUST NOT declarar volumes nem bind mounts em nenhum serviço, nem para dados do banco nem para código. O estado do banco SHALL ser descartado quando o ambiente é removido.

#### Scenario: Nenhum volume declarado
- **WHEN** `docker compose config` é executado
- **THEN** a configuração resolvida não contém nenhuma chave `volumes` em nenhum serviço nem no nível superior

#### Scenario: Banco descartado ao remover o ambiente
- **WHEN** um evento é criado, o ambiente é removido com `docker compose down` e depois iniciado de novo com `docker compose up -d`
- **THEN** `GET /api/events/` retorna uma lista vazia

#### Scenario: Mudança de código exige rebuild
- **WHEN** um arquivo em `src/` é alterado e o ambiente é reconstruído com `docker compose up --build -d`
- **THEN** a alteração aparece na aplicação em execução; sem rebuild, a aplicação continua com o código anterior

### Requirement: Execução sem arquivo .env
O ambiente Compose MUST funcionar sem arquivo `.env` na raiz, com valores padrão para todas as variáveis necessárias (credenciais do PostgreSQL, `DATABASE_URL` e porta), e SHALL permitir sobrescrevê-los por variáveis de ambiente.

#### Scenario: Subida em clone limpo
- **WHEN** `docker compose up --build -d` é executado em um clone sem arquivo `.env`
- **THEN** o ambiente sobe e a aplicação responde normalmente

### Requirement: Aplicação funcional no ambiente Compose
Com o ambiente Compose em execução, a aplicação SHALL atender corretamente às páginas, aos arquivos estáticos, à API de eventos e ao endpoint de métricas, persistindo dados no PostgreSQL do serviço `db`.

#### Scenario: Página inicial renderizada
- **WHEN** `GET /` é requisitado
- **THEN** a resposta tem status 200 e conteúdo HTML

#### Scenario: Arquivo estático servido
- **WHEN** `GET /static/css/style.css` é requisitado
- **THEN** a resposta tem status 200

#### Scenario: Criação de evento via API
- **WHEN** `POST /api/events/` é requisitado com um payload JSON válido (`title`, `description`, `date`, `location`, `technologies`)
- **THEN** a resposta tem status 200 e retorna o evento com `id` e `edit_token`

#### Scenario: Listagem de eventos via API
- **WHEN** `GET /api/events/` é requisitado depois da criação de um evento
- **THEN** a resposta tem status 200 e a lista contém o evento criado

#### Scenario: Página de detalhe do evento
- **WHEN** `GET /events/<id>` é requisitado com o `id` do evento criado
- **THEN** a resposta tem status 200

#### Scenario: Consulta por token de edição
- **WHEN** `GET /api/events/by-token/<edit_token>` é requisitado com o token do evento criado
- **THEN** a resposta tem status 200 e retorna o evento

#### Scenario: Atualização por token de edição
- **WHEN** `PUT /api/events/by-token/<edit_token>` é requisitado com um payload válido que altera o `title`
- **THEN** a resposta tem status 200 e uma consulta posterior retorna o `title` alterado

#### Scenario: Token inexistente
- **WHEN** `GET /api/events/by-token/token-inexistente` é requisitado
- **THEN** a resposta tem status 404

#### Scenario: Métricas expostas
- **WHEN** `GET /metrics` é requisitado
- **THEN** a resposta tem status 200 e conteúdo no formato de exposição do Prometheus
