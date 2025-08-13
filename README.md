# Default Terraform EKS Configuration

A clean, production-ready Terraform configuration for deploying AWS EKS clusters with high-performance gp3 storage.

Features

- EKS Cluster: Kubernetes 1.32 with modern configuration
- Auto Scaling: 2-3 node cluster with t3a.medium instances
- High Performance Storage: gp3 volumes with 3000 IOPS and 125 MB/s throughput
- Security: Encrypted EBS volumes and proper IAM roles
- Cost Optimized: Uses gp3 storage (20% cheaper than gp2)

Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- kubectl installed
- IAM roles pre-created:
  - `onprem-eks-cluster-iam-role` (EKS cluster role)
  - `AmazonEKSNodeRole` (Node group role)

Quick Start

1. Clone the Repository
```bash
git clone https://github.com/Anujramola1999/default-terraform-code.git
cd default-terraform-code/terraform-eks
```

2. Initialize Terraform
```bash
terraform init
```

3. Review and Customize Configuration
Edit `main.tf` to customize:
- Cluster name (currently: `frank-kyverno-test`)
- AWS region (currently: `us-west-1`)
- AWS profile (currently: `devtest-sso`)
- Instance types, scaling configuration, etc.

4. Deploy the Cluster
```bash
terraform plan
terraform apply
```

5. Configure kubectl
```bash
aws eks update-kubeconfig --name frank-kyverno-test --profile devtest-sso --region us-west-1
```

6. Apply gp3 Storage Class
```bash
kubectl apply -f gp3-storageclass.yaml
```

Converting from gp2 to gp3 Storage

If you have an existing EKS cluster with gp2 storage, follow these steps to upgrade to gp3:

Step 1: Check Current Storage Classes
```bash
kubectl get storageclass
```

You should see something like:
```
NAME   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2    kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  10m
```

Step 2: Apply the gp3 Storage Class
```bash
kubectl apply -f gp3-storageclass.yaml
```

Step 3: Verify gp3 is Now Default
```bash
kubectl get storageclass
```

You should now see:
```
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  10m
gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   true                   30s
```

Step 4: Remove Default from gp2 (Optional)
```bash
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

Step 5: Verify Configuration
```bash
kubectl describe storageclass gp3
```

gp3 vs gp2 Comparison

| Feature | gp2 | gp3 |
|---------|-----|-----|
| Baseline IOPS | 3 IOPS/GB (min 100) | 3,000 IOPS |
| Max IOPS | 16,000 | 16,000 |
| Baseline Throughput | Varies by size | 125 MB/s |
| Max Throughput | 250 MB/s | 1,000 MB/s |
| Cost | Higher | ~20% cheaper |
| Provisioner | kubernetes.io/aws-ebs | ebs.csi.aws.com |
| Volume Expansion | Limited | Supported |

Architecture

```
┌─────────────────────────────────────────┐
│                AWS EKS                  │
├─────────────────────────────────────────┤
│  Cluster: frank-kyverno-test            │
│  Version: 1.32                          │
│  Nodes: 2-3 (t3a.medium)               │
│  Storage: gp3 (3000 IOPS, 125 MB/s)    │
│  Volumes: 25GB encrypted               │
└─────────────────────────────────────────┘
```

File Structure

```
terraform-eks/
├── main.tf                    # Complete EKS configuration
└── gp3-storageclass.yaml     # High-performance storage class
```

Configuration Details

Cluster Configuration
- Name: `frank-kyverno-test`
- Version: Kubernetes 1.32
- Authentication: API_AND_CONFIG_MAP mode
- Networking: Default VPC with public/private endpoint access

Node Group Configuration
- Instance Type: t3a.medium
- Capacity: ON_DEMAND
- Scaling: Min=2, Desired=2, Max=3
- AMI: AL2_x86_64

Storage Configuration
- Volume Type: gp3
- Volume Size: 25GB
- IOPS: 3,000
- Throughput: 125 MB/s
- Encryption: Enabled

Customization

Change Cluster Name
1. Update the `name` field in the `aws_eks_cluster` resource
2. Update all related tags and resource names
3. Update the kubeconfig command in outputs

Modify Scaling
```hcl
scaling_config {
  desired_size = 3    # Change desired number of nodes
  max_size     = 5    # Change maximum nodes
  min_size     = 2    # Change minimum nodes
}
```

Change Instance Type
```hcl
instance_types = ["t3a.large"]  # or ["m5.xlarge"], etc.
```

Cleanup

To destroy the cluster and all resources:
```bash
terraform destroy
```

Troubleshooting

Common Issues

1. IAM Role Not Found
   - Ensure the IAM roles exist in your AWS account
   - Update the role ARNs in `main.tf`

2. Storage Class Not Default
   - Run the gp2 patch command to remove old default
   - Verify with `kubectl get storageclass`

3. Node Group Creation Fails
   - Check subnet availability
   - Verify node group IAM role permissions

Useful Commands

```bash
# Check cluster status
kubectl get nodes

# Check storage classes
kubectl get storageclass

# Check cluster info
kubectl cluster-info

# View cluster events
kubectl get events --sort-by=.metadata.creationTimestamp
```

License



