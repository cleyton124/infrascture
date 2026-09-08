Aqui está o arquivo completo em formato **`README.md`**, estruturado com a sintaxe oficial de Markdown do GitHub (incluindo *badges*, alertas e blocos de código).

As imagens estão apontadas para a sintaxe `![Descrição](./caminho-da-imagem.png)`. Basta salvar os 3 prints na mesma pasta do arquivo `README.md` (ou em uma pasta `images/`) e ajustar o nome do arquivo no código abaixo para que apareçam perfeitamente no seu repositório!

---

```markdown
# 🚀 Automação de Site Estático na AWS S3 com Terraform e GitHub Actions

![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235847b7.svg?style=for-the-badge&logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232671E5.svg?style=for-the-badge&logo=githubactions&logoColor=white)

Documentação técnica de engenharia de infraestrutura referente ao provisionamento automatizado de um site estático no Amazon S3 via Infraestrutura como Código (IaC), utilizando gatilhos baseados em *Issues* do GitHub.

---

## 📌 Visão Geral do Projeto

O objetivo deste projeto é automatizar a criação de sites estáticos na AWS. O fluxo de execução funciona da seguinte forma:

1. **Gatilho:** Uma nova *Issue* é aberta no repositório.
2. **Sanitização:** O GitHub Actions extrai o título da *Issue* e o formata para os padrões de nome do S3.
3. **Provisionamento (IaC):** O Terraform é executado e cria/configura o bucket S3 na AWS.
4. **Deploy:** O conteúdo estático (`index.html` e `404.html`) é sincronizado no bucket.
5. **Notificação:** A Actions comenta na *Issue* confirmando a conclusão e disponibilizando o endpoint.

> ⚠️ **Contexto do Ambiente:** O projeto foi desenvolvido em uma conta acadêmica **AWS Academy Learner Lab (`voclabs`)**. Por conta disso, a política IAM `Pvoclabs2` possui bloqueios explícitos (*explicit deny*) em diversas APIs da AWS, o que exigiu adaptações técnicas no Terraform para contornar limitações de permissão.

---

## 🛠️ Resolução de Desafios e Fluxo de Execução

Abaixo está o registro sequencial de erros enfrentados durante a construção da pipeline de CI/CD e como foram resolvidos.

### 1️⃣ Falha de Autenticação com a AWS

Na primeira execução da pipeline, a etapa de configuração das credenciais retornou falha ao se comunicar com a API da AWS.

![Erro de Credenciais AWS](./Screenshot%202026-09-08%20at%2009-39-39%20site-est%C3%A1tico-cleyton%20%C2%B7%20cleyton124_infrascture%4037aa93e.png)

* **Erro:** `Error: The security token included in the request is invalid.`
* **Causa Raiz:** Os tokens de sessão temporários da conta de laboratório expiraram ou foram inseridos incorretamente nos *Secrets* do GitHub.
* **Solução:** Atualização dos *Secrets* (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) no repositório com as credenciais válidas do painel do Vocareum.

---

### 2️⃣ Negação de Permissão IAM no Terraform (`Object Lock`)

Ao rodar o `terraform apply`, a criação nativa do recurso `aws_s3_bucket` foi bloqueada após a tentativa de leitura de configurações padrão.

![Erro Object Lock S3](./Screenshot%202026-09-08%20at%2009-42-24%20site-estatico-49864d868d%20%C2%B7%20cleyton124_infrascture%40cd24a4c.png)

* **Erro:** `Error: error getting S3 Bucket Object Lock configuration: AccessDenied ... with an explicit deny in an identity-based policy: arn:aws:iam::...:policy/Pvoclabs2`
* **Causa Raiz:** O provider padrão do Terraform executa chamadas de inspeção pós-criação (como `s3:GetBucketObjectLockConfiguration`). Como a política `Pvoclabs2` do laboratório possui um *Explicit Deny* para essa chamada, a execução é abortada.
* **Solução:** Substituição do recurso declarativo por um `null_resource` contendo comandos da **AWS CLI (`s3api`)** via `local-exec`. Isso evita chamadas invisíveis do provider nativo.

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

---

### 3️⃣ Permissões Insuficientes no `GITHUB_TOKEN`

Com o Terraform ajustado, a pipeline falhou no último *step*, responsável por responder à *Issue*.

* **Erro:** `Error: Unhandled error: HttpError: Resource not accessible by integration (status 403)`
* **Causa Raiz:** O token automático disponibilizado pelo GitHub Actions vem com privilégio apenas de leitura (`read-only`).
* **Solução:** Adicionar explicitamente a permissão de escrita em *Issues* na raiz do arquivo de *workflow*:

```yaml
permissions:
  contents: read
  issues: write

```

---

## ⚙️ Arquivo do GitHub Actions (`.github/workflows/provision.yml`)

Abaixo está o arquivo final consolidado da automação:

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

## 📊 Matriz de Aprendizados

| Categoria | Erro | Causa Raiz | Aprendizado / Solução |
| --- | --- | --- | --- |
| **AWS Security** | Invalid Token | Credenciais temporárias expiradas. | Atualizar os *Secrets* no GitHub ao reiniciar sessões no AWS Lab. |
| **Terraform / IaC** | `AccessDenied` Object Lock | Leitura automática do provider bloqueada por *Deny* explícito no IAM. | Orquestrar ações imperativas via AWS CLI dentro de `null_resource`. |
| **CI/CD** | HTTP 403 na API do GitHub | `GITHUB_TOKEN` padrão sem permissão de escrita. | Declarar `permissions: issues: write` no arquivo do workflow. |
| **Storage** | 404 `NoSuchKey` | Infraestrutura provisionada sem os arquivos estáticos. | Incluir etapa de sincronização (`aws s3 sync`) pós-apply na pipeline. |

```

```