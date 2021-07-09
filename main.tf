provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

module "label" {
  source     = "cloudposse/label/null"
  version    = "0.24.1"
  attributes = ["cluster"]

  tags = {
    "k8s.io/cluster-autoscaler/${module.this.cluster_name}" = "true"
    "k8s.io/cluster-autoscaler/enabled"                     = "true"
  }

  context = module.this.context
}

locals {
  # The usage of the specific kubernetes.io/cluster/* resource tags below are required
  # for EKS and Kubernetes to discover and manage networking resources
  # https://www.terraform.io/docs/providers/aws/guides/eks-getting-started.html#base-vpc-networking

  tags = merge(module.label.tags,
  map("kubernetes.io/cluster/${module.label.id}", "shared"))

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
}

module "eks_cluster" {
  source  = "cloudposse/eks-cluster/aws"
  version = "0.41.0"

  region                       = var.region
  vpc_id                       = module.vpc.vpc_id
  subnet_ids                   = concat(module.subnets.private_subnet_ids, module.subnets.public_subnet_ids)
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

  context = module.this.context
}

module "eks_workers" {
  source = "cloudposse/eks-workers/aws"
  # version = "0.19.0"

  for_each = var.eks_worker_groups

  subnet_ids   = var.private_subnet_ids
  # cluster_name = module.label.id
  cluster_name      = data.null_data_source.wait_for_cluster_and_kubernetes_configmap.outputs["cluster_name"]
  name              = var.eks_worker_groups[each.key].name
  instance_types    = var.eks_worker_groups[each.key].instance_type
  desired_size      = var.eks_worker_groups[each.key].desired_size
  min_size          = var.eks_worker_groups[each.key].min_size
  max_size          = var.eks_worker_groups[each.key].max_size
  disk_size         = var.eks_worker_groups[each.key].disk_size
  kubernetes_labels = var.kubernetes_labels

  tags = local.tags

  bootstrap_extra_args = "--use-max-pods false"
  kubelet_extra_args   = "--node-labels=purpose=ci-worker"

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
      type                     = "ingress"
      from_port                = 0
      to_port                  = 65535
      protocol                 = "-1"
      cidr_blocks              = []
      source_security_group_id = var.eks_worker_security_group_id
      description              = "Allow all inbound traffic from Security Group ID of the EKS cluster"
    }
  ]

  # Auto-scaling policies and CloudWatch metric alarms
  autoscaling_policies_enabled           = var.autoscaling_policies_enabled
  cpu_utilization_high_threshold_percent = var.cpu_utilization_high_threshold_percent
  cpu_utilization_low_threshold_percent  = var.cpu_utilization_low_threshold_percent
}

module "eks_node_group" {
  source  = "cloudposse/eks-node-group/aws"
  version = "0.19.0"

  for_each       = var.eks_node_groups
  subnet_ids     = var.private_subnet_ids
  cluster_name   = data.null_data_source.wait_for_cluster_and_kubernetes_configmap.outputs["cluster_name"]
  instance_types = var.eks_node_groups[each.key].instance_types
  desired_size   = var.eks_node_groups[each.key].desired_size
  min_size       = var.eks_node_groups[each.key].min_size
  max_size       = var.eks_node_groups[each.key].max_size
  disk_size      = var.eks_node_groups[each.key].disk_size

  kubernetes_labels = var.kubernetes_labels
  tags              = local.tags

  cluster_autoscaler_enabled = true
  context                    = module.this.context
}