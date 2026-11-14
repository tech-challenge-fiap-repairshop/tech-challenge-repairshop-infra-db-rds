terraform {
  backend "s3" {
    key     = "rds/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

