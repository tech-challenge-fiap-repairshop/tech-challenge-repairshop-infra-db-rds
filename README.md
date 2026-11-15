# 🐘🔒 Repair Shop — Infra Database RDS PostgreSQL (`infra-db-rds`)

[![CI/CD Pipeline](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-db-rds/actions/workflows/ci-cd-db-rds.yml/badge.svg)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-db-rds/actions/workflows/ci-cd-db-rds.yml)
[![Terraform](https://img.shields.io/badge/Terraform-1.8.5-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![PostgreSQL 16](https://img.shields.io/badge/Amazon%20RDS-PostgreSQL%2016-336791?logo=postgresql&logoColor=white)](https://aws.amazon.com/rds/postgresql/)

Repositório de **Infraestrutura como Código (Terraform)** que provisiona a instância gerenciada **Amazon RDS (PostgreSQL 16)** da plataforma **Repair Shop (Tech Challenge FIAP — 15SOAT)** em sub-redes privadas da VPC, garantindo **persistência ACID e integridade referencial rigorosa** para o domínio cadastral (`app-register-service`).

---

## 📋 Índice

- [Recursos Provisionados e Segurança](#recursos-provisionados-e-segurança)
- [Arquitetura Atual — Motivação e Benefícios dos Componentes](#arquitetura-atual--motivação-e-benefícios-dos-componentes)
- [Por que DynamoDB em vez de Banco Relacional para OS e Pagamentos?](#por-que-dynamodb-em-vez-de-banco-relacional-para-os-e-pagamentos)
- [Como Executar e Validar Localmente (Terraform)](#como-executar-e-validar-localmente-terraform)
- [Como Executar em Produção (Esteira CI/CD GitHub Actions)](#como-executar-em-produção-esteira-cicd-github-actions)
- [Documentação Técnica e Collection do Postman](#documentação-técnica-e-collection-do-postman)

---

## Recursos Provisionados e Segurança

Conforme [`infra/main.tf`](infra/main.tf) e os arquivos `infra/environments/{dev,hml,prd}.tfvars`:

| Recurso AWS | Configuração Técnica | Benefício |
| :--- | :--- | :--- |
| **`aws_db_instance.postgres`** | • Engine: **PostgreSQL 16**<br>• Storage: `20 GB gp3` com **`storage_encrypted = true`**<br>• Classe (`dev`/`hml`/`prd`): `db.t3.micro`<br>• **`publicly_accessible = false`**, porta `5432`<br>• `db_name = "repairshop"` (`backup_retention_period`: `0` em `dev`/`prd`, `1` em `hml`) | Banco relacional gerenciado com criptografia em repouso e sem exposição direta à internet pública. |
| **`aws_db_subnet_group`** | Associado dinamicamente às sub-redes privadas retornadas pelo state remoto de `network/${var.environment}.tfstate` | Garante posicionamento exclusivo na camada privada da VPC. |
| **`aws_security_group.rds`** | Ingresso TCP `5432` restrito exclusivamente aos CIDRs das sub-redes privadas (`private_subnet_cidrs`) | Impede qualquer tentativa de conexão externa fora do cluster EKS/VPC privada. |

> **Estado Remoto**: Armazenado no S3 em `rds/${ENV}.tfstate`. O endpoint gerado é consultado dinamicamente na esteira de deploy do `app-register-service`.

---

## Arquitetura Atual — Motivação e Benefícios dos Componentes

| Pilar / Tecnologia | Papel no Ecossistema | Motivação Técnica e Pontos Positivos |
| :--- | :--- | :--- |
| **RDS (PostgreSQL 16)** | **Componente central deste repositório** — atende o [`app-register-service`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-register-service) | Dados mestre (`tb_customer`, `tb_vehicle`, `tb_user` geridos via **Flyway**) demandam chaves estrangeiras com integridade estrita (`ON DELETE CASCADE`) e constraints `UNIQUE` simultâneas (CPF/CNPJ, placa e e-mail) nativas do modelo relacional ACID. |
| **DynamoDB (NoSQL)** | Atende os contextos transacionais de OS e Pagamentos ([`infra-db-dynamo`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-db-dynamo)) | Retira do RDS o tráfego intenso de atualizações de status de OS, callbacks SQS e webhooks de pagamento, evitando contenção de conexões e locks de tabela. |
| **ElastiCache (Redis 7.0)** | Camada em memória em sub-rede privada ([`infra-redis`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-redis)) | Complementa o RDS no contexto do `register-service` (`spring-boot-starter-data-redis`), preparando cache distribuído sub-milissegundo para sessões e tokens JWT para evitar consultas repetidas ao PostgreSQL no login. |
| **Apps (EKS + Lambda Auth)** | Microsserviços em **EKS (`1.31`)** ([`infra-eks`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-eks)) + [`lambda-auth`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-lambda-auth) | O `lambda-auth` escala horizontalmente na borda e delega autenticação para o `register-service` no EKS, mantendo todas as conexões JDBC confinadas aos pods autorizados na VPC privada. |
| **Amazon SQS (Mensageria + DLQ)** | 5 filas padrão + 5 DLQs ([`infra-sqs`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-sqs)) | Permite coreografia assíncrona entre execução, pagamento e notificação (Saga Coreografada) sem manter transações SQL abertas esperando integrações externas ou SMTP. |
| **API Gateway (HTTP API v2)** | Ponto único de entrada ([`infra-apigateway`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-apigateway)) | Isola o tráfego externo por HTTP API v2, roteando para o Lambda Auth ou para os NLBs internos do EKS enquanto o RDS permanece completamente oculto na sub-rede privada. |
| **Observabilidade (Grafana)** | OpenTelemetry + Prometheus + Loki + Jaeger + Grafana | Permite monitorar latência de consultas JDBC, saúde das *readiness probes* (`db` no Actuator do `register-service`) e traces end-to-end até o banco nos 11 dashboards Grafana. |

---

## Por que DynamoDB em vez de Banco Relacional para OS e Pagamentos?

Manter o **RDS PostgreSQL** exclusivamente no `register-service` e utilizar **Amazon DynamoDB** (`tb-service_order-{env}` e `tb-payment-{env}`) para Ordens de Serviço e Pagamentos resulta de uma escolha arquitetural consciente:

1. **Proteção do RDS contra exaustão de pool de conexões**: No cluster EKS com Horizontal Pod Autoscaler (HPA), múltiplos pods de OS, Pagamentos e consumidores SQS concorrendo por conexões JDBC rapidamente saturariam o limite de conexões simultâneas de uma instância `db.t3.micro`. O DynamoDB usa HTTPS *stateless*, eliminando gargalos de pool de conexões.
2. **Agregados polimórficos e evolução de schema sem `ALTER TABLE`**: Cada OS armazena metadados, histórico de 12 estados, execuções e tarefas extras sob `PK=ORDER#<id>`; faturamentos reúnem pagamentos e faturas sob `PK=BILLING#<id>`. Modelar isso via SQL exige múltiplos `JOIN`s e migrações DDL sempre que atributos de pagamento do Mercado Pago evoluem.
3. **Transações e índices secundários orientados ao fluxo**: `TransactWriteItems` garante atomicidade dentro do agregado, e os GSIs (`pending-dispatch-index` e `dispatch-notification-index`) entregam consultas assíncronas rápidas em modo `PAY_PER_REQUEST`.

---

## Como Executar e Validar Localmente (Terraform)

> **Pré-requisitos**: **Terraform `1.8.5`**, **AWS CLI v2** autenticado e pré-existência do state de rede (`network/${ENV}.tfstate` criado pelo `infra-network`).

```bash
cd infra

# Inicializar com o backend S3 de estado remoto (ex.: ambiente dev)
terraform init \
  -backend-config="bucket=SEU_BUCKET_TERRAFORM_STATE" \
  -backend-config="key=rds/dev.tfstate" \
  -backend-config="region=us-east-1"

terraform fmt -check -recursive
terraform validate

# Simular criação/atualização usando o tfvars desejado
terraform plan -var-file="environments/dev.tfvars"
```

> Para testar apenas o banco PostgreSQL 16 em desenvolvimento local sem AWS, utilize o `docker-compose.yml` presente nos repositórios [`app-register-service`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-register-service) ou [`app`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app).

---

## Como Executar em Produção (Esteira CI/CD GitHub Actions)

Pipeline definida em [`.github/workflows/ci-cd-db-rds.yml`](.github/workflows/ci-cd-db-rds.yml) e remoção em [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml).

### Mapeamento de Ambientes e Gatilhos
- `develop` -> **`dev`** (`environments/dev.tfvars`)
- `homolog` -> **`hml`** (`environments/hml.tfvars`)
- `main` -> **`prd`** (`environments/prd.tfvars`)

### Etapas da Esteira
1. `terraform fmt -check` e `terraform validate`.
2. `terraform init` apontando para o remote state `rds/${ENV}.tfstate` (e lendo `network/${ENV}.tfstate` do S3).
3. `terraform plan` (em PRs e pushes).
4. `terraform apply -auto-approve` em pushes para `develop`, `homolog` e `main`.

> **Dependência obrigatória**: Execute **`infra-network`** antes deste repositório.

---

## Documentação Técnica e Collection do Postman

- **Arquivos Terraform deste Repositório**: [`infra/main.tf`](infra/main.tf) | [`infra/environments/dev.tfvars`](infra/environments/dev.tfvars) | [`infra/environments/hml.tfvars`](infra/environments/hml.tfvars) | [`infra/environments/prd.tfvars`](infra/environments/prd.tfvars)
- **Modelo Entidade-Relacionamento (PostgreSQL) & Diagrama Cloud**:
  - [`DER PostgreSQL (Referência Core)`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app/blob/main/docs/delivery/infrastructure/database-er-diagram.png)
  - [`Migration Inicial do Register Service (V1__init_register_schema.sql)`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-register-service/blob/main/src/main/resources/db/migration/V1__init_register_schema.sql)
  - [`Diagrama de Infraestrutura Cloud`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/delivery/infrastructure/repairshop-diagrama-infra-cloud.svg)
- **ADRs e RFCs**:
  - [ADRs (`ADR-001` a `ADR-013`)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/ADRs/README.md)
  - [RFCs (`RFC-001` a `RFC-014`)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/RFCs/README.md)
- **Postman Collections & Environments (Organização)**:
  - Collection Principal: [`Repair Shop (Tech Challenge FIAP)`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Repair%20Shop%20%28Tech%20Challenge%20FIAP%29.postman_collection.json)
  - Collection Completa: [`Tech Challenge FIAP - Completo`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Tech_Challenge_Fiap_-_Completo.postman_collection.json)
  - Environment Local: [`Local.postman_environment.json`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Local.postman_environment.json)
  - Guia do Postman: [`docs/postman/README.md`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/README.md)
- **Dashboards Grafana (11 JSONs)**: [`dashboards/`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/tree/main/local/observability/grafana/dashboards)
