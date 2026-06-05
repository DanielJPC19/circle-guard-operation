terraform {
  backend "gcs" {
    bucket = "circleguard-tfstate"
    prefix = "prod/terraform.tfstate"
  }
}
