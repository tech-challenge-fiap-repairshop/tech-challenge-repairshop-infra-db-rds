provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "RepairShop"
      Component   = "Database"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
