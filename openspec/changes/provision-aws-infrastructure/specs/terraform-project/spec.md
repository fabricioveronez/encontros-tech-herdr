## ADDED Requirements

### Requirement: Projeto Terraform no diretório `terraform/`
Todo o código de infraestrutura SHALL ficar no diretório `terraform/` na raiz do repositório, organizado como um root module que compõe módulos locais em `terraform/modules/`.

#### Scenario: Estrutura de diretórios
- **WHEN** o diretório `terraform/` é listado
- **THEN** existem `versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf` e o diretório `modules/` com os módulos `network`, `security`, `database`, `alb` e `ecs`

#### Scenario: Cada módulo tem interface própria
- **WHEN** um diretório em `terraform/modules/` é inspecionado
- **THEN** ele contém `main.tf`, `variables.tf` e `outputs.tf`, e não declara bloco `provider`

### Requirement: Somente módulos locais
O projeto MUST NOT usar módulos do Terraform Registry nem módulos de repositórios de terceiros. Todo `source` de bloco `module` SHALL ser um caminho local.

#### Scenario: Fontes de módulos locais
- **WHEN** todos os blocos `module` em `terraform/` são inspecionados
- **THEN** todo atributo `source` começa com `./` ou `../`

### Requirement: Providers oficiais com versões fixadas
O projeto SHALL declarar `required_version` e `required_providers` com restrições de versão, usando apenas providers do namespace `hashicorp` (`aws` e `random`). O arquivo `.terraform.lock.hcl` MUST ser versionado.

#### Scenario: Restrições de versão declaradas
- **WHEN** o `terraform/versions.tf` é inspecionado
- **THEN** `required_version` exige no mínimo `1.10`, e `hashicorp/aws` e `hashicorp/random` têm restrição de versão explícita

#### Scenario: Lock file presente
- **WHEN** o diretório `terraform/` é listado após o `init`
- **THEN** o `.terraform.lock.hcl` existe e não é ignorado pelo `.gitignore`

### Requirement: Região parametrizável com padrão na Virgínia do Norte
A região AWS SHALL vir da variável `aws_region`, com padrão `us-east-1`. Nenhum nome de região ou de AZ MUST estar fixo fora dos padrões de variáveis.

#### Scenario: Padrão de região
- **WHEN** a variável `aws_region` é inspecionada
- **THEN** o padrão é `"us-east-1"` e o provider `aws` usa `var.aws_region`

#### Scenario: Sem AZs fixas
- **WHEN** os arquivos `.tf` são inspecionados
- **THEN** nenhum nome de AZ (por exemplo `us-east-1a`) aparece literalmente; as AZs vêm de `data "aws_availability_zones"`

### Requirement: Backend S3 com configuração parcial
O state SHALL ser armazenado em um backend `s3` com `use_lockfile = true` e `encrypt = true`. `bucket`, `key` e `region` MUST ser fornecidos no `terraform init` (configuração parcial), com um `backend.hcl.example` versionado como referência.

#### Scenario: Backend declarado sem bucket fixo
- **WHEN** o bloco `backend "s3"` é inspecionado
- **THEN** ele contém `use_lockfile = true` e `encrypt = true` e não contém `bucket` nem `key`

#### Scenario: Exemplo de configuração de backend
- **WHEN** o `terraform/backend.hcl.example` é inspecionado
- **THEN** ele mostra `bucket`, `key` e `region` com valores de exemplo

### Requirement: Nomes e tags padronizados
Os recursos SHALL ser nomeados a partir de `project_name` e `environment` e MUST receber as tags `Project`, `Environment` e `ManagedBy` via `default_tags` do provider.

#### Scenario: Tags padrão no provider
- **WHEN** o bloco `provider "aws"` é inspecionado
- **THEN** `default_tags` define `Project`, `Environment` e `ManagedBy = "terraform"`

### Requirement: Arquivos sensíveis e gerados fora do Git
O `.gitignore` MUST ignorar `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfvars` (exceto `*.tfvars.example`), `backend.hcl` e `crash.log`.

#### Scenario: Arquivos locais ignorados
- **WHEN** `git check-ignore` é executado para `terraform/.terraform/`, `terraform/terraform.tfstate`, `terraform/terraform.tfvars` e `terraform/backend.hcl`
- **THEN** todos são ignorados, e `terraform/terraform.tfvars.example` e `terraform/backend.hcl.example` não são

### Requirement: Validação sem credenciais AWS
O projeto SHALL passar em formatação e validação sem nenhuma credencial AWS. `terraform plan` e `terraform apply` MUST NOT fazer parte da validação.

#### Scenario: Formatação
- **WHEN** `terraform fmt -check -recursive` é executado em `terraform/`
- **THEN** o comando termina com código 0 e não lista arquivos

#### Scenario: Validação offline
- **WHEN** `terraform init -backend=false` e `terraform validate` são executados em `terraform/` sem variáveis `AWS_*` e sem perfil AWS configurado
- **THEN** ambos terminam com código 0 e o `validate` reporta `Success! The configuration is valid.`
