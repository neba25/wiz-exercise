module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-eks"
  cluster_version = var.eks_cluster_version

  enable_cluster_creator_admin_permissions = true

  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Cluster endpoint reachable publicly for kubectl from your laptop during
  # the demo; nodes themselves stay in the private subnet per requirements.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  eks_managed_node_groups = {
    default = {
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      instance_types = ["t3.micro"]
      subnet_ids     = aws_subnet.private[*].id
    }
  }

  tags = {
    Name = "${var.project_name}-eks"
  }
}

# ECR repo to hold the app image
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}
