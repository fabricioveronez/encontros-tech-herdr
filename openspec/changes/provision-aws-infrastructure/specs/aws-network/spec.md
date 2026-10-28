## ADDED Requirements

### Requirement: VPC nova e independente
A infraestrutura SHALL criar uma VPC própria, com CIDR definido pela variável `vpc_cidr` (padrão `10.0.0.0/16`) e suporte a DNS habilitado. Ela MUST NOT referenciar VPC, subnets ou gateways existentes na conta.

#### Scenario: VPC criada pelo módulo
- **WHEN** o módulo `network` é inspecionado
- **THEN** ele declara um `aws_vpc` com `cidr_block = var.vpc_cidr`, `enable_dns_support = true` e `enable_dns_hostnames = true`, e nenhum `data` source de VPC ou subnet existente

### Requirement: Distribuição multi-AZ
A rede SHALL se distribuir em `az_count` AZs (padrão 2), obtidas dinamicamente da região. `az_count` MUST ser validado como maior ou igual a 2.

#### Scenario: Validação de quantidade de AZs
- **WHEN** a variável `az_count` é inspecionada
- **THEN** ela tem padrão `2` e um bloco `validation` que rejeita valores menores que 2

#### Scenario: Uma subnet por camada em cada AZ
- **WHEN** o módulo `network` é inspecionado
- **THEN** as subnets públicas, de aplicação e de banco são criadas uma por AZ selecionada, com CIDRs calculados por `cidrsubnet()` sem sobreposição entre camadas

### Requirement: Camada pública com saída via Internet Gateway
As subnets públicas SHALL ter rota padrão (`0.0.0.0/0`) para um Internet Gateway e hospedar o ALB e os NAT Gateways.

#### Scenario: Rota pública
- **WHEN** a route table das subnets públicas é inspecionada
- **THEN** ela tem rota `0.0.0.0/0` para o Internet Gateway da VPC

### Requirement: Camada de aplicação privada com NAT por AZ
As subnets de aplicação MUST NOT atribuir IP público. Cada uma SHALL ter saída para a internet por um NAT Gateway localizado na mesma AZ, com um NAT Gateway (e um Elastic IP) por AZ.

#### Scenario: NAT por AZ
- **WHEN** o módulo `network` é inspecionado
- **THEN** existem tantos `aws_nat_gateway` e `aws_eip` quanto AZs selecionadas, cada NAT numa subnet pública diferente

#### Scenario: Rota da subnet de aplicação aponta para o NAT da mesma AZ
- **WHEN** a route table de uma subnet de aplicação da AZ N é inspecionada
- **THEN** sua rota `0.0.0.0/0` aponta para o NAT Gateway da AZ N

### Requirement: Camada de banco isolada
As subnets de banco MUST NOT ter rota para a internet, nem via Internet Gateway nem via NAT.

#### Scenario: Sem rota padrão
- **WHEN** a route table das subnets de banco é inspecionada
- **THEN** ela não contém rota `0.0.0.0/0`

### Requirement: Security groups encadeados
O acesso entre camadas SHALL ser controlado por três security groups: ALB, aplicação e banco. A aplicação MUST aceitar tráfego somente do SG do ALB, na porta do container. O banco MUST aceitar tráfego somente do SG da aplicação, na porta 5432.

#### Scenario: Entrada no ALB
- **WHEN** as regras de entrada do SG do ALB são inspecionadas
- **THEN** existe apenas entrada TCP 80 a partir dos CIDRs de `allowed_ingress_cidrs` (padrão `["0.0.0.0/0"]`)

#### Scenario: Entrada na aplicação
- **WHEN** as regras de entrada do SG da aplicação são inspecionadas
- **THEN** existe apenas entrada TCP na porta `container_port` com origem no SG do ALB

#### Scenario: Entrada no banco
- **WHEN** as regras de entrada do SG do banco são inspecionadas
- **THEN** existe apenas entrada TCP 5432 com origem no SG da aplicação, sem nenhum bloco CIDR
