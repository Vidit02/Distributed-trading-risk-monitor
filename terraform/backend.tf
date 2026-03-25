terraform {
  backend "s3" {
    bucket         = "trading-risk-monitor-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "trading-risk-monitor-tfstate-lock"
  }
}
