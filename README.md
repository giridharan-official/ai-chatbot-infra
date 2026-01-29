# AI Chatbot Framework - AWS Production Infrastructure

**Last Updated**: January 29, 2026

---

## Overview

This repository contains infrastructure-as-code and GitOps configurations for deploying the AI Chatbot Framework to AWS.

Includes:
- Terraform infrastructure (EKS, VPC, ECR, security groups)
- Helm charts for all components
- ArgoCD GitOps configuration
- GitHub Actions CI/CD pipelines

---

## Quick Start

### Prerequisites

Required tools:
- Terraform >= 1.5.0
- Helm >= 3.10
- kubectl >= 1.29
- AWS CLI v2
- Git

### Deploy in 5 Steps
```bash
# 1. Clone repository
git clone https://github.com/giridharan-official/ai-chatbot-infra.git
cd ai-chatbot-infra

# 2. Configure AWS credentials
aws configure
export AWS_REGION=ap-south-1

# 3. Initialize Terraform
cd terraform
terraform init
terraform plan
terraform apply

# 4. Deploy Kubernetes resources
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

kubectl apply -f k8s/namespaces.yaml
helm install ai-chatbot ./helm/ai-chatbot \
  -f gitops/dev/values.yaml \
  -n dev

# 5. Deploy ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
kubectl apply -f argocd-bootstrap/

# Access ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

---

## Architecture
```
GitHub Repository
    |
    v
GitHub Actions CI (builds images)
    |
    v
AWS ECR (stores images)
    |
    v
ArgoCD (GitOps controller)
    |
    +-- Dev EKS Cluster
    +-- Staging EKS Cluster
    +-- Production EKS Cluster
```

---

## Repository Structure
```
ai-chatbot-infra/
├── terraform/              # Infrastructure code
│   ├── eks/               # EKS cluster
│   ├── vpc/               # Network
│   └── main.tf
│
├── helm/                  # Kubernetes charts
│   └── ai-chatbot/        # Parent chart
│       └── charts/        # Subcharts (backend, frontend, ml, worker)
│
├── gitops/                # ArgoCD configurations
│   ├── app-of-apps/       # Root application
│   ├── dev/               # Dev environment
│   ├── staging/           # Staging environment
│   └── prod/              # Production environment
│
├── .github/workflows/     # CI/CD pipelines
│   ├── ci-backend.yaml
│   └── ci-frontend.yaml
│
└── docs/                  # Documentation
    ├── 01-ARCHITECTURE.md
    ├── 02-AWS-ACCOUNT-STRUCTURE.md
    ├── 03-KUBERNETES.md
    ├── 04-GITOPS.md
    └── 05-OBSERVABILITY.md
```

---

## Deployment Workflow

Development:
1. Developer pushes code
2. GitHub Actions builds Docker image
3. Image pushed to ECR
4. gitops/dev/values.yaml updated with new image tag
5. ArgoCD detects change within 3 minutes
6. ArgoCD automatically syncs to dev namespace
7. Pods restart with new image

Production:
1. Release manager creates version tag (v1.0.0)
2. GitHub Actions builds and tags image
3. gitops/prod/values.yaml manually updated
4. Pull request reviewed and merged
5. ArgoCD detects change
6. Release manager manually clicks "Sync" in ArgoCD UI
7. Production deployment begins

---

## Environments

Development:
- Backend: 1 replica
- Frontend: 1 replica
- MongoDB: 5Gi storage
- Auto-scaling: Disabled

Staging:
- Backend: 2-4 replicas with auto-scaling
- Frontend: 2-4 replicas with auto-scaling
- MongoDB: 10Gi storage
- Auto-scaling: Enabled

Production:
- Backend: 3-10 replicas with auto-scaling
- Frontend: 3-10 replicas with auto-scaling
- MongoDB: 100Gi storage
- Auto-scaling: Enabled

---

## Infrastructure Cost

| Component | Cost/Month |
|-----------|-----------|
| EKS (3 clusters) | $250 |
| MongoDB Atlas | $285 |
| ElastiCache Redis | $130 |
| SQS | < $1 |
| S3 | < $5 |
| CloudWatch | $20-30 |
| **Total** | **~$700/month** |

---

## Security

- VPC with private subnets
- IAM roles for pods (IRSA)
- ECR image scanning
- CloudTrail audit logging
- GuardDuty threat detection
- Secrets in AWS Secrets Manager

---

## Troubleshooting

Check pod status:
```bash
kubectl get pods -n dev
kubectl describe pod <pod-name> -n dev
kubectl logs -n dev -l app=backend
```

Check ArgoCD:
```bash
kubectl get applications -n argocd
kubectl describe application ai-chatbot-dev -n argocd
```

Check ECR images:
```bash
aws ecr describe-images --repository-name backend --region ap-south-1
```

---

## Contributing

1. Create branch: `git checkout -b feature/your-feature`
2. Commit: `git commit -am 'Add feature'`
3. Push: `git push origin feature/your-feature`
4. Create pull request

Code validation:
- `terraform validate`
- `helm lint`
- `kubectl --dry-run`

---

## License

MIT License

