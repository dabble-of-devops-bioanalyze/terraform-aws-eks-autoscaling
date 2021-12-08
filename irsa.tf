// TODO
// I am not sure if this is needed or not
// I think the autoscaling is created through the cloudposse autoscaling policies
// https://github.com/cloudposse/terraform-aws-ec2-autoscale-group/blob/0.27.0/autoscaling.tf
// But for now we'll keep the IRSA
// Instructions are the same as in the main irsa example. We're just using a helm_resource to deploy the autoscaling charts
// https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v17.11.0/examples/irsa

locals {
  eks_cluster_oidc_issuer_url = module.eks_cluster.eks_cluster_identity_oidc_issuer
}

module "iam_assumable_role_admin" {
  source       = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version      = "3.6.0"
  create_role  = true
  role_name    = "cluster-autoscaler-${module.eks_cluster.eks_cluster_id}"
  provider_url = replace(local.eks_cluster_oidc_issuer_url, "https://", "")

  role_policy_arns = [
  aws_iam_policy.cluster_autoscaler.arn]
  oidc_fully_qualified_subjects = [
  "system:serviceaccount:${local.k8s_service_account_namespace}:${local.k8s_service_account_name}"]
}


resource "aws_iam_policy" "cluster_autoscaler" {
  name_prefix = "cluster-autoscaler-${module.eks_cluster.eks_cluster_id}"
  description = "EKS cluster-autoscaler policy for cluster ${module.eks_cluster.eks_cluster_id}"
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json
}

output "aws_iam_policy_cluster_autoscaler" {
  value = aws_iam_policy.cluster_autoscaler.arn
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "clusterAutoscalerAll"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "clusterAutoscalerOwn"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${module.eks_cluster.eks_cluster_id}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

data "template_file" "autoscaler" {
  depends_on = [
    module.eks_cluster,
    aws_iam_policy.cluster_autoscaler
  ]
  template = file("${path.module}/helm_charts/autoscaler/values.yml.tpl")
  vars = {
    region               = var.region
    current_account      = data.aws_caller_identity.current.account_id
    cluster_name         = module.eks_cluster.eks_cluster_id
    role_arn             = module.iam_assumable_role_admin.this_iam_role_arn
    service_account_name = local.k8s_service_account_name
  }
}

# helm repo add autoscaler https://kubernetes.github.io/autoscaler
#  helm install my-release autoscaler/cluster-autoscaler \
# --set 'autoDiscovery.clusterName'=<CLUSTER NAME>

resource "helm_release" "autoscaler" {
  depends_on = [
    module.eks_cluster,
    data.template_file.autoscaler
  ]
  name       = "autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.10.5"
  namespace  = "kube-system"


  values = [
    data.template_file.autoscaler.rendered
  ]
}
