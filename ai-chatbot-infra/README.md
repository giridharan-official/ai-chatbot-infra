# AI Chatbot Framework - AWS Production Infrastructure

**Status**: ✅ Production Ready  
**Last Updated**: January 29, 2026  
**Deployment Environment**: AWS EKS, ArgoCD, Terraform  

---

## 📖 Overview

This repository contains infrastructure-as-code (IaC) and GitOps configurations for deploying the AI Chatbot Framework to AWS in a production-ready manner.

### What's Included

- **Terraform**: EKS cluster, VPC, ECR, networking, security groups, monitoring
- **Helm Charts**: Microservices deployment with environment-specific configurations
- **GitOps**: ArgoCD application manifests and sync policies for dev/staging/prod
- **CI/CD**: GitHub Actions workflows for automated builds and deployments
- **Observability**: CloudWatch, metrics, logging, and alerting

---

## 🚀 Quick Start

### Prerequisites
```bash
# Required tools
- Terraform >= 1.5.0
- Helm >= 3.10
- kubectl >= 1.29
- AWS CLI v2
- Git
- Docker (for local testing)

# AWS Requirements
- AWS Account with IAM permissions
- VPC and subnets already created (or use terraform to create)
- ECR repositories created
```

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
# Open http://localhost:8080
```

---

## 📊 Architecture Overview
```
┌─────────────────────────────────────────────────────┐
│                   GitHub Repository                 │
│  (ai-chatbot-framework + ai-chatbot-infra)         │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
        ┌────────────────────┐
        │  GitHub Actions CI │
        │  - Build Docker    │
        │  - Push to ECR     │
        │  - Update GitOps   │
        └────────┬───────────┘
                 │
                 ▼
        ┌─────────────────────────────────────┐
        │  AWS ECR (Container Registry)       │
        │  - backend:latest                   │
        │  - frontend:latest                  │
        │  - ml:latest                        │
        └────────┬───────────────────────────┘
                 │
                 ▼
    ┌────────────────────────────────────────┐
    │  ArgoCD (GitOps Controller)            │
    │  - Watches git repo for changes        │
    │  - Syncs to Kubernetes                 │
    │  - Manages 3 environments              │
    └────────┬───────────────────────────────┘
             │
    ┌────────┴──────────────┬──────────────┬──────────────┐
    ▼                       ▼              ▼              ▼
┌────────┐           ┌────────────┐  ┌────────────┐  ┌────────────┐
│  DEV   │           │  STAGING   │  │   PROD     │  │  SECURITY  │
│ EKS    │           │ EKS        │  │ EKS        │  │ Monitoring │
│        │           │            │  │            │  │            │
└────────┘           └────────────┘  └────────────┘  └────────────┘
```

---

## 📁 Repository Structure
```
ai-chatbot-infra/
├── terraform/                      # Infrastructure as Code
│   ├── main.tf
│   ├── eks/                       # EKS cluster configuration
│   ├── vpc/                       # Network configuration
│   ├── ecr.tf                     # Container registry
│   ├── security-groups.tf
│   └── outputs.tf
│
├── helm/                          # Kubernetes Helm Charts
│   └── ai-chatbot/                # Parent chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── templates/
│       └── charts/                # Subcharts
│           ├── backend/
│           ├── frontend/
│           ├── ml/
│           └── worker/
│
├── gitops/                        # GitOps configurations
│   ├── app-of-apps/
│   │   ├── argocd-root-app.yaml
│   │   └── argocd-env-apps.yaml
│   │
│   ├── dev/
│   │   ├── chatbot.yaml           # Dev environment
│   │   └── values.yaml
│   │
│   ├── staging/
│   │   ├── chatbot.yaml
│   │   └── values.yaml
│   │
│   └── prod/
│       ├── chatbot.yaml
│       └── values.yaml
│
├── .github/workflows/             # CI/CD pipelines
│   ├── ci-backend.yaml
│   ├── ci-frontend.yaml
│   ├── ci-ml.yaml
│   └── ci-worker.yaml
│
├── docs/                          # Documentation
│   ├── 01-ARCHITECTURE.md
│   ├── 02-AWS-ACCOUNT-STRUCTURE.md
│   ├── 03-KUBERNETES.md
│   ├── 04-GITOPS.md
│   ├── 05-OBSERVABILITY.md
│   └── 06-DEPLOYMENT-GUIDE.md
│
└── README.md                      # This file
```

---

## 🔐 Security Highlights

- ✅ VPC with private subnets for workloads
- ✅ IAM roles and IRSA for pod authentication
- ✅ ECR image scanning enabled
- ✅ Secrets stored in AWS Secrets Manager
- ✅ TLS encryption for all communications
- ✅ Network policies for pod-to-pod communication
- ✅ CloudTrail logging for audit trails
- ✅ Security Hub for compliance monitoring

---

## 📈 Scaling Configuration

### Dev Environment
- Backend: 1 replica, 250m CPU, 512Mi RAM
- Frontend: 1 replica, 100m CPU, 256Mi RAM
- MongoDB: 5Gi storage
- Auto-scaling: Disabled

### Staging Environment
- Backend: 2-4 replicas with autoscaling (70% CPU threshold)
- Frontend: 2-4 replicas with autoscaling
- MongoDB: 10Gi storage
- Auto-scaling: Enabled

### Production Environment
- Backend: 3-10 replicas with autoscaling
- Frontend: 3-10 replicas with autoscaling
- MongoDB: 100Gi storage with backup
- ML Service: GPU-enabled nodes (g4dn.xlarge)
- Auto-scaling: Enabled with reserved capacity

---

## 🛠️ Deployment Workflow

### Development
```
1. Developer pushes code to main branch
2. GitHub Actions CI triggers automatically
3. Docker images built and pushed to ECR
4. gitops/dev/values.yaml updated with new image tags
5. ArgoCD detects change (every 3 minutes)
6. ArgoCD syncs to dev namespace automatically
7. Pods restart with new images
8. Health checks verify deployment
```

### Production
```
1. Release manager creates version tag (v1.0.0)
2. Same CI/CD pipeline runs
3. Image tagged as v1.0.0 (not latest)
4. gitops/prod/values.yaml manually updated
5. Release PR created for review
6. After approval, merged to main
7. ArgoCD detects change
8. Release manager clicks "Sync" in ArgoCD UI (manual)
9. Production deployment begins with canary strategy
```

---

## 📊 Monitoring & Alerting

- **CloudWatch**: Container metrics, logs, custom metrics
- **CloudWatch Alarms**: CPU, memory, error rates
- **X-Ray**: Distributed tracing (optional)
- **SNS**: Alert notifications to ops team

---

## 🔍 Troubleshooting

### Pod Not Starting?
```bash
# Check pod status
kubectl get pods -n dev
kubectl describe pod <pod-name> -n dev

