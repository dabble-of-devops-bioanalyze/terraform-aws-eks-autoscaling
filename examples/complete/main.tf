provider "aws" {
  region = var.region
}

module "example" {
  source = "../.."

  region     = var.region
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  oidc_provider_enabled             = true
  cluster_encryption_config_enabled = true

  context = module.this.context
}
