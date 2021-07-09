provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
      command     = "aws"
    }
  }
}

resource "null_resource" "kubectl_update" {
  depends_on = [
    module.eks,
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "aws eks --region $AWS_REGION update-kubeconfig --name $NAME"
    environment = {
      AWS_REGION = var.region
      NAME       = local.cluster_name
    }
  }
}

resource "helm_release" "cluster_autoscaler" {
  depends_on = [
    module.eks,
    null_resource.kubectl_update
  ]

  name      = "cluster-autoscaler"
  namespace = "kube-system"

  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "autoscaler"

  # awsRegion: us-west-2

  # rbac:
  #   create: true
  #   serviceAccount:
  #     # This value should match local.k8s_service_account_name in locals.tf
  #     name: cluster-autoscaler-aws-cluster-autoscaler-chart
  #     annotations:
  #       # This value should match the ARN of the role created by module.iam_assumable_role_admin in irsa.tf
  #       eks.amazonaws.com/role-arn: "arn:aws:iam::<ACCOUNT ID>:role/cluster-autoscaler"

  # autoDiscovery:
  #   clusterName: test-eks-irsa
  #   enabled: true

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = local.k8s_service_account_name
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cluster-autoscaler"
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = local.cluster_name
  }

  set {
    name  = "autoDiscovery.enabled"
    value = "true"
  }

  set {
    name = "image.repository"
    value = "us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler"
  }

  set {
    name = "image.tag"
    value = "v${var.kubernetes_version}"
  }
}
