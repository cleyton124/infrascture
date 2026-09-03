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

  # Desativa verificações padrão do provedor AWS que requerem permissões restritas no AWS Academy
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true

  # Ignora a checagem de Object Lock e outras verificações de APIs bloqueadas pelo IAM do Learner Lab
  s3_use_path_style           = false
}

# 1. Criação do Bucket S3 (desativando o calculo de partições)
resource "aws_s3_bucket" "static_site_bucket" {
  bucket        = "static-site-${var.bucket_name}"
  force_destroy = true

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

# 3. Liberação do Acesso Público
resource "aws_s3_bucket_public_access_block" "static_site_bucket" {
  bucket = aws_s3_bucket.static_site_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 4. Saída do Endpoint do Site
output "website_endpoint" {
  value       = aws_s3_bucket_website_configuration.static_site_config.website_endpoint
  description = "URL do site estático criado no S3"
}