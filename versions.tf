terraform {
  required_version = ">= 0.13"

  required_providers {
    # Update these to reflect the actual requirements of your module
    local = {
      source  = "hashicorp/local"
      version = ">= 1.2"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    null = {
      source = "hashicorp/null"
    }
    template = {
      source = "hashicorp/template"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}
