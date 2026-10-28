## ADDED Requirements

### Requirement: Cluster ECS para Fargate
A infraestrutura SHALL criar um cluster ECS, com Container Insights controlado por variável, para executar a aplicação com Fargate.

#### Scenario: Cluster criado
- **WHEN** o módulo `ecs` é inspecionado
- **THEN** existe um `aws_ecs_cluster` com a configuração `containerInsights` vinda de variável

### Requirement: Task definition gerida pelo Terraform
O Terraform SHALL criar e versionar a task definition da aplicação. Ela MUST:
- usar `requires_compatibilities = ["FARGATE"]` e `network_mode = "awsvpc"`;
- ter CPU e memória parametrizáveis;
- ter um único container essencial cuja imagem vem da variável `container_image`.

#### Scenario: Imagem vinda de variável
- **WHEN** a task definition é inspecionada
- **THEN** o container usa `image = var.container_image` (uma imagem pública do Docker Hub) e não declara `repositoryCredentials`

#### Scenario: Sem ignorar mudanças da task definition
- **WHEN** o `aws_ecs_service` é inspecionado
- **THEN** ele referencia a task definition do Terraform e não contém `ignore_changes` para `task_definition`, de modo que um novo `container_image` gera uma nova revisão no `apply`

### Requirement: Configuração do container conforme o contrato da imagem
O container SHALL receber `PORT` (igual a `container_port`, padrão 8000), `WEB_CONCURRENCY` e `LOG_FORMAT=simple` como variáveis de ambiente. A `DATABASE_URL` MUST ser injetada exclusivamente via `secrets` a partir do ARN do Secrets Manager, nunca em `environment`.

#### Scenario: Segredo injetado
- **WHEN** as `container_definitions` são inspecionadas
- **THEN** `secrets` contém `DATABASE_URL` com `valueFrom` igual ao ARN do segredo, e `environment` não contém `DATABASE_URL`

#### Scenario: Porta alinhada
- **WHEN** as `container_definitions` são inspecionadas
- **THEN** o `portMappings` usa `container_port`, e a variável `PORT` do ambiente tem o mesmo valor

### Requirement: Logs no CloudWatch
A saída do container SHALL ser enviada a um log group do CloudWatch criado pelo Terraform, com retenção configurável, via driver `awslogs`.

#### Scenario: Driver de log
- **WHEN** as `container_definitions` são inspecionadas
- **THEN** `logConfiguration` usa `awslogs`, com o log group do módulo e a região de `aws_region`

### Requirement: Papéis IAM de privilégio mínimo
A task SHALL ter uma execution role com a política gerenciada `AmazonECSTaskExecutionRolePolicy` e permissão `secretsmanager:GetSecretValue` restrita ao ARN do segredo da `DATABASE_URL`. A task role MUST NOT ter permissões anexadas.

#### Scenario: Permissão ao segredo restrita
- **WHEN** as políticas da execution role são inspecionadas
- **THEN** a ação `secretsmanager:GetSecretValue` tem como `Resource` apenas o ARN do segredo da `DATABASE_URL`

### Requirement: Service multi-AZ em subnets privadas
O service SHALL usar `launch_type = "FARGATE"`, executar `desired_count` tasks (padrão 2) nas subnets de aplicação de todas as AZs, sem IP público, com o SG da aplicação, e ficar registrado no target group do ALB.

#### Scenario: Rede do service
- **WHEN** o `aws_ecs_service` é inspecionado
- **THEN** `network_configuration` usa as subnets de aplicação, o SG da aplicação e `assign_public_ip = false`

#### Scenario: Rollback automático de deploy
- **WHEN** o `aws_ecs_service` é inspecionado
- **THEN** `deployment_circuit_breaker` está com `enable = true` e `rollback = true`

### Requirement: Application Load Balancer público
Um ALB `internet-facing` SHALL ser criado nas subnets públicas, com listener HTTP na porta 80 encaminhando para um target group do tipo `ip` na porta do container. O health check SHALL usar `health_check_path`, com padrão `/metrics`, e esperar status 200.

#### Scenario: Encaminhamento
- **WHEN** o módulo `alb` é inspecionado
- **THEN** existe um listener na porta 80 com ação `forward` para um target group com `target_type = "ip"` e `port = container_port`

#### Scenario: Health check
- **WHEN** o target group é inspecionado
- **THEN** o health check usa `path = var.health_check_path` (padrão `/metrics`) e `matcher = "200"`

### Requirement: Saídas para operação e deploy
O root module SHALL expor como outputs o DNS do ALB, a URL da aplicação, os nomes do cluster e do service, o ARN da task definition e o nome do log group.

#### Scenario: Outputs disponíveis
- **WHEN** o `terraform/outputs.tf` é inspecionado
- **THEN** existem os outputs `alb_dns_name`, `app_url`, `ecs_cluster_name`, `ecs_service_name`, `task_definition_arn` e `cloudwatch_log_group`
