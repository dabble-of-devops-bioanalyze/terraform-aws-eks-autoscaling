variable "region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

# variable "availability_zones" {
#   type        = list(string)
#   description = "List of availability zones"
# }

####################################################################
# VPC 
####################################################################

variable "vpc_id" {
  type        = string
  description = "VPC ID for the cluster VPC ID"
}

# variable "private_subnet_ids" {
#   type        = list(string)
#   description = "Private Subnet Ids"
# }

# variable "public_subnet_ids" {
#   type        = list(string)
#   description = "Public Subnet Ids"
# }

variable "subnet_ids" {
  type        = list(string)
  description = "Public Subnet Ids"
}

# variable "eks_worker_security_group_id" {
#   type        = string
#   description = "Security group to allow traffic eks workers to talk to eachother sg-XXXXXXXXX"
# }

variable "kubernetes_version" {
  type        = string
  default     = "1.17"
  description = "Desired Kubernetes master version. If you do not specify a value, the latest available version is used"
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["audit"]
  description = "A list of the desired control plane logging to enable. For more information, see https://docs.aws.amazon.com/en_us/eks/latest/userguide/control-plane-logs.html. Possible values [`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`]"
}

variable "cluster_log_retention_period" {
  type        = number
  default     = 7
  description = "Number of days to retain cluster logs. Requires `enabled_cluster_log_types` to be set. See https://docs.aws.amazon.com/en_us/eks/latest/userguide/control-plane-logs.html."
}

variable "map_additional_aws_accounts" {
  description = "Additional AWS account numbers to add to `config-map-aws-auth` ConfigMap"
  type        = list(string)
  default     = []
}

variable "map_additional_iam_roles" {
  description = "Additional IAM roles to add to `config-map-aws-auth` ConfigMap"

  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))

  default = []
}

variable "map_additional_iam_users" {
  description = "Additional IAM users to add to `config-map-aws-auth` ConfigMap"

  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))

  default = []
}

variable "oidc_provider_enabled" {
  type        = bool
  default     = true
  description = "Create an IAM OIDC identity provider for the cluster, then you can create IAM roles to associate with a service account in the cluster, instead of using `kiam` or `kube2iam`. For more information, see https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html"
}

variable "local_exec_interpreter" {
  type        = list(string)
  default     = ["/bin/sh", "-c"]
  description = "shell to use for local_exec"
}

####################################################################
# EKS 
####################################################################

variable "kubernetes_labels" {
  type        = map(string)
  description = "Key-value mapping of Kubernetes labels. Only labels that are applied with the EKS API are managed by this argument. Other Kubernetes labels applied to the EKS Node Group will not be managed"
  default     = {}
}

variable "cluster_encryption_config_enabled" {
  type        = bool
  default     = true
  description = "Set to `true` to enable Cluster Encryption Configuration"
}

variable "cluster_encryption_config_kms_key_id" {
  type        = string
  default     = ""
  description = "KMS Key ID to use for cluster encryption config"
}

variable "cluster_encryption_config_kms_key_enable_key_rotation" {
  type        = bool
  default     = true
  description = "Cluster Encryption Config KMS Key Resource argument - enable kms key rotation"
}

variable "cluster_encryption_config_kms_key_deletion_window_in_days" {
  type        = number
  default     = 10
  description = "Cluster Encryption Config KMS Key Resource argument - key deletion windows in days post destruction"
}

variable "cluster_encryption_config_kms_key_policy" {
  type        = string
  default     = null
  description = "Cluster Encryption Config KMS Key Resource argument - key policy"
}

variable "cluster_encryption_config_resources" {
  type        = list(any)
  default     = ["secrets"]
  description = "Cluster Encryption Config Resources to encrypt, e.g. ['secrets']"
}

####################################################################
# EKS Worker Groups 
####################################################################

variable "autoscaling_policies_enabled" {
  type        = bool
  default     = true
  description = "Whether to create `aws_autoscaling_policy` and `aws_cloudwatch_metric_alarm` resources to control Auto Scaling"
}


variable "eks_worker_groups" {
  description = "EKS Worker Groups"
  type = list(object({
    name          = string
    instance_type = string
    desired_size  = number
    min_size      = number
    max_size      = number
  }))
  default = [
    {
      name          = "t3a_medium"
      instance_type = "t3a.medium"
      desired_size  = 1
      min_size      = 1
      max_size      = 2
    }
  ]
}

####################################################################
# EKS Node Groups 
####################################################################

variable "eks_node_groups" {
  type = list(object({
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size      = number
    name           = string
  }))
  description = "EKS Worker Groups"
  default = [
    {
      name           = "worker-group-1"
      instance_types = ["t3a.medium"]
      desired_size   = 1
      min_size       = 1
      max_size       = 2
      disk_size      = 20
    }
  ]
}
