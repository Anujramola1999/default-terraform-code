terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-west-1"
  profile = "devtest-sso"
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Simple EKS Cluster
resource "aws_eks_cluster" "frank_kyverno_test" {
  name     = "frank-kyverno-test"
  role_arn = "arn:aws:iam::844333597536:role/onprem-eks-cluster-iam-role"
  version  = "1.32"

  vpc_config {
    subnet_ids              = data.aws_subnets.default.ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = {
    Name        = "frank-kyverno-test"
    Environment = "testing"
    DoNotDelete = "true"
  }
}

# Launch template for node group with gp3 volume
resource "aws_launch_template" "frank_kyverno_workers" {
  name_prefix   = "frank-kyverno-workers-"

  vpc_security_group_ids = [aws_eks_cluster.frank_kyverno_test.vpc_config[0].cluster_security_group_id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 25
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "frank-kyverno-workers"
      DoNotDelete = "true"
    }
  }
}

# Simple Node Group
resource "aws_eks_node_group" "frank_kyverno_workers" {
  cluster_name    = aws_eks_cluster.frank_kyverno_test.name
  node_group_name = "frank-kyverno-workers"
  node_role_arn   = "arn:aws:iam::844333597536:role/AmazonEKSNodeRole"
  subnet_ids      = data.aws_subnets.default.ids

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3a.medium"]
  ami_type       = "AL2_x86_64"

  launch_template {
    id      = aws_launch_template.frank_kyverno_workers.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_eks_cluster.frank_kyverno_test]

  tags = {
    Name = "frank-kyverno-workers"
    DoNotDelete = "true"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.frank_kyverno_test.endpoint
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = aws_eks_cluster.frank_kyverno_test.name
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --name frank-kyverno-test --profile devtest-sso --region us-west-1"
} 