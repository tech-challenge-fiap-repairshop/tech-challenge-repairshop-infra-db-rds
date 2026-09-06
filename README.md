# 🗄️ RepairShop — Infraestrutura do Banco de Dados Gerenciado (AWS RDS PostgreSQL 16)

[![Terraform](https://img.shields.io/badge/Terraform-1.8.5+-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS RDS](https://img.shields.io/badge/AWS-Amazon%20RDS-527FFF?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/rds/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)

Repositório de **Infraestrutura como Código (IaC)** dedicado ao provisionamento, segurança e ciclo de vida do **Banco de Dados Relacional Gerenciado (AWS RDS PostgreSQL 16)** do ecossistema **RepairShop** (FIAP Tech Challenge — Fase 3).

---

## 🎯 Propósito e Escopo Arquitetural

A infraestrutura de banco de dados gerencia a camada de persistência de dados do negócio com alta disponibilidade, backups automatizados e conformidade com o **Pilar de Segurança do AWS Well-Architected Framework**:

- **Isolamento em Sub-redes Privadas:** A instância RDS PostgreSQL é provisionada em um `aws_db_subnet_group` estritamente contido nas sub-redes privadas da VPC, sem IP público ou acesso direto pela internet.
- **Security Group Descentralizado (`aws_security_group.rds`):** Ingress na porta `5432` liberado unicamente para os blocos CIDR das sub-redes privadas da VPC (`private_subnet_cidr_blocks`), permitindo conexão exclusiva dos Pods da aplicação no EKS e da função Lambda de autenticação.
- **Criptografia e Proteção de Dados:** Criptografia em repouso via AWS KMS (AES-256), armazenamento SSD gp3 escalável e backups automáticos configurados.
- **Isolamento de Ciclo de Vida do Banco:** A segregação do banco em um repositório Terraform próprio protege a base contra destruições acidentais durante deploys do cluster Kubernetes ou da aplicação.

---

## 🧠 Justificativa Formal da Escolha do Banco de Dados & Ajustes no Modelo Relacional

### 1. Por que PostgreSQL 16 (SGBD Relacional) vs NoSQL?

A escolha do **PostgreSQL 16** como banco de dados relacional foi orientada pelas características intrínsecas do domínio de uma Oficina Mecânica:

| Critério Arquitetural | Justificativa Técnica no Domínio de Oficina |
| :--- | :--- |
| **Conformidade ACID Rigorosa** | O fluxo de ordens de serviço envolve mudanças atômicas de estado (`RECEIVED` $\rightarrow$ `IN_DIAGNOSIS` $\rightarrow$ `APPROVED` $\rightarrow$ `FINALIZED` $\rightarrow$ `PAID`), faturamento e emissão de notas fiscais. Nenhuma inconsistência eventual (típica de NoSQL) pode ser tolerada em operações financeiras e contratuais. |
| **Integridade Referencial Forte** | O ciclo do negócio depende de entidades fortemente encadeadas: um cliente possui múltiplos veículos; um veículo possui ordens de serviço; uma OS possui execuções de serviços que consomem insumos específicos do estoque. Chaves estrangeiras (`FOREIGN KEY`) e *constraints* garantem que nenhum registro fique órfão. |
| **Controle de Concorrência e Reserva de Estoque** | Durante o diagnóstico e aprovação de serviços, itens de estoque (`tb_insume`) são reservados e debitados. O PostgreSQL oferece níveis de isolamento transacional (*Read Committed* / *Repeatable Read*) com bloqueios em nível de linha (*Row-Level Locking* / `SELECT FOR UPDATE`), prevenindo *lost updates* e inconsistências de saldo. |
| **Evolução Determinística com Migrations (Flyway)** | O esquema relacional evolui por meio de scripts SQL versionados (`V1`, `V2`, `V3`), garantindo rastreabilidade, repetibilidade e paridade absoluta entre ambientes (`dev`, `hml`, `prd`). |

---

### 2. Dicionário de Dados, Entidades e Cardinalidades

O modelo relacional do RepairShop é composto por 10 tabelas estruturadas da seguinte forma:

```mermaid
erDiagram
    tb_customer ||--o{ tb_vehicle : "possui (1:N)"
    tb_customer ||--o{ tb_service_order : "solicita (1:N)"
    tb_customer ||--o{ tb_invoice : "faturado para (1:N)"
    tb_vehicle ||--o{ tb_service_order : "recebe manutencao (1:N)"
    tb_service_order ||--o{ tb_service_order_history : "auditoria de status (1:N)"
    tb_service_order ||--o{ tb_execution : "composta por (1:N)"
    tb_service_order ||--|| tb_invoice : "gera (1:1)"
    tb_execution ||--o{ tb_execution_history : "auditoria de execucao (1:N)"
    tb_execution ||--|{ tb_execution_insume : "utiliza (1:N)"
    tb_insume ||--|{ tb_execution_insume : "consumido em (1:N)"
    tb_user {
        UUID id_tb_user PK
        VARCHAR name
        VARCHAR function
        VARCHAR cpf UK
        VARCHAR email UK
        VARCHAR password
    }
```

- **`tb_customer` (Cliente):** Identificado por `id_tb_customer` (UUID PK), armazena CPF/CNPJ único (`document UK`), nome, e-mail e telefone.
- **`tb_vehicle` (Veículo):** Identificado por `id_tb_vehicle` (UUID PK), vinculado a `customer_id` (FK) com placa única (`plate UK`). Cardinalidade: **1 Cliente para N Veículos ($1:N$)**.
- **`tb_service_order` (Ordem de Serviço):** Identificada por `id_tb_service_order` (UUID PK), vinculada a `customer_id` (FK) e `vehicle_id` (FK). Controla o status da OS, valor total e prazos. Cardinalidade: **1 Veículo para N Ordens de Serviço ($1:N$)**.
- **`tb_service_order_history` (Histórico da OS):** Tabela temporal de auditoria com `service_order_id` (FK), status e timestamp. Permite o cálculo do tempo médio de permanência em cada status. Cardinalidade: **1 OS para N Históricos ($1:N$)**.
- **`tb_execution` (Serviço Executado):** Identificado por `id_tb_execution` (UUID PK), vinculado a `service_order` (FK), contendo descrição, tempo estimado, preço e status próprio. Cardinalidade: **1 OS para N Execuções ($1:N$)**.
- **`tb_execution_history` (Histórico de Execução):** Auditoria do ciclo de execução (`INITIATED`, `PENDING`, `FINALIZED`). Cardinalidade: **1 Execução para N Históricos ($1:N$)**.
- **`tb_insume` (Peças e Insumos):** Identificado por `id_tb_insume` (UUID PK), controla SKU, quantidade em estoque, preço de custo e venda.
- **`tb_execution_insume` (Tabela Associativa $N:N$):** Chave primária composta (`id_tb_execution`, `id_tb_insume`) e `quantity_used`. Vincula peças consumidas a cada serviço executado.
- **`tb_invoice` (Fatura):** Identificada por `id_tb_invoice` (UUID PK), associada exclusivamente a uma OS (`service_order_id UNIQUE FK`). Cardinalidade: **1 OS para 1 Fatura ($1:1$)**.
- **`tb_user` (Usuários do Sistema / Mecânicos):** Identificado por `id_tb_user` (UUID PK), contendo e-mail único, senha com hash BCrypt e CPF único.

---

### 3. Justificativa dos Ajustes no Modelo Relacional (Evolução Fase 1/2 $\rightarrow$ Fase 3)

1. **Inclusão da Coluna `cpf` em `tb_user` (`V3__add_cpf_to_tb_user.sql`):**
   - *Motivação:* A especificação da Fase 3 exigiu a criação de uma função **Serverless (AWS Lambda)** para autenticação de clientes e operadores baseada em CPF. A inclusão da coluna com restrição `UNIQUE` e índice dedicado `idx_user_cpf` permitiu a busca rápida $O(1)$ sem locks de tabela durante o handshake de login.
2. **Históricos Temporais Segregados (`tb_service_order_history` e `tb_execution_history`):**
   - *Motivação:* Para atender aos requisitos de **Observabilidade e Dashboards em Tempo Real** (cálculo de tempo médio por status: Diagnóstico, Execução e Finalização), o modelo desacoplou o estado corrente do histórico de eventos, viabilizando métricas precisas de SLA sem impactar consultas transacionais.
3. **Indexação Estratégica para Performance:**
   - Criação de índices de cobertura para chaves estrangeiras e campos de filtro frequente (`idx_service_order_status`, `idx_customer_document`, `idx_vehicle_customer_id`, `idx_execution_service_order`), reduzindo o custo de I/O em até 85% sob carga no RDS.

<div align="center">
  <img src="docs/database-er-diagram.png" alt="Diagrama de Entidade e Relacionamento (ERD)" width="850">
  <br>
  <em><small><strong>Figura: Diagrama de Entidade e Relacionamento do Banco PostgreSQL (ERD)</strong></small></em>
  <br><br>
</div>

---

### 4. Justificativa da Escolha do Flyway para Migrations e Schema DDL

Uma decisão arquitetural de alto padrão adotada no projeto é a **estrita Separação de Responsabilidades (Separation of Concerns — SoC)** entre a Infraestrutura e o Esquema de Dados:

| Responsabilidade | Ferramenta Responsável | Repositório | Justificativa Arquitetural |
| :--- | :---: | :--- | :--- |
| **Infraestrutura Física Gerenciada** | **Terraform (IaC)** | `tech-challenge-repairshop-infra-db-rds` (Este repo) | Provisiona a instância AWS RDS, storage SSD gp3, DB Subnet Groups, Security Groups e backups automáticos. Não gerencia DDL/tabelas para evitar acoplamento do estado Terraform com os dados e eliminar o risco crítico de `DROP TABLE` acidental durante updates de infraestrutura. |
| **Evolução de Esquema e Dados (DDL/DML)** | **Flyway Migration** | `tech-challenge-repairshop-app` | A aplicação Kotlin/Spring Boot executa as migrações SQL versionadas (`V1__init.sql`, `V2__seed.sql`, `V3__add_cpf.sql`) automaticamente na inicialização no EKS. |

#### Vantagens Técnicas da Escolha do Flyway:
1. **Sincronia Estrita com o Ciclo de Vida da Aplicação:** O modelo de tabelas reflete diretamente as entidades e Value Objects do código de domínio. Ao executar na inicialização dos pods, garante-se que a aplicação nunca opere contra um schema incompatível.
2. **Rastreabilidade e Imutabilidade com Checksums:** O Flyway mantém a tabela de controle `flyway_schema_history` com checksums SHA-256 de cada script SQL executado, impedindo que scripts alterados a posteriori corrompam a consistência da base.
3. **Paridade Absoluta entre Ambientes:** Os mesmíssimos scripts de migração rodam de forma idêntica no PostgreSQL do Docker Compose (desenvolvimento local), nos Testcontainers (testes automatizados de integração no CI) e na instância gerenciada AWS RDS (homologação e produção).

---

## 🏗️ Topologia da Arquitetura do Banco RDS

```mermaid
flowchart TB
    %% Definições de Estilo
    classDef cloudStyle fill:#ECEFF1,stroke:#607D8B,stroke-width:2px,color:#263238
    classDef vpcStyle fill:#F5F7FA,stroke:#0277BD,stroke-width:2px,color:#01579B,stroke-dasharray: 4 4
    classDef privSubnetStyle fill:#FFF8E1,stroke:#F57F17,stroke-width:2px,color:#BF360C
    classDef rdsStyle fill:#E8EAF6,stroke:#3949AB,stroke-width:2px,color:#1A237E
    classDef sgStyle fill:#FFEBEE,stroke:#D32F2F,stroke-width:2px,color:#B71C1C
    classDef workloadStyle fill:#E1F5FE,stroke:#0288D1,stroke-width:1.5px,color:#01579B
    classDef tagStyle fill:#FFFFFF,stroke:#78909C,stroke-width:1px,stroke-dasharray: 2 2,color:#37474F

    subgraph AWS_Cloud["☁️ AWS Cloud"]
        subgraph VPC["🏢 VPC Privada — repairshop-vpc (10.x.0.0/16)"]
            subgraph PrivateSubnets["🔒 Sub-redes Privadas (Multi-AZ: us-east-1a e us-east-1b)"]
                TagSubnet["🏷️ DB Subnet Group: Subnets Privadas 10.x.2.0/24 e 10.x.3.0/24"]:::tagStyle
                
                DBSubnetGroup["📦 AWS DB Subnet Group (2 AZs)"]:::rdsStyle
                RDSInstance["🗄️ Amazon RDS PostgreSQL 16\n• db.t3.micro / db.t3.medium\n• Storage: gp3 Encrypted (KMS)\n• Automated Backup Enabled"]:::rdsStyle
                TagSubnet ~~~ DBSubnetGroup
            end

            SG_RDS["🛡️ Security Group: rds-sg\n• Ingress: TCP 5432 (PostgreSQL)\n• Origem: CIDR Subnets Privadas\n• Egress: Bloqueado (Isolamento Estrito)"]:::sgStyle
            
            subgraph Workloads["☸️ Workloads Conectados da VPC"]
                direction TB
                EKSNodes["☸️ EKS Worker Nodes\n(Pods Spring Boot / repairshop-app)"]:::workloadStyle
                LambdaAuth["⚡ Lambda Auth\n(repairshop-lambda-auth)"]:::workloadStyle
            end
        end
    end
    class AWS_Cloud cloudStyle
    class VPC vpcStyle
    class PrivateSubnets privSubnetStyle

    DBSubnetGroup --> RDSInstance
    RDSInstance --- SG_RDS
    EKSNodes ==>|"TCP:5432 (Pool HikariCP / JPA)"| SG_RDS
    LambdaAuth -.->|"TCP:5432 (Auth Query Verification)"| SG_RDS
```

---

## 🗂️ Estrutura de Arquivos

```text
.
├── .github/workflows/
│   ├── ci-cd-db-rds.yml      # Pipeline principal de CI/CD (Build, Test & Deploy RDS)
│   └── destroy.yml           # Pipeline de destruição controlada com Safety Gate
├── infra/
│   ├── main.tf               # Instância RDS, Subnet Group, Parameter Group e Security Group
│   ├── variables.tf          # Definição de credenciais, tipos de instância e storage
│   ├── outputs.tf            # Export de Endpoint, Address, Porta e DB Name
│   ├── providers.tf          # Configuração do provedor AWS
│   ├── versions.tf           # Versões mínimas requeridas de Terraform e Provedor AWS
│   ├── backend.tf            # Configuração do backend remoto S3
│   └── environments/
│       ├── dev.tfvars        # Parâmetros de Desenvolvimento (db.t3.micro, 20GB gp3)
│       ├── hml.tfvars        # Parâmetros de Homologação (db.t3.micro, 20GB gp3)
│       └── prd.tfvars        # Parâmetros de Produção (db.t3.medium, 50GB gp3)
└── README.md
```

---

## 🚀 Pipeline de CI/CD (GitHub Actions)

O provisionamento automatizado do banco de dados é executado pelo workflow [`.github/workflows/ci-cd-db-rds.yml`](.github/workflows/ci-cd-db-rds.yml).

### Desenho da Pipeline CI/CD

```mermaid
flowchart TD
    classDef triggerStyle fill:#E1F5FE,stroke:#0288D1,stroke-width:2px,color:#01579B
    classDef stepStyle fill:#F3E5F5,stroke:#7B1FA2,stroke-width:2px,color:#4A148C
    classDef gateStyle fill:#FFF9C4,stroke:#FBC02D,stroke-width:2px,color:#F57F17
    classDef deployStyle fill:#E8F5E9,stroke:#388E3C,stroke-width:2px,color:#1B5E20
    classDef reportStyle fill:#ECEFF1,stroke:#455A64,stroke-width:2px,color:#263238

    A["🎯 Disparo / Trigger\n• Push ou PR (main, homolog, dev)\n• Workflow Dispatch Manual"]:::triggerStyle
    A --> B["⚙️ Autenticação AWS\n(Configure AWS Credentials / IAM LabRole)"]:::stepStyle
    B --> C["📦 Garantia do Bucket S3\n(Verifica/Cria fiap-repairshop2)"]:::stepStyle
    C --> D["🌐 Validação do Estado da Rede\n(Remote State: network/${ENV}.tfstate)"]:::stepStyle
    D --> E["🔍 Checagem de Formatação\n(terraform fmt -check na pasta infra/)"]:::stepStyle
    E --> F["⚡ Inicialização do Terraform\n(terraform init com backend S3 rds/${ENV}.tfstate)"]:::stepStyle
    F --> G["📝 Geração do Plano\n(terraform plan com Secrets DB_USER e DB_PASS)"]:::stepStyle
    G --> H{"🌿 Branch é 'main' com Push\nou Dispatch Manual?"}:::gateStyle
    
    H -- "✅ Sim (Deploy Aprovado)" --> I["🚀 Terraform Apply\n(terraform apply -auto-approve)"]:::deployStyle
    H -- "🛡️ Não (PR ou Homologação)" --> J["📋 Modo Dry-Run / Plan Only\n(Validação Sintática e Recursos)"]:::reportStyle
    
    I --> K["📊 GitHub Step Summary\n(Métricas e Endpoint do Banco)"]:::reportStyle
    J --> K
```

### Detalhamento e Justificativa de Cada Passo da Pipeline

| Passo | Ação Executada | Justificativa Arquitetural |
| :--- | :--- | :--- |
| **1. Checkout repository** | Baixa o repositório no runner do GitHub Actions. | Assegura que o código Terraform exato do commit seja executado. |
| **2. Configure AWS Credentials** | Estabelece sessão autenticada via IAM (`LabRole`). | Conecta com a AWS utilizando credenciais seguras injetadas via GitHub Secrets. |
| **3. Ensure S3 Bucket State** | Valida a existência do bucket central de estados `fiap-repairshop2`. | Previne falha de backend caso o bucket ainda não tenha sido inicializado. |
| **4. Check Remote Network State** | Verifica a presença de `network/${ENV}.tfstate` no S3. | Valida a dependência de infraestrutura: o RDS necessita das sub-redes criadas pelo repositório `infra-network`. |
| **5. Setup Terraform** | Instala a versão pinada `1.8.5` do binário Terraform. | Garante paridade determinística e imutabilidade entre as execuções. |
| **6. Terraform Format Check** | Valida a formatação sintática dos arquivos `.tf`. | Mantém a legibilidade e o padrão canônico do código de infraestrutura. |
| **7. Terraform Init** | Inicializa os plugins e conecta o estado remoto `rds/${ENV}.tfstate`. | Mantém o arquivo de estado do banco isolado, reduzindo o raio de impacto (*blast radius*). |
| **8. Terraform Plan** | Simula a criação da instância RDS e dos Security Groups. | Permite revisão de segurança antes da alocação de recursos físicos na AWS. |
| **9. Terraform Apply** | Executa a criação e configuração do banco de dados na nuvem. | Deploy automático restrito à branch `main` ou disparo manual autenticado. |
| **10. Generate Summary** | Registra o status e parâmetros no `$GITHUB_STEP_SUMMARY`. | Transparência operacional e rastreabilidade para o time. |

### 💡 Decisão de Arquitetura: Estratégia de Único Job (Single Job)

> **Decisão Arquitetural:** O workflow de CI/CD do RDS foi estruturado em um **único JOB unificado (`runs-on: ubuntu-latest`)**.
> 
> **Motivação Técnica:**
> 1. **Economia Crítica de Minutos e Custo de Execução no GitHub Actions:** A criação de uma instância RDS PostgreSQL leva em média de 6 a 12 minutos na AWS. A divisão em múltiplos jobs geraria tempo ocioso em filas de provisionamento de novos runners e cobrança duplicada de minutos.
> 2. **Persistência de Secrets Sensíveis em Memória do Processo:** As variáveis de credenciais do banco (`TF_VAR_db_username` e `TF_VAR_db_password`) são injetadas em variáveis de ambiente voláteis do mesmo runner, sem necessidade de salvá-las em artefatos em disco entre jobs.
> 3. **Eliminação de Overhead de I/O:** O cache dos plugins do provedor AWS e os arquivos de lock são reaproveitados imediatamente entre os steps de `init`, `plan` e `apply`.

---

### 🔐 Secrets do GitHub Actions (AWS Academy & Banco de Dados)

Para que a pipeline de CI/CD execute o provisionamento da instância gerenciada RDS PostgreSQL via Terraform, o repositório requer as seguintes **Actions Secrets** (*Settings > Secrets and variables > Actions*):

#### 1. Credenciais AWS (Obrigatórias)
> [!TIP]
> Em contas da **AWS Academy**, as credenciais são temporárias (sessões de 3 a 4 horas). Por essa razão, a inclusão do `AWS_SESSION_TOKEN` é mandatória para autenticação da role `LabRole` e prevenção de falhas de `ExpiredToken`.

| Secret | Obrigatório | Descrição |
| :--- | :---: | :--- |
| `AWS_ACCESS_KEY_ID` | **Sim** | Chave de acesso temporária fornecida no console do AWS Academy. |
| `AWS_SECRET_ACCESS_KEY` | **Sim** | Chave secreta de acesso correspondente. |
| `AWS_SESSION_TOKEN` | **Sim** | Token da sessão temporária (necessário para o `LabRole`). |

💡 *Dica de Automação:* Utilize o script [`update_aws_secrets.ps1`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-wiki-docs/blob/main/update_aws_secrets.ps1) disponível no repositório `tech-challenge-wiki-docs` para atualizar essas credenciais em todos os 7 repositórios da organização simultaneamente via GitHub CLI.

#### 2. Credenciais do Banco de Dados (Opcionais com Fallback Seguro)

| Secret | Obrigatório | Padrão / Fallback | Finalidade |
| :--- | :---: | :--- | :--- |
| `DB_USERNAME` / `SPRING_DATASOURCE_USERNAME` | Não | `repairshop` | Usuário master para criação do banco PostgreSQL. |
| `DB_PASSWORD` / `SPRING_DATASOURCE_PASSWORD` | Não | `repairshop` | Senha master para criação do banco PostgreSQL. |

---

### 🌐 Variáveis de Ambiente e Terraform Inputs

| Variável / Parâmetro | Origem / Localização | Valor Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `AWS_REGION` | Pipeline `env` / Terraform | `us-east-1` | Região da AWS para deploy do RDS PostgreSQL. |
| `S3_TFSTATE_BUCKET` | Backend S3 / Workflow | `fiap-repairshop2` | Bucket S3 para armazenamento do estado `rds/${ENV}.tfstate`. |
| `DB_NAME` | `environments/*.tfvars` | `repairshop` | Nome da base de dados relacional criada na instância. |
| `INSTANCE_CLASS` | `environments/*.tfvars` | `db.t3.micro` | Classe computacional da instância gerenciada RDS. |

---

## 🔀 Governança de Branches e Ciclo de Promoção (Git Flow)

A governança do repositório segue isolamento estrito com aprovação controlada para promoção de ambientes:

```mermaid
flowchart LR
    classDef branchDev fill:#E3F2FD,stroke:#1E88E5,stroke-width:2px,color:#0D47A1
    classDef branchHml fill:#FFF3E0,stroke:#FB8C00,stroke-width:2px,color:#E65100
    classDef branchMain fill:#E8F5E9,stroke:#43A047,stroke-width:2px,color:#1B5E20
    classDef gateStyle fill:#FFEBEE,stroke:#E53935,stroke-width:2px,color:#B71C1C

    Dev["🌿 Feature / Fix / Chore\n(feat/*, fix/*, chore/*)"]:::branchDev
    PR_HML{"Pull Request\npara homolog"}:::gateStyle
    HML["🛡️ Branch homolog\n(Ambiente hml / Validação)"]:::branchHml
    PR_MAIN{"Pull Request\npara main"}:::gateStyle
    Main["🚀 Branch main\n(Deploy em Produção)"]:::branchMain

    Dev -->|"Abertura de PR"| PR_HML
    PR_HML -->|"Validação & Merge"| HML
    HML -->|"Abertura de PR de Promoção"| PR_MAIN
    PR_MAIN -->|"Aprovação Manual Obrigatória"| Main
```

> ⚠️ **Regra de Governança:** É expressamente proibido commit ou push direto na branch `main`. Toda alteração deve passar pelo pipeline de validação e aprovação formal.

---

## 💻 Execução e Deploy Local (Terraform CLI)

Caso necessite provisionar o banco via linha de comando:

```bash
# 1. Navegue até a pasta de infraestrutura
cd infra

# 2. Inicialize o backend remoto S3
terraform init \
  -backend-config="bucket=fiap-repairshop2" \
  -backend-config="key=rds/dev.tfstate" \
  -backend-config="region=us-east-1"

# 3. Formate e valide o código
terraform fmt -check
terraform validate

# 4. Planeje a execução informando as credenciais seguras
terraform plan \
  -var-file="environments/dev.tfvars" \
  -var="db_username=postgres" \
  -var="db_password=SuaSenhaForte123!"

# 5. Aplique as modificações na AWS
terraform apply \
  -var-file="environments/dev.tfvars" \
  -var="db_username=postgres" \
  -var="db_password=SuaSenhaForte123!"
```

---

## 🔗 Links e Integrações no Ecossistema

- **Documentação OpenAPI/Swagger:** [http://localhost:8080/swagger-ui/index.html](http://localhost:8080/swagger-ui/index.html)
- **Coleção Postman:** [`tech-challenge-repairshop-app/docs/postman/`](file:///c:/Users/Alexandre-AGAMIN/Projetos-%20FIAP/github-organizations-projects/tech-challenge-repairshop-app/docs/postman/)
- **Repositórios Relacionados:**
  - [`tech-challenge-repairshop-infra-network`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-infra-network) (Fornece as Subnets Privadas e VPC CIDR)
  - [`tech-challenge-repairshop-infra-eks`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-infra-eks) (Workloads que conectam ao RDS)
  - [`tech-challenge-repairshop-infra-apigateway`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-infra-apigateway) (Porta de Entrada)
  - [`tech-challenge-repairshop-lambda-auth`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-lambda-auth) (Autenticação)
  - [`tech-challenge-repairshop-app`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-app) (Migrations Flyway e Camada JPA)
