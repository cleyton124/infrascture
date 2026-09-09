# 🚀 Automação de Site Estático na AWS S3 com Terraform e GitHub Actions

![Site funcionando](./images/Home.png)
![404](./images/404.png)

Documentação técnica de um projeto de Infraestrutura como Código (IaC) que provisiona e publica um site estático no Amazon S3, disparado automaticamente pela abertura de uma *Issue* no GitHub.

> ⚠️ **Contexto do ambiente:** Uma empresa precisa de uma infraestrutura como código para suas worksload que não precisa de configurar manualmente a infraestrutura pelo console da AWS. para isso precisa de uma IAC para seu site estático subir ou destruir de forma escalavel.

---

## 📌 Visão geral do fluxo

```
Issue aberta no GitHub
        │
        ▼
GitHub Actions dispara o workflow
        │
        ▼
Configura credenciais AWS temporárias
        │
        ▼
Terraform + AWS CLI criam o bucket S3
        │
        ▼
Bucket é configurado (público, website, ACL)
        │
        ▼
Conteúdo do site é enviado (aws s3 sync)
        │
        ▼
Comentário de confirmação na Issue
        │
        ▼
Site estático publicado e acessível
```

1. **Gatilho:** uma nova *Issue* é aberta no repositório.
2. **Sanitização:** o nome da *Issue* é limpo e formatado para virar o nome do bucket.
3. **Provisionamento (IaC):** Terraform cria e configura o bucket S3.
4. **Deploy:** os arquivos estáticos (`index.html`, `404.html`) são sincronizados no bucket.
5. **Notificação:** o workflow comenta na *Issue* confirmando a conclusão.

---

## 📂 Estrutura do repositório

```
.
├── .github/
│   └── workflows/
│       └── provision-s3-static-site.yaml
├── images/
│   ├── workflows_github.png
│   ├── erro_autenticação.png
│   ├── erro_s3GetBucketObjectLockConfiguration.png
│   ├── buckets_da_conta.png
│   ├── sem_politica_bucket.png
│   ├── erro_403_Forbidden.png
│   ├── politica_bucket.png
│   ├── bucket_sem_objetos.png
│   ├── objetos_do_bucket.png
│   ├── 404.png
│   ├── 404_not_found.png
│   ├── upload_index.html_404.html.png
│   ├── Error Unhandled error HttpError Resource not accessible by integration.png
│   └── Home.png
├── site/
│   ├── index.html
│   └── 404.html
├── terraform/
│   └── s3_bucket_static_pasta/
│       └── main.tf
└── README.md
```

---

## 🛠️ Fluxo de execução detalhado — erros e soluções

Abaixo está o registro cronológico de tudo que aconteceu ao longo do desenvolvimento: cada erro real enfrentado, por que ele aconteceu, e como foi resolvido.

### 1️⃣ Issue aberta dispara o workflow

![Workflow disparado pela Issue](./images/workflows_github.png)

Criei pelo *Issue* a automação ou  CI/CD. O GitHub Actions está configurado para escutar esse evento:

```yaml
on:
  issues:
    types: [opened]
```

O título da *Issue* é extraído e limpo (minúsculas, sem acentos/caracteres especiais) para virar o nome do bucket:

```yaml
- name: Extract Bucket Name from Issue
  id: get_bucket
  run: |
    CLEAN_NAME=$(echo "${{ github.event.issue.title }}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    echo "BUCKET_NAME=$CLEAN_NAME" >> $GITHUB_ENV
```

---

### 2️⃣ Falha de autenticação com a AWS

![Erro de autenticação AWS](./images/erro_autenticação.png)

* **Erro:** token de sessão expirado (`ExpiredToken` / `The security token included in the request is invalid`).
* **Causa raiz:** minha contas do laboratório usa credenciais **temporárias**, com validade curta.Logo a sessão expirou no Github actions. 
* **Solução:** Precisei buscar credenciais novas e atualizar no Github.
---

### 3️⃣ Bloqueio de permissão no Terraform (Object Lock)

![Erro s3:GetBucketObjectLockConfiguration](./images/erro_s3GetBucketObjectLockConfiguration.png)

* **Erro:**
  ```
  Error: error getting S3 Bucket Object Lock configuration: AccessDenied
  ... is not authorized to perform: s3:GetBucketObjectLockConfiguration
  with an explicit deny in an identity-based policy: arn:aws:iam::...:policy/Pvoclabs2
  ```
