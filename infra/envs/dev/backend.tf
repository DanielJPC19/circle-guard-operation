terraform {
  backend "s3" {
    endpoint                    = "nyc3.digitaloceanspaces.com"
    bucket                      = "circleguard-tfstate"
    key                         = "dev/terraform.tfstate"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    region                      = "us-east-1"
  }
}
