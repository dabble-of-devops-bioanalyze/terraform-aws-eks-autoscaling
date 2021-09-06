
#k8s_service_account_namespace = "kube-system"
#k8s_service_account_name      = "cluster-autoscaler-aws-cluster-autoscaler"

cloudProvider: aws
awsRegion: ${region} 

rbac:
  create: true
  serviceAccount:
    # This value should match local.k8s_service_account_name in locals.tf
    name: "${service_account_name}"
    annotations:
      # This value should match the ARN of the role created by module.iam_assumable_role_admin in irsa.tf
      eks.amazonaws.com/role-arn: "${role_arn}"


autoDiscovery:
  clusterName: "${cluster_name}"
  enabled: true