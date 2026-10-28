## 1. Estrutura do projeto

- [ ] 1.1 Adicionar ao `.gitignore` da raiz as entradas `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfvars` (com exceção `!*.tfvars.example`), `backend.hcl` e `crash.log` (spec terraform-project)
- [ ] 1.2 Criar `terraform/versions.tf` com `required_version = ">= 1.10"`, `hashicorp/aws ~> 6.0`, `hashicorp/random ~> 3.6` e `backend "s3" { use_lockfile = true, encrypt = true }` sem bucket/key (design D2, D3)
- [ ] 1.3 Criar `terraform/providers.tf` com `region = var.aws_region` e `default_tags` (`Project`, `Environment`, `ManagedBy`) (design D11)
- [ ] 1.4 Criar `terraform/variables.tf` com as variáveis de raiz: `aws_region` (padrão `us-east-1`), `project_name`, `environment`, `az_count` (validação `>= 2`), `vpc_cidr`, `allowed_ingress_cidrs`, `container_image` (obrigatória), `container_port`, `task_cpu`, `task_memory`, `cpu_architecture`, `desired_count`, `web_concurrency`, `extra_environment`, `health_check_path`, `log_retention_days`, `enable_container_insights` e as variáveis do banco (design D4–D10)
- [ ] 1.5 Criar `terraform/backend.hcl.example` e `terraform/terraform.tfvars.example` com valores de exemplo (design D3)

## 2. Módulo network

- [ ] 2.1 Criar `terraform/modules/network` com `aws_vpc` (DNS habilitado) e `aws_internet_gateway` (design D5)
- [ ] 2.2 Criar as subnets pública, de app e de banco, uma por AZ, com `cidrsubnet()` nos índices 0/10/20; somente as públicas com `map_public_ip_on_launch = true` (design D5)
- [ ] 2.3 Criar um `aws_eip` e um `aws_nat_gateway` por AZ nas subnets públicas (design D5)
- [ ] 2.4 Criar as route tables: pública com `0.0.0.0/0` → IGW; uma por AZ para app com `0.0.0.0/0` → NAT da mesma AZ; banco sem rota padrão. Associar cada subnet à sua route table (design D5)
- [ ] 2.5 Expor `vpc_id` e os IDs das subnets por camada como outputs

## 3. Módulo security

- [ ] 3.1 Criar `terraform/modules/security` com os SGs do ALB, da app e do banco (design D6)
- [ ] 3.2 Criar as regras com `aws_vpc_security_group_ingress_rule`/`egress_rule`: ALB 80 a partir de `allowed_ingress_cidrs` e saída para a app; app `container_port` só a partir do ALB e saída liberada; banco 5432 só a partir da app (design D6)
- [ ] 3.3 Expor os IDs dos três SGs como outputs

## 4. Módulo database

- [ ] 4.1 Criar `terraform/modules/database` com `random_password` (`length = 32`, `special = false`) e `aws_db_subnet_group` nas subnets de banco (design D7, D8)
- [ ] 4.2 Criar o `aws_db_instance` PostgreSQL com `multi_az = var.db_multi_az`, `storage_encrypted = true`, `publicly_accessible = false` e variáveis para versão, classe, storage, backup, `deletion_protection` e `skip_final_snapshot` (design D7)
- [ ] 4.3 Criar `aws_secretsmanager_secret` (com `recovery_window_in_days` por variável) e `aws_secretsmanager_secret_version` com a `DATABASE_URL` completa (design D8)
- [ ] 4.4 Expor `db_endpoint` e `database_url_secret_arn` como outputs, sem senha (design D12)

## 5. Módulo alb

- [ ] 5.1 Criar `terraform/modules/alb` com o ALB `internet-facing` nas subnets públicas e o SG do ALB (design D10)
- [ ] 5.2 Criar o target group (`target_type = "ip"`, porta do container, health check em `var.health_check_path`, `matcher = "200"`, `deregistration_delay` por variável) e o listener HTTP :80 com `forward` (design D10)
- [ ] 5.3 Expor `alb_dns_name`, `target_group_arn` e `listener_arn` como outputs

## 6. Módulo ecs

- [ ] 6.1 Criar `terraform/modules/ecs` com `aws_ecs_cluster` (`containerInsights` por variável) e `aws_cloudwatch_log_group` com retenção por variável (design D9)
- [ ] 6.2 Criar a execution role (`AmazonECSTaskExecutionRolePolicy` + política inline com `secretsmanager:GetSecretValue` só no ARN do segredo) e a task role sem políticas (design D9)
- [ ] 6.3 Criar `aws_ecs_task_definition` Fargate com `runtime_platform`, `image = var.container_image`, `portMappings`, `environment` (`PORT`, `WEB_CONCURRENCY`, `LOG_FORMAT=simple` + extras), `secrets` com `DATABASE_URL` e `logConfiguration` `awslogs` (design D9)
- [ ] 6.4 Criar `aws_ecs_service` com `launch_type = "FARGATE"`, subnets de app, SG da app, `assign_public_ip = false`, `load_balancer`, circuit breaker com rollback, `health_check_grace_period_seconds`, sem `ignore_changes` em `task_definition` (design D9)
- [ ] 6.5 Expor nomes do cluster/service, ARN da task definition e nome do log group como outputs

## 7. Composição no root module

- [ ] 7.1 Criar `terraform/main.tf` com `local.name`, `data "aws_availability_zones"` (`state = "available"`) + `slice` por `az_count`, e as chamadas dos cinco módulos com `source` local (design D1, D4)
- [ ] 7.2 Criar `terraform/outputs.tf` com `alb_dns_name`, `app_url`, `vpc_id`, subnets por camada, `ecs_cluster_name`, `ecs_service_name`, `task_definition_arn`, `db_endpoint`, `database_url_secret_arn` e `cloudwatch_log_group` (design D12)

## 8. Validação (sem credenciais AWS)

Pré-condição: executar em `terraform/` com as variáveis `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` e `AWS_PROFILE` removidas do ambiente (`env -u ...`).

- [ ] 8.1 `terraform fmt -check -recursive` termina com código 0
- [ ] 8.2 `terraform init -backend=false` termina com código 0 e gera o `.terraform.lock.hcl`
- [ ] 8.3 `terraform validate` reporta `Success! The configuration is valid.`
- [ ] 8.4 `grep -rn 'source *=' terraform/` mostra apenas fontes locais (`./` ou `../`) em blocos `module`
- [ ] 8.5 `grep -rnE 'us-east-1[a-f]' terraform/` não encontra nada; `us-east-1` só aparece como padrão de `aws_region` e nos arquivos `.example`
- [ ] 8.6 `git check-ignore` confirma que `terraform/.terraform/`, `terraform/terraform.tfvars` e `terraform/backend.hcl` são ignorados, e que `terraform/.terraform.lock.hcl`, `terraform/terraform.tfvars.example` e `terraform/backend.hcl.example` não são
