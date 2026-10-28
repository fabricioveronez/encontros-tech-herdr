## Context

A Encontros Tech é uma aplicação Flask servida por Gunicorn que persiste eventos em PostgreSQL. A change `containerize-application` define o contrato da imagem: configuração só por variáveis de ambiente (`PORT`, padrão 8000; `WEB_CONCURRENCY`; `LOG_FORMAT`), banco apenas via `DATABASE_URL`, logs no stdout, Gunicorn como PID 1 e nenhum endpoint de health dedicado (`/metrics` como liveness, R4 daquela change).

Esta change cria a infraestrutura AWS que vai executar essa imagem. O deploy em si será feito depois, por uma pipeline de CI/CD que não faz parte deste escopo.

Restrições acordadas:
- Terraform com o provider AWS; somente módulos locais, sem módulos da comunidade (registry ou Git de terceiros).
- ECS com Fargate; banco RDS PostgreSQL; VPC nova e independente, sem depender de nenhum recurso de rede existente.
- Multi-AZ; região padrão `us-east-1`, parametrizável.
- Imagem pública no Docker Hub; não há ECR.
- A task definition é criada e mantida pelo Terraform (deploys futuros passam por `terraform apply` com nova imagem).
- Backend em S3.
- Código em `terraform/` na raiz.
- Validação só com `terraform fmt` e `terraform validate`, sem credenciais AWS. Nada de `plan` nem `apply`.

## Goals / Non-Goals

**Goals:**
- Infraestrutura completa, reproduzível e parametrizada para rodar a aplicação na AWS.
- Alta disponibilidade entre AZs em todas as camadas (ALB, tasks, NAT, banco).
- Isolamento em camadas: só o ALB é público; app e banco ficam em subnets privadas, com acesso encadeado por security groups.
- Nenhum segredo em texto puro na task definition nem no repositório.
- Projeto validável offline (`fmt` + `validate`) para servir de gate na pipeline futura.

**Non-Goals:**
- Pipeline de CI/CD e as credenciais/OIDC que ela usará.
- Criação do bucket S3 de state (bootstrap).
- HTTPS, certificado ACM, domínio e Route 53.
- Autoscaling do service, WAF, backups cross-region, réplicas de leitura.
- Migrações de schema e correção de limitações do código (`SECRET_KEY` fixo, `create_all` no import).
- Múltiplos ambientes (dev/stage/prod) com diretórios separados. A parametrização por variáveis já permite isso via arquivos de `tfvars` e keys de state diferentes.

## Decisions

### D1. Layout: root module + módulos locais por domínio
```
terraform/
├── versions.tf          required_version, required_providers, backend "s3" {}
├── providers.tf         provider "aws" { region, default_tags }
├── variables.tf
├── main.tf              data "aws_availability_zones" + chamadas dos módulos
├── outputs.tf
├── terraform.tfvars.example
├── backend.hcl.example
└── modules/
    ├── network/         VPC, subnets, IGW, NAT, EIPs, route tables
    ├── security/        SGs do ALB, da app e do banco + regras
    ├── database/        random_password, subnet group, RDS, secret DATABASE_URL
    ├── alb/             ALB, target group, listener HTTP
    └── ecs/             cluster, log group, IAM roles, task definition, service
```
Cada módulo tem `main.tf`, `variables.tf`, `outputs.tf` e `versions.tf` (declarando `required_providers` sem bloco `provider`). O root só faz a composição.
- *Security groups num módulo próprio:* as regras se referenciam em cadeia (ALB → app → banco). Com elas num único módulo, a cadeia fica explícita e evita dependências cruzadas entre `alb`, `ecs` e `database`.
- *Alternativa:* um diretório por ambiente (`environments/dev`). Descartada por enquanto (ver Non-Goals).

### D2. Versões
- `required_version = ">= 1.10"`, a primeira versão com `use_lockfile` estável no backend S3.
- `hashicorp/aws ~> 6.0` e `hashicorp/random ~> 3.6`.
- O `.terraform.lock.hcl` é versionado para fixar os hashes dos providers.

### D3. Backend S3 com configuração parcial e lock nativo
`backend "s3" { use_lockfile = true, encrypt = true }`. `bucket`, `key` e `region` chegam por `-backend-config` (arquivo `backend.hcl`, com um `backend.hcl.example` versionado). O lock via DynamoDB está depreciado e não é usado.
- A validação usa `terraform init -backend=false`, que baixa os providers sem tocar no S3 e sem credenciais.
- *Alternativa:* backend local. Descartada porque a pipeline futura precisa de state compartilhado.

