data "aws_caller_identity" "current" {}

data "aws_iam_policy" "ebs_csi" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role" "ebs_csi_irsa" {
  name = "${var.cluster_name}-ebs-csi-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.oidc_provider, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_attach" {
  role       = aws_iam_role.ebs_csi_irsa.name
  policy_arn = data.aws_iam_policy.ebs_csi.arn
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.3"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  cluster_endpoint_public_access = true
  enable_irsa = true

  # --------------------------------------------------
  # kubectl admin access (EKS Access API)
  # --------------------------------------------------
  access_entries = {
    admin = {
      principal_arn = data.aws_caller_identity.current.arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # --------------------------------------------------
  # Managed Node Groups
  # --------------------------------------------------
  eks_managed_node_groups = {

    general = {
      name = "general-ng"

      instance_types = ["t3.medium"]

      min_size     = 2
      max_size     = 5
      desired_size = 2

      labels = {
        workload = "general"
      }

      tags = {
        NodeGroup = "general"
      }
    }

    ml = {
      name = "ml-ng"

      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 1

      labels = {
        workload = "ml"
      }

      tags = {
        NodeGroup = "ml"
      }
    }
  }

  # --------------------------------------------------
  # EKS Managed Add-ons
  # --------------------------------------------------
  cluster_addons = {
    vpc-cni = {
      most_recent = true
    }

    kube-proxy = {
      most_recent = true
    }

    coredns = {
      most_recent = true
    }

    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = aws_iam_role.ebs_csi_irsa.arn
    }
  }

  tags = {
    Project = var.project_name
  }
}