* **Causa raiz:** o recurso nativo `aws_s3_bucket` do provider Terraform faz, automaticamente, uma leitura completa do bucket logo após criá-lo,incluindo a configuração de Object Lock,então a política `Pvoclabs2` do laboratório tem um **explicit deny** nessa chamada específica,bloqueando essa leitura.
* **Solução:** substitui o recurso declarativo `aws_s3_bucket` por um `null_resource` orquestrando a criação via **AWS CLI**, evitando a chamada automática que o provider faz:

```hcl
resource "null_resource" "static_site_bucket" {
  triggers = {
    bucket_name = local.full_bucket_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      aws s3api create-bucket \
        --bucket ${local.full_bucket_name} \
        --region us-west-2 \
        --create-bucket-configuration LocationConstraint=us-west-2

      aws s3api put-public-access-block \
        --bucket ${local.full_bucket_name} \
        --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

      aws s3api put-bucket-ownership-controls \
        --bucket ${local.full_bucket_name} \
        --ownership-controls '{"Rules":[{"ObjectOwnership":"BucketOwnerPreferred"}]}'

      aws s3api put-bucket-acl \
        --bucket ${local.full_bucket_name} \
        --acl public-read

      aws s3api put-bucket-website \
        --bucket ${local.full_bucket_name} \
        --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"404.html"}}'
    EOT
  }
}
```
OBS: passei muitas horas tentando enterder esse problema e foi o que mais causou problema.

**Lição aprendida:** quando um recurso nativo do Terraform faz chamadas "escondidas" que sua conta não tem permissão de executar, a solução não é insistir com o recurso declarativo, é orquestrar aquela etapa via CLI imperativo dentro de um `null_resource`.

---

### 9️ `GITHUB_TOKEN` sem permissão de escrita

![Erro de permissão ao comentar na Issue](./images/Error%20Unhandled%20error%20HttpError%20Resource%20not%20accessible%20by%20integration.png)

* **Erro:**
  ```
  RequestError [HttpError]: Resource not accessible by integration
  status: 403
  'x-accepted-github-permissions': 'issues=write; pull_requests=write'
  ```
* **Causa raiz:** por padrão, o `GITHUB_TOKEN` automático do GitHub Actions vem apenas com permissão de **leitura**. O último *step* do workflow precisa comentar na Issue, o que exige escrita.
* **Solução:** declarei explicitamente as permissões necessárias no início do arquivo de workflow:

```yaml
permissions:
  contents: read
  issues: write
```


### 4️⃣ Bucket criado com sucesso

![Bucket listado na conta AWS](./images/buckets_da_conta.png)

Com o `null_resource` no lugar do `aws_s3_bucket`, o `terraform apply` passou a rodar sem bater na permissão bloqueada,logo os buckets aparecem corretamente listado na conta.

---

### 5️⃣ Bucket sem política de acesso público

![Bucket sem política pública](./images/sem_politica_bucket.png)
![Erro 403 Forbidden ao acessar o site](./images/erro_403_Forbidden.png)

* **Erro:** `403 Forbidden` ao tentar acessar o endpoint do site.
* **Causa raiz:** por padrão, o S3 bloqueia toda leitura pública de objetos para manter o principio de menor privilegio,mesmo com o *website hosting* habilitado.Então liberei o *Public Access Block* e criei uma *Bucket Policy* de leitura pública.
* **Solução:** os comandos `put-public-access-block` e `put-bucket-acl` (já incluídos no `null_resource` da etapa 3) resolveram isso automaticamente a cada `apply`.

---

### 6️⃣ Política de acesso aplicada corretamente

![Política do bucket aplicada](./images/politica_bucket.png)

Depois de corrigir, o bucket passa a aceitar leitura pública dos objetos com permissão de leitura mantendo o principio de menor privilégio.
---

### 7️⃣ Bucket vazio → 404 NoSuchKey

![Bucket sem objetos](./images/bucket_sem_objetos.png)
![Erro 404](./images/404.png)
![Erro 404 Not Found detalhado](./images/404_not_found.png)

* **Erro:**
  ```
  404 Not Found
  Code: NoSuchKey
  Key: index.html
  ```
* **Causa raiz:** O S3 não tinha nenhum arquivo `index.html`/`404.html` dentro dele ainda.Provisionei pelo Terraform a infraestrutura mas não coloquei automaticamente para provisionar os arquivos no codigo.
* **Solução:** criação dos arquivos estáticos (`site/index.html`, `site/404.html`) e upload para o bucket.

