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

      # Libera o bloqueio de acesso público ANTES de tentar setar ACL pública
      aws s3api put-public-access-block \
        --bucket ${local.full_bucket_name} \
        --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

      # Precisa existir antes de aplicar ACL, senão dá erro de "ACLs not supported"
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