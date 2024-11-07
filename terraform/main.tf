provider "aws" {
  region = var.aws_region
}

# VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block = var.vpc_cidr
}

# Subnets
resource "aws_subnet" "eks_subnets" {
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

data "aws_availability_zones" "available" {}

# EKS Cluster
resource "aws_eks_cluster" "atlantis_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.eks_subnets[*].id
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Worker Node Group IAM Role
resource "aws_iam_role" "eks_worker_role" {
  name = "${var.cluster_name}-worker-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_policy" {
  role       = aws_iam_role.eks_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# IAM Instance Profile for Worker Nodes
resource "aws_iam_instance_profile" "eks_worker_instance_profile" {
  name = "${var.cluster_name}-worker-instance-profile"
  role = aws_iam_role.eks_worker_role.name
}

# Launch Template for Worker Nodes
resource "aws_launch_template" "eks_worker_launch_template" {
  name_prefix   = "${var.cluster_name}-worker-template"
  image_id      = data.aws_ami.eks_worker.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.eks_worker_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
  }
}

# Worker Autoscaling Group
resource "aws_autoscaling_group" "eks_worker_asg" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.eks_subnets[*].id
  launch_template {
    id      = aws_launch_template.eks_worker_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "kubernetes.io/cluster/${aws_eks_cluster.atlantis_cluster.name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

data "aws_ami" "eks_worker" {
  most_recent = true
  owners      = ["602401143452"]  # Amazon EKS AMI account ID
  filter {
    name   = "name"
    values = ["amazon-eks-node-*"]
  }
}

# IAM Role for EKS Admin
resource "aws_iam_role" "eks_admin_role" {
  name = "${var.cluster_name}-eks-admin-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::288761741470:root"  # Replace with your AWS account ID
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_admin_policy_attachment" {
  role       = aws_iam_role.eks_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM Role for EKS Read-Only
resource "aws_iam_role" "eks_readonly_role" {
  name = "${var.cluster_name}-eks-readonly-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::288761741470:root"  # Replace with your AWS account ID
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_readonly_policy_attachment" {
  role       = aws_iam_role.eks_readonly_role.name
  policy_arn = aws_iam_policy.custom_eks_readonly_policy.arn
}

# Custom EKS Read-Only Policy
resource "aws_iam_policy" "custom_eks_readonly_policy" {
  name        = "${var.cluster_name}-eks-read-only-policy"
  description = "Custom EKS Read-Only Policy with permissions similar to AmazonEKSReadOnlyPolicy"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "eks:ListUpdates",
          "eks:DescribeUpdate"
        ],
        Resource = "*"
      }
    ]
  })
}
resource "aws_eks_node_group" "atlantis_worker_nodes" {
  cluster_name    = aws_eks_cluster.atlantis_cluster.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_worker_role.arn
  subnet_ids      = aws_subnet.eks_subnets[*].id

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types = ["t3.medium"]  # You can change this instance type based on your requirements
  ami_type       = "AL2_x86_64"  # Amazon Linux 2 AMI for EKS

  tags = {
    "Name"                                      = "${var.cluster_name}-worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}
