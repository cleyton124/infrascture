terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "bucket_name" {
  type        = string
  description = "Nome do bucket vindo da Issue do GitHub"
}

provider "aws" {
  region = "us-west-2"

  # Bypasses para evitar chamadas de leitura bloqueadas pelo IAM da AWS Academy
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true

  # Previne que o provider tente validar o estilo do endpoint via API
  s3_use_path_style           = false
}

# 1. Bucket S3 com o bloco lifecycle/ignore_changes para ignorar o Object Lock
resource "aws_s3_bucket" "static_site_bucket" {
  bucket        = "static-site-${var.bucket_name}"
  force_destroy = true

  lifecycle {
    ignore_changes = [
      object_lock_configuration,
      object_lock_enabled
    ]
  }

  tags = {
    Name        = "Static Site Bucket"
    Environment = "Production"
  }
}

# 2. Configuração do Site Estático
resource "aws_s3_bucket_website_configuration" "static_site_config" {
  bucket = aws_s3_bucket.static_site_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

# 3. Liberação de acesso público
resource "aws_s3_bucket_public_access_block" "static_site_bucket" {
  bucket = aws_s3_bucket.static_site_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 4. Saída da URL do site
output "website_endpoint" {
  value       = aws_s3_bucket_website_configuration.static_site_config.website_endpoint
  description = "URL do site estático criado no S3"
}