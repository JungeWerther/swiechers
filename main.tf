terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.72.1"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "lambda_example_container-image" {
  source  = "terraform-aws-modules/lambda/aws//examples/container-image"
  version = "7.14.0"
}

