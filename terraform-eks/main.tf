terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Local values for computed names and tags
locals {
  cluster_name          = var.cluster_name
  node_group_name       = "${var.cluster_name}-workers"
  launch_template_name  = "${var.cluster_name}-workers"
  
  # Merge common tags with additional tags
  common_tags = merge(
    var.common_tags,
    var.additional_tags,
    {
      ClusterName = var.cluster_name
    }
  )
  
  # Node group tags
  node_tags = merge(
    local.common_tags,
    {
      Name = local.node_group_name
    }
  )
  
  # Cluster tags
  cluster_tags = merge(
    local.common_tags,
    {
      Name = local.cluster_name
    }
  )
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

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = var.cluster_service_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = data.aws_subnets.default.ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = local.cluster_tags
}

# Launch template for node group
resource "aws_launch_template" "workers" {
  name_prefix = "${local.launch_template_name}-"

  vpc_security_group_ids = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.node_disk_size
      volume_type = var.node_disk_type
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.node_tags
  }
}

# EKS Node Group
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = local.node_group_name
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = data.aws_subnets.default.ids

  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types
  ami_type       = var.node_ami_type

  launch_template {
    id      = aws_launch_template.workers.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_eks_cluster.main]

  tags = local.node_tags
}

# Outputs
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = aws_eks_cluster.main.name
}

output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "node_group_arn" {
  description = "EKS node group ARN"
  value       = aws_eks_node_group.workers.arn
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value = var.aws_profile != null ? "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --profile ${var.aws_profile} --region ${var.aws_region}" : "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
} 