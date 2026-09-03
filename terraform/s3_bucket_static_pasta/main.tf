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

  skip_requesting_account_id = true
  skip_metadata_api_check    = true
  skip_region_validation     = true
}

# Cria o Bucket
resource "aws_s3_bucket" "static_site_bucket" {
  bucket        = "static-site-${var.bucket_name}"
  force_destroy = true

  tags = {
    Name        = "Static Site Bucket"
    Environment = "Production"
  }
}

# Configura o Site Estático
resource "aws_s3_bucket_website_configuration" "static_site_config" {
  bucket = aws_s3_bucket.static_site_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

# Libera o Acesso Público
resource "aws_s3_bucket_public_access_block" "static_site_bucket" {
  bucket = aws_s3_bucket.static_site_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

output "website_endpoint" {
  value       = aws_s3_bucket_website_configuration.static_site_config.website_endpoint
  description = "URL do site estático"
}