---

### 8️⃣ Upload do conteúdo estático

![Upload de index.html e 404.html](./images/upload_index.html_404.html.png)
![Objetos dentro do bucket](./images/objetos_do_bucket.png)

Realizei o upload manual inicial via CLI, para validar:

```bash
aws s3 cp site/index.html s3://NOME-DO-BUCKET/
aws s3 cp site/404.html s3://NOME-DO-BUCKET/
```

Depois corrigi, automatizando dentro do workflow com `aws s3 sync`, garantindo que toda vez que uma nova Issue disparar o pipeline, o conteúdo mais recente da pasta `site/` seja publicado:

```yaml
- name: Upload Site Content
  run: |
    aws s3 sync ./site s3://static-site-${{ env.BUCKET_NAME }}/ --delete
```
---

### 🔟 Site publicado com sucesso

![Site estático funcionando](./images/Home.png)

Com todos os ajustes aplicados, o pipeline completo passa a funcionar de ponta a ponta: da Issue aberta até o site acessível publicamente pelo endpoint do S3.

---

## ⚙️ Workflow final (`.github/workflows/provision-s3-static-site.yaml`)

```yaml
name: Create S3 Static Site

on:
  issues:
    types: [opened]

permissions:
  contents: read
  issues: write

jobs:
  provision-s3:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-west-2

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Extract Bucket Name from Issue
        id: get_bucket
        run: |
          CLEAN_NAME=$(echo "${{ github.event.issue.title }}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
          echo "BUCKET_NAME=$CLEAN_NAME" >> $GITHUB_ENV

      - name: Run Terraform
        run: |
          cd terraform/s3_bucket_static_pasta
          terraform init
          terraform apply -auto-approve -var="bucket_name=${{ env.BUCKET_NAME }}"

      - name: Upload Site Content
        run: |
          aws s3 sync ./site s3://static-site-${{ env.BUCKET_NAME }}/ --delete

      - name: Comment on Issue
        uses: actions/github-script@v6
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: 'O Bucket S3 foi provisionado via Terraform e os arquivos estáticos foram publicados com sucesso!'
            })
```

---

## 🧱 Terraform final (`terraform/s3_bucket_static_pasta/main.tf`)

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.75.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

variable "bucket_name" {
  type        = string
  description = "Nome do bucket vindo da Issue do GitHub"
}

provider "aws" {
  region = "us-west-2"
}

locals {
  full_bucket_name = "static-site-${var.bucket_name}"
}

resource "null_resource" "static_site_bucket" {
  triggers = {
    bucket_name = local.full_bucket_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      aws s3api create-bucket \
        --bucket ${local.full_bucket_name} \
        --region us-west-2 \
        --create-bucket-configuration LocationConstraint=us-west-2

      aws s3api put-public-access-block \
        --bucket ${local.full_bucket_name} \
        --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

      aws s3api put-bucket-ownership-controls \
        --bucket ${local.full_bucket_name} \
        --ownership-controls '{"Rules":[{"ObjectOwnership":"BucketOwnerPreferred"}]}'

      aws s3api put-bucket-acl \
        --bucket ${local.full_bucket_name} \
        --acl public-read

      aws s3api put-bucket-website \
        --bucket ${local.full_bucket_name} \
        --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"404.html"}}'
    EOT
  }
}

output "website_endpoint" {
  value      = "${local.full_bucket_name}.s3-website-us-west-2.amazonaws.com"
  depends_on = [null_resource.static_site_bucket]
}
```

---

## 🔁 Como reproduzir o projeto

1. Faça um fork/clone deste repositório.
2. Configure os *Secrets* do repositório (`Settings → Secrets and variables → Actions`):
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN`
3. Ajuste `Settings → Actions → General → Workflow permissions` para permitir leitura e escrita, caso a organização restrinja por padrão.
4. Coloque o conteúdo do seu site em `site/index.html` e `site/404.html`.
5. Abra uma nova *Issue* com o nome desejado para o bucket — o pipeline faz o resto.

---

## 🔮 Possíveis melhorias futuras

- Adicionar checagem de idempotência no `null_resource` (evitar erro se o bucket já existir ao reabrir a Issue com o mesmo nome).
- Migrar de S3 website hosting público para **CloudFront + Origin Access Control**, mais seguro para produção fora do ambiente acadêmico.
- Adicionar step de `terraform destroy` disparado pelo fechamento da Issue, para limpeza automática de recursos.