# View logs
kubectl logs -n dev -l app=backend
kubectl logs -n dev -l app=backend --previous  # If crashed

# Check events
kubectl get events -n dev
```

### ArgoCD Sync Issues?
```bash
# Check application status
kubectl get applications -n argocd

# View detailed status
kubectl describe application ai-chatbot-dev -n argocd

# Force refresh
kubectl patch application ai-chatbot-dev -n argocd \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type merge
```

### Image Pull Errors?
```bash
# Verify ECR credentials
kubectl get secrets -n dev ecr-registry-secret

# Check image exists
aws ecr describe-images --repository-name backend --region ap-south-1

# Verify image URL in deployment
kubectl get deployment ai-chatbot-backend -n dev -o yaml | grep image:
```

---

## 📚 Documentation

For detailed information, see:

- **[Architecture Design](docs/01-ARCHITECTURE.md)** - Service recommendations and cost analysis
- **[AWS Account Structure](docs/02-AWS-ACCOUNT-STRUCTURE.md)** - Multi-account strategy and security
- **[Kubernetes Infrastructure](docs/03-KUBERNETES.md)** - EKS cluster design and networking
- **[GitOps Strategy](docs/04-GITOPS.md)** - ArgoCD configuration and deployment patterns
- **[Observability](docs/05-OBSERVABILITY.md)** - Monitoring, logging, and alerting
- **[Deployment Guide](docs/06-DEPLOYMENT-GUIDE.md)** - Step-by-step deployment instructions

---

## 📋 Assumptions & Limitations

See [ASSUMPTIONS.md](ASSUMPTIONS.md) for:
- Known limitations
- Assumptions made during design
- Future improvements
- Cost considerations

---

## 👥 Contributing

1. Create feature branch: `git checkout -b feature/your-feature`
2. Commit changes: `git commit -am 'Add feature'`
3. Push to branch: `git push origin feature/your-feature`
4. Create Pull Request

All code must pass:
- `terraform validate`
- `helm lint`
- `kubectl --dry-run`

---

## 📄 License

MIT License - See LICENSE file

---

## ✅ Verification Checklist

- [ ] Terraform initialized and validated
- [ ] EKS cluster created and healthy
- [ ] ArgoCD installed and accessible
- [ ] Dev environment synced and pods running
- [ ] Staging environment synced and pods running
- [ ] Production environment synced (manual)
- [ ] Monitoring and alerting configured
- [ ] Backup strategy verified
- [ ] Security scanning enabled
- [ ] Documentation complete

---

**Questions?** Create an issue in the repository or check the detailed documentation in the `docs/` folder.

