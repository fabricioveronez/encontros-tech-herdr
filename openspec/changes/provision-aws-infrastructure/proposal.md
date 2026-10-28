## Why

A imagem da aplicação Encontros Tech está sendo containerizada (change `containerize-application`), mas não existe nenhuma infraestrutura em nuvem para executá-la. Precisamos de uma infraestrutura AWS reproduzível, descrita em Terraform, que sirva de alvo para uma futura pipeline de CI/CD fazer o deploy da aplicação.

## What Changes

- Novo projeto Terraform em `terraform/`, na raiz do repositório, usando apenas o provider oficial da AWS (e o `random`, da HashiCorp) e **módulos locais**, sem nenhum módulo da comunidade.
- Rede totalmente independente: uma VPC nova, multi-AZ, com subnets públicas, privadas de aplicação e privadas de banco em cada AZ, um Internet Gateway e um NAT Gateway por AZ.
- Banco PostgreSQL no Amazon RDS (Multi-AZ por padrão) em subnets sem rota para a internet, com senha gerada pelo Terraform e `DATABASE_URL` completa guardada no AWS Secrets Manager.
- Aplicação no Amazon ECS com Fargate, atrás de um Application Load Balancer público (HTTP), com a imagem puxada do Docker Hub (repositório público). A task definition é criada e versionada pelo Terraform, e a imagem chega pela variável `container_image`.
- Região padrão `us-east-1` (Virgínia do Norte), parametrizável por variável, e AZs derivadas da região.
- Backend de state remoto em S3 com lock nativo (`use_lockfile`), em configuração parcial: bucket e key são informados no `terraform init`.
- Validação sem credenciais AWS: `terraform fmt -check -recursive` e `terraform init -backend=false` + `terraform validate`. Não há `plan` nem `apply` nesta change.
- Entradas no `.gitignore` para state, diretório `.terraform/` e arquivos `*.tfvars` locais.

## Capabilities

### New Capabilities
- `terraform-project`: estrutura do projeto Terraform (root module, módulos locais, versões, backend S3, variáveis de região e de ambiente) e o processo de validação sem credenciais.
- `aws-network`: VPC independente multi-AZ, com subnets por camada, roteamento, NAT por AZ e security groups encadeados ALB → app → banco.
- `aws-database`: instância RDS PostgreSQL privada, criptografada e Multi-AZ, e o segredo `DATABASE_URL` consumido pela aplicação.
- `aws-container-service`: cluster ECS Fargate, task definition, service, Application Load Balancer, logs no CloudWatch e papéis IAM necessários para executar a imagem pública do Docker Hub.

### Modified Capabilities
<!-- Nenhuma: não existem specs anteriores em openspec/specs/. -->

## Impact

- **Arquivos novos:** tudo em `terraform/` (root module, `modules/network`, `modules/security`, `modules/database`, `modules/alb`, `modules/ecs`, exemplos de `tfvars` e de configuração de backend) e o `.terraform.lock.hcl` gerado pelo `init`.
- **Arquivos alterados:** `.gitignore` (entradas de Terraform). Nenhuma alteração em código Python, `requirements.txt` ou nos arquivos da change `containerize-application`.
- **Dependência de contrato:** a task definition assume o contrato da imagem definido em `containerize-application` (porta via `PORT`, banco apenas via `DATABASE_URL`, logs no stdout, `/metrics` como health check).
- **Custos quando aplicado (fora desta change):** NAT Gateways por AZ, RDS Multi-AZ, ALB e tasks Fargate geram custo contínuo.
- **Fora do escopo:** pipeline de CI/CD, criação do bucket de state, `terraform plan`/`apply`, HTTPS/ACM/DNS, autoscaling, migrações de banco e alterações no código da aplicação.
