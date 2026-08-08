terraform {
  backend "s3" {
    bucket  = "fiap-repairshop2"
    key     = "rds/dev.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