### D4. Região e AZs parametrizadas
- `var.aws_region` tem padrão `"us-east-1"`.
- As AZs vêm de `data "aws_availability_zones" { state = "available" }`, limitadas por `slice(..., 0, var.az_count)`.
- `var.az_count` tem padrão 2 e uma `validation` que exige `>= 2` (mínimo para ALB e RDS Multi-AZ).
- Nenhum nome de AZ fica fixo no código. O `validate` não consulta o data source, então não precisa de credenciais.

### D5. Rede: três camadas por AZ, NAT por AZ
- `var.vpc_cidr` tem padrão `10.0.0.0/16`. As subnets saem de `cidrsubnet()` indexado pela AZ: públicas `/24` a partir do índice 0, app a partir do 10 e banco a partir do 20.
- **Públicas:** rota padrão para o IGW. Hospedam o ALB e os NAT Gateways.
- **App:** cada uma tem a própria route table, com rota padrão para o NAT **da mesma AZ**. Isso mantém o isolamento de falha por AZ e é necessário porque o pull do Docker Hub sai pela internet (endpoints de VPC atendem só o ECR).
- **Banco:** route table sem rota padrão, ou seja, sem saída para a internet.
- VPC com `enable_dns_support` e `enable_dns_hostnames` ativados (necessário para o endpoint do RDS).
- *Alternativa:* um NAT único, mais barato. Descartada pelo requisito multi-AZ.
- *Alternativa:* tasks em subnet pública com IP público. Descartada por expor a app.

### D6. Security groups encadeados
- `sg-alb`: entrada TCP 80 de `var.allowed_ingress_cidrs` (padrão `0.0.0.0/0`); saída para `sg-app` na porta do container.
- `sg-app`: entrada na porta do container **apenas** de `sg-alb`; saída liberada (Docker Hub, Secrets Manager, CloudWatch e banco).
- `sg-db`: entrada TCP 5432 **apenas** de `sg-app`; sem regra de saída.
- As regras são recursos separados (`aws_vpc_security_group_ingress_rule` / `egress_rule`), seguindo a recomendação atual do provider e evitando ciclos entre os SGs.

### D7. RDS PostgreSQL
- Engine `postgres`, versão por `var.db_engine_version` (padrão `"16"`); classe por `var.db_instance_class` (padrão `db.t4g.micro`); `allocated_storage` e `max_allocated_storage` por variável.
- `multi_az = var.db_multi_az` (padrão `true`), `storage_encrypted = true`, `publicly_accessible = false`, subnet group nas subnets de banco.
- `deletion_protection` e `skip_final_snapshot` por variável. Os padrões (`false` / `true`) favorecem destruir e recriar o ambiente durante o estudo; para produção, devem ser invertidos no `tfvars`.
- `backup_retention_period` por variável (padrão 7).

### D8. `DATABASE_URL` no Secrets Manager
A aplicação aceita só a URL completa, e a injeção de segredos do ECS entrega um valor por variável. Por isso:
1. `random_password` com `special = false` e comprimento 32. Sem caracteres especiais, não há problema de URL-encoding nem conflito com os caracteres proibidos pelo RDS (`/`, `@`, `"`, espaço).
2. O RDS recebe `username`/`password` do Terraform. `manage_master_user_password` não é usado, porque o segredo gerado pelo RDS tem formato JSON e não serve como URL.
3. `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version` com `postgresql://<user>:<pass>@<address>:<port>/<db_name>`.
4. A task definition referencia o ARN em `secrets[].valueFrom`. A execution role recebe `secretsmanager:GetSecretValue` só nesse ARN.

`recovery_window_in_days` é variável (padrão 0), para permitir destruir e recriar sem conflito de nome.
- *Alternativa:* alterar a app para montar a URL a partir de partes. Descartada por estar fora do escopo de infraestrutura.
- *Alternativa:* entrypoint em shell. Descartada porque contraria o D4 da change de container.

### D9. ECS Fargate e task definition gerida pelo Terraform
- **Cluster** com `containerInsights` controlado por variável (padrão `disabled`, por custo).
- **Log group** `/ecs/<name>` com retenção por variável (padrão 14 dias). O driver `awslogs` usa a região de `var.aws_region`.
- **Task definition:**
  - `FARGATE`, `awsvpc`, `cpu`/`memory` por variável (padrão 256/512), `runtime_platform` `LINUX`/`X86_64` (arquitetura por variável).
  - Um container com `image = var.container_image` (por exemplo `docker.io/<usuario>/encontros-tech:<tag>`) e `essential = true`.
  - Port mapping em `var.container_port` (padrão 8000).
  - `environment`: `PORT`, `WEB_CONCURRENCY`, `LOG_FORMAT=simple`, mais um mapa extra por variável.
  - `secrets`: `DATABASE_URL`.
- **IAM:**
  - Execution role com `AmazonECSTaskExecutionRolePolicy` + política inline para o secret.
  - Task role vazia (a app não chama APIs AWS), declarada para permitir extensões futuras.
