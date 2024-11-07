output "cluster_endpoint" {
  value = aws_eks_cluster.atlantis_cluster.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.atlantis_cluster.name
}

output "admin_role_arn" {
  value = aws_iam_role.eks_admin_role.arn
}

output "readonly_role_arn" {
  value = aws_iam_role.eks_readonly_role.arn
}
output "aws_region" {
  value = var.aws_region
}
