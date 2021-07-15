output "id" {
  description = "ID of the created example"
  value       = module.this.enabled ? module.this.id : null
}

output "region" {
  description = "AWS Region of the cluster"
  value       = var.region
}

output "eks_cluster_id" {
  description = "EKS Cluster ID"
  value       = module.eks_cluster.eks_cluster_id
}

output "eks_cluster_name" {
  value = module.eks_cluster.eks_cluster_id
}

output "eks_cluster_arn" {
  value = module.eks_cluster.eks_cluster_arn
}

output "eks_cluster" {
  description = "All values from the EKS Cluster"
  value       = module.eks_cluster
}

output "eks_cluster_node_groups" {
  value = module.eks_node_group
}

output "eks_cluster_workers" {
  value = module.eks_workers
}

output "get_kubectl" {
  description = "Get your kubectl "
  value       = "aws eks get-token --cluster-name ${module.eks_cluster.eks_cluster_id}"
}