- **Service:**
  - `launch_type = "FARGATE"`, `desired_count = var.desired_count` (padrão 2, com `validation >= 1`).
  - Subnets de app, `assign_public_ip = false` e `sg-app`.
  - `load_balancer` apontando para o target group.
  - `deployment_circuit_breaker { enable = true, rollback = true }`.
  - `health_check_grace_period_seconds` por variável (padrão 60).
  - `depends_on` no listener do ALB.
  - Sem `ignore_changes` em `task_definition`: o Terraform é o dono das revisões, e o deploy futuro é `terraform apply -var container_image=...`.
- Como a imagem é pública, não há `repositoryCredentials`.

### D10. ALB HTTP
- ALB `internet-facing` nas subnets públicas, com `sg-alb`.
- Target group `target_type = "ip"`, protocolo HTTP na porta do container.
- Health check em `var.health_check_path` (padrão `/metrics`, que não acessa o banco), matcher `200`.
- `deregistration_delay` reduzido por variável (padrão 30), para deploys mais rápidos.
- Listener HTTP :80 com `forward` para o target group. Não há HTTPS (Non-Goal).

### D11. Nomenclatura e tags
- `var.project_name` (padrão `encontros-tech`) e `var.environment` (padrão `dev`) formam o prefixo `local.name = "${project}-${environment}"`.
- Tags comuns via `default_tags` do provider (`Project`, `Environment`, `ManagedBy = "terraform"`).
- Os nomes respeitam os limites da AWS: ALB e target group aceitam até 32 caracteres, e o target group usa `name_prefix` se o nome ficar longo.

### D12. Saídas
`alb_dns_name`, `app_url` (`http://<dns>`), `vpc_id`, IDs das subnets por camada, `ecs_cluster_name`, `ecs_service_name`, `task_definition_arn`, `db_endpoint`, `database_url_secret_arn` e `cloudwatch_log_group`. Nenhuma saída expõe a senha.

### D13. Validação sem credenciais
Executada a partir de `terraform/`:
1. `terraform fmt -check -recursive`
2. `terraform init -backend=false`
3. `terraform validate`

Nenhum comando acessa a AWS. Esse é o critério de aceite técnico da change.

## Risks / Trade-offs

- **R1. Senha do banco no state** → `random_password` e o secret ficam em texto no state. Mitigação: backend S3 com `encrypt = true` e acesso ao bucket restrito. Aceito por ser a forma de entregar a `DATABASE_URL` completa sem mudar a app.
- **R2. `create_all` concorrente (herdado da change de container)** → Com `desired_count = 2` e banco vazio, as tasks podem disputar o `CREATE TABLE` na primeira subida. Mitigação: circuit breaker com rollback e reinício automático das tasks. Na segunda tentativa a tabela já existe. Se for um problema na prática, aplicar o primeiro deploy com `desired_count = 1`.
- **R3. Rate limit de pull anônimo do Docker Hub** → O limite é por IP de saída, e há um IP por NAT. Em operação normal basta, mas laços de restart podem estourar. Aceito; a alternativa seria um mirror em ECR ou credenciais do Docker Hub.
- **R4. Dependência do Docker Hub em runtime** → Se o Docker Hub cair, tasks novas não sobem (as em execução continuam). Aceito.
- **R5. Custo fixo** → NAT por AZ, RDS Multi-AZ e ALB custam mesmo sem tráfego. Mitigação: `db_multi_az` e `az_count` são parametrizáveis; o ambiente pode ser destruído (padrões de D7).
- **R6. Validação não garante que o `apply` funciona** → `validate` não verifica cotas, nomes já existentes, disponibilidade de classes de instância na região nem permissões. Aceito: o `plan`/`apply` real fica para a pipeline.
- **R7. HTTP sem TLS** → O tráfego entre cliente e ALB não é criptografado. Aceito nesta fase (sem domínio).
- **R8. Health check em `/metrics`** → Não detecta falha de conexão com o banco. Aceito; depende de um endpoint de health na aplicação (change futura).
- **R9. `SECRET_KEY` fixo no código (herdado)** → Todas as tasks compartilham a mesma chave. Fora do escopo.

## Migration Plan

Não há `apply` nesta change. Para uso futuro:
1. Criar o bucket S3 de state (versionado e criptografado).
2. Copiar `backend.hcl.example` para `backend.hcl` e `terraform.tfvars.example` para `terraform.tfvars`.
3. Rodar `terraform init -backend-config=backend.hcl`.
4. Rodar `terraform apply`.

Rollback: `terraform destroy`. Nenhum recurso existente é tocado, porque a rede é nova.

## Open Questions

- Nenhuma bloqueante. A arquitetura de CPU (`X86_64` vs `ARM64`) depende de como a pipeline vai buildar a imagem; o padrão é `X86_64`.
