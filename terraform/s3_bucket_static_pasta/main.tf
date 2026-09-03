provider "aws" {
  region = "us-west-2"
}

variable "bucket_name" {
  type        = string
  description = "Nome do bucket extraido do titulo da issue"
}

# 1. Criação do Bucket e configuração de site estático
resource "aws_s3_bucket" "static_site_bucket" {
  bucket = "static-site-${var.bucket_name}"

  website {
    index_document = "index.html"
    error_document = "404.html"
  }

  tags = {
    Name        = "Static Site Bucket"
    Environment = "Production"
  }
}

# 2. Desativação do bloqueio de acesso público
resource "aws_s3_bucket_public_access_block" "static_site_bucket" {
  bucket = aws_s3_bucket.static_site_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 3. Controle de propriedade dos objetos
resource "aws_s3_bucket_ownership_controls" "static_site_bucket" {
  bucket = aws_s3_bucket.static_site_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# 4. Aplicação da ACL pública de leitura
resource "aws_s3_bucket_acl" "static_site_bucket" {
  depends_on = [
    aws_s3_bucket_public_access_block.static_site_bucket,
    aws_s3_bucket_ownership_controls.static_site_bucket,
  ]

  bucket = aws_s3_bucket.static_site_bucket.id
  acl    = "public-read"
}