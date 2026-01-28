module "vpc" {
  source = "./vpc"

  project_name = var.project_name
  aws_region   = var.aws_region
}


module "eks" {
  source = "./eks"

  cluster_name    = var.eks_cluster_name
  project_name    = var.project_name
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
}
