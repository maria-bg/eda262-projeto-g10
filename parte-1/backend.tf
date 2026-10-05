terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "eda262-g10-terraform-state"
    key            = "parte-1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "eda262-g10-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}
