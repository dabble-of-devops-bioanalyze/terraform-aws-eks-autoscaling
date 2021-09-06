
data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

module "label" {
  source     = "cloudposse/label/null"
  version    = "0.24.1"
  attributes = ["cluster"]

  # https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html
  tags = {
    "k8s.io/cluster-autoscaler/${module.this.id}"         = "owned"
    "k8s.io/cluster-autoscaler/${module.this.id}-cluster" = "owned"
    "k8s.io/cluster-autoscaler/enabled"                   = "true"
    "kubernetes.io/cluster/${module.this.id}-cluster"     = "owned"
  }

  context = module.this.context
}

locals {
  # The usage of the specific kubernetes.io/cluster/* resource tags below are required
  # for EKS and Kubernetes to discover and manage networking resources
  # https://www.terraform.io/docs/providers/aws/guides/eks-getting-started.html#base-vpc-networking

  tags = merge(module.label.tags,
  map("kubernetes.io/cluster/${module.label.id}-cluster", "shared"))

  # Unfortunately, most_recent (https://github.com/cloudposse/terraform-aws-eks-workers/blob/34a43c25624a6efb3ba5d2770a601d7cb3c0d391/main.tf#L141)
  # variable does not work as expected, if you are not going to use custom ami you should
  # enforce usage of eks_worker_ami_name_filter variable to set the right kubernetes version for EKS workers,
  # otherwise will be used the first version of Kubernetes supported by AWS (v1.11) for EKS workers but
  # EKS control plane will use the version specified by kubernetes_version variable.
  eks_worker_ami_name_filter = "amazon-eks-node-${var.kubernetes_version}*"

  # required tags to make ALB ingress work https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
  public_subnets_additional_tags = {
    "kubernetes.io/role/elb" : 1
  }
  private_subnets_additional_tags = {
    "kubernetes.io/role/internal-elb" : 1
  }

  k8s_service_account_namespace = "kube-system"
  k8s_service_account_name      = "cluster-autoscaler-aws-cluster-autoscaler"
}

module "eks_cluster" {
  source  = "cloudposse/eks-cluster/aws"
  version = ">= 0.41.0"

  region                       = var.region
  vpc_id                       = var.vpc_id
  subnet_ids                   = var.subnet_ids
  kubernetes_version           = var.kubernetes_version
  local_exec_interpreter       = var.local_exec_interpreter
  oidc_provider_enabled        = var.oidc_provider_enabled
  enabled_cluster_log_types    = var.enabled_cluster_log_types
  cluster_log_retention_period = var.cluster_log_retention_period

  cluster_encryption_config_enabled                         = var.cluster_encryption_config_enabled
  cluster_encryption_config_kms_key_id                      = var.cluster_encryption_config_kms_key_id
  cluster_encryption_config_kms_key_enable_key_rotation     = var.cluster_encryption_config_kms_key_enable_key_rotation
  cluster_encryption_config_kms_key_deletion_window_in_days = var.cluster_encryption_config_kms_key_deletion_window_in_days
  cluster_encryption_config_kms_key_policy                  = var.cluster_encryption_config_kms_key_policy
  cluster_encryption_config_resources                       = var.cluster_encryption_config_resources
  workers_role_arns                                         = var.eks_workers_role_arns

  context = module.this.context
}

module "eks_workers" {
  depends_on = [module.eks_cluster]
  source     = "cloudposse/eks-workers/aws"
  version    = "0.19.2"


  # for_each = tomap(var.eks_worker_groups)
  for_each = { for eks_worker_group in var.eks_worker_groups : eks_worker_group.name => eks_worker_group }

  vpc_id                             = var.vpc_id
  subnet_ids                         = var.subnet_ids
  cluster_name                       = data.null_data_source.wait_for_cluster_and_kubernetes_configmap.outputs["cluster_name"]
  cluster_endpoint                   = module.eks_cluster.eks_cluster_endpoint
  cluster_certificate_authority_data = module.eks_cluster.eks_cluster_certificate_authority_data

  name          = "${module.label.id}-${each.value.name}"
  instance_type = each.value.instance_type
  min_size      = each.value.min_size
  max_size      = each.value.max_size

  tags = local.tags

  autoscaling_group_tags = {
    "k8s.io/cluster-autoscaler/${module.this.id}-cluster" = "owned"
    "k8s.io/cluster-autoscaler/${module.this.id}"         = "owned"
    "kubernetes.io/cluster/${module.this.id}-cluster"     = "owned"
    "k8s.io/cluster-autoscaler/enabled"                   = "true"
  }
  # bootstrap_extra_args = "--use-max-pods false"
  # kubelet_extra_args   = "--node-labels=purpose=ci-worker"

  context = module.this.context

  security_group_rules = [
    {
      type                     = "egress"
      from_port                = 0
      to_port                  = 65535
      protocol                 = "-1"
      cidr_blocks              = ["0.0.0.0/0"]
      source_security_group_id = null
      description              = "Allow all outbound traffic"
    },
    {
      type        = "ingress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      cidr_blocks = []
      # source_security_group_id = var.eks_worker_security_group_id
      source_security_group_id = module.eks_cluster.security_group_id
      description              = "Allow all inbound traffic from Security Group ID of the EKS cluster"
    }
  ]

  # Auto-scaling policies and CloudWatch metric alarms
  autoscaling_policies_enabled = var.eks_worker_group_autoscaling_policies_enabled
  # cpu_utilization_high_threshold_percent = var.cpu_utilization_high_threshold_percent
  # cpu_utilization_low_threshold_percent  = var.cpu_utilization_low_threshold_percent
}

data "null_data_source" "wait_for_cluster_and_kubernetes_configmap" {
  inputs = {
    cluster_name             = module.eks_cluster.eks_cluster_id
    kubernetes_config_map_id = module.eks_cluster.kubernetes_config_map_id
  }
}

module "eks_node_group" {
  depends_on = [module.eks_cluster]
  source     = "cloudposse/eks-node-group/aws"
  version    = "0.24.0"

  for_each       = { for eks_node_group in var.eks_node_groups : eks_node_group.name => eks_node_group }
  subnet_ids     = var.subnet_ids
  cluster_name   = data.null_data_source.wait_for_cluster_and_kubernetes_configmap.outputs["cluster_name"]
  instance_types = each.value.instance_types
  desired_size   = each.value.desired_size
  min_size       = each.value.min_size
  max_size       = each.value.max_size
  disk_size      = each.value.disk_size

  kubernetes_labels = var.kubernetes_labels
  # kubernetes_labels = local.tags
  tags = local.tags

  cluster_autoscaler_enabled = var.eks_node_group_autoscaling_enabled
  context                    = module.this.context
}

##################################################
# EKS Cluster Data 
# These are here more for demonstrative purposes
# And also to test that each of the providers can connect
##################################################

data "aws_eks_cluster" "cluster" {
  name = module.eks_cluster.eks_cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_cluster.eks_cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  //  version = "~> 1.11"
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.eks_cluster_id]
      command     = "aws"
    }
  }
}

resource "null_resource" "kubectl_update" {
  depends_on = [
    module.eks_cluster,
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "aws eks --region $AWS_REGION update-kubeconfig --name $NAME"
    environment = {
      AWS_REGION = var.region
      NAME       = module.eks_cluster.eks_cluster_id
    }
  }
}
