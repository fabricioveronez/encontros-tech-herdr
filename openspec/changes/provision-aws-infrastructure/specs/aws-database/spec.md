## ADDED Requirements

### Requirement: Instância RDS PostgreSQL privada
A infraestrutura SHALL criar uma instância RDS com engine `postgres`, na versão de `db_engine_version` (padrão `"16"`) e classe de `db_instance_class` (padrão `db.t4g.micro`), usando um DB subnet group formado pelas subnets de banco. A instância MUST NOT ser publicamente acessível.

#### Scenario: Instância em subnets de banco
- **WHEN** o módulo `database` é inspecionado
- **THEN** o `aws_db_instance` usa `engine = "postgres"`, `publicly_accessible = false` e um `aws_db_subnet_group` com as subnets de banco, e está associado apenas ao SG do banco

### Requirement: Alta disponibilidade e criptografia
A instância SHALL ter `multi_az` controlado pela variável `db_multi_az`, com padrão `true`, e MUST ter armazenamento criptografado.

#### Scenario: Multi-AZ por padrão
- **WHEN** a variável `db_multi_az` e o `aws_db_instance` são inspecionados
- **THEN** o padrão é `true`, `multi_az = var.db_multi_az` e `storage_encrypted = true`

### Requirement: Ciclo de vida configurável
`deletion_protection`, `skip_final_snapshot` e `backup_retention_period` SHALL ser controlados por variáveis com padrões documentados.

#### Scenario: Variáveis de ciclo de vida
- **WHEN** as variáveis do módulo `database` são inspecionadas
- **THEN** existem variáveis para proteção contra exclusão, snapshot final e retenção de backup, usadas pelo `aws_db_instance`

### Requirement: Senha gerada pelo Terraform e segura para URL
A senha do usuário master SHALL ser gerada por `random_password` sem caracteres especiais, com no mínimo 32 caracteres. Ela MUST NOT ser definida como valor literal nem exposta em outputs.

#### Scenario: Geração da senha
- **WHEN** o módulo `database` é inspecionado
- **THEN** existe um `random_password` com `length >= 32` e `special = false`, usado como `password` do `aws_db_instance`

#### Scenario: Senha fora dos outputs
- **WHEN** os outputs do root module e do módulo `database` são inspecionados
- **THEN** nenhum output expõe a senha nem a `DATABASE_URL` em texto

### Requirement: DATABASE_URL no Secrets Manager
A string de conexão completa SHALL ser armazenada num segredo do AWS Secrets Manager no formato `postgresql://<usuario>:<senha>@<host>:<porta>/<banco>`, e o ARN do segredo SHALL ser exposto como output para o consumo da task definition.

#### Scenario: Conteúdo do segredo
- **WHEN** o `aws_secretsmanager_secret_version` é inspecionado
- **THEN** seu `secret_string` é montado com o usuário, a senha gerada, o `address`, a `port` e o `db_name` da instância RDS no formato `postgresql://`

#### Scenario: ARN exportado
- **WHEN** os outputs do módulo `database` são inspecionados
- **THEN** existe um output com o ARN do segredo da `DATABASE_URL`
