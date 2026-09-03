name: Create S3 Static Site

on:
  issues:
    types: [opened]

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

      - name: Extract Bucket Name from Issue
        id: get_bucket
        run: |
          # Limpa o nome do bucket tirando espaços ou caracteres especiais
          BUCKET=$(echo "${{ github.event.issue.title }}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
          echo "BUCKET_NAME=static-site-$BUCKET" >> $GITHUB_ENV

      - name: Create S3 Bucket and Configure Website via AWS CLI
        run: |
          # 1. Cria o Bucket S3
          aws s3api create-bucket \
            --bucket ${{ env.BUCKET_NAME }} \
            --region us-west-2 \
            --create-bucket-configuration LocationConstraint=us-west-2 || true

          # 2. Desativa o bloqueio de acesso público
          aws s3api put-public-access-block \
            --bucket ${{ env.BUCKET_NAME }} \
            --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

          # 3. Configura o S3 para Hospedagem de Site Estático
          aws s3api put-bucket-website \
            --bucket ${{ env.BUCKET_NAME }} \
            --website-configuration '{"IndexDocument": {"Suffix": "index.html"}, "ErrorDocument": {"Key": "404.html"}}'

      - name: Comment on Issue
        uses: actions/github-script@v6
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const bucketName = process.env.BUCKET_NAME;
            const endpoint = `http://${bucketName}.s3-website-us-west-2.amazonaws.com`;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `O Bucket do S3 foi criado com sucesso!\n\n**URL do Site Estático:** ${endpoint}`
            })