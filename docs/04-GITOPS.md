# Part 4: GitOps Strategy with ArgoCD


## Executive Summary

This document describes the GitOps implementation for the AI Chatbot Framework using ArgoCD. The strategy follows the App-of-Apps pattern to manage multiple environments (dev, staging, production) with declarative, Git-driven deployments.

**Key Principles**:
- Git as single source of truth
- Automatic deployment on code changes (dev/staging)
- Manual approval for production changes
- Declarative infrastructure (no manual kubectl apply)
- Audit trail of all changes via Git

---

## Section 1: What is GitOps?

### Traditional Deployment (Imperative)
```
Developer makes code changes
    ↓
CI/CD pipeline builds image
    ↓
Engineer manually:
  kubectl set image deployment/backend image=...
  OR
  helm upgrade ai-chatbot ...
    ↓
Change applied to cluster
    ↓
Problem: No audit trail, different commands by different people
         Manual mistakes possible, hard to track who changed what
```

### GitOps Deployment (Declarative)
```
Developer makes code changes
    ↓
Commits to GitHub
    ↓
GitHub Actions CI/CD:
  - Builds Docker image
  - Pushes to ECR
  - Updates gitops/dev/values.yaml with new image tag
  - Commits back to GitHub
    ↓
ArgoCD:
  - Watches GitHub repo every 3 minutes
  - Detects change in gitops/dev/values.yaml
  - Compares Git state to cluster state
  - If different: syncs (updates cluster to match Git)
    ↓
Cluster updated
    ↓
Benefit: All changes in Git with full audit trail
         Single source of truth (Git)
         Reproducible deployments
```

### GitOps Benefits

- Single Source of Truth: Git contains all deployment configuration
- Audit Trail: Every change tracked in Git history
- Rollback: Revert to any previous state with Git revert
- Disaster Recovery: Recreate cluster by running ArgoCD
- Automation: No manual kubectl commands needed
- Approval Process: PR reviews before production changes
- Consistency: Same deployment process across environments

---

## Section 2: ArgoCD Architecture

### ArgoCD Components
```
┌─────────────────────────────────────────────────────┐
│           ArgoCD in Kubernetes Cluster              │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  ArgoCD API Server                           │  │
│  │  - REST API for UI/CLI                       │  │
│  │  - Webhook receiver from GitHub              │  │
│  │  - Authentication & RBAC                     │  │
│  └──────────────────────────────────────────────┘  │
│                       ↓                             │
│  ┌──────────────────────────────────────────────┐  │
│  │  ArgoCD Application Controller                │  │
│  │  - Watches Git repository                    │  │
│  │  - Compares Git state vs cluster state       │  │
│  │  - Syncs (applies) changes to cluster        │  │
│  │  - Stores Application CRD state              │  │
│  └──────────────────────────────────────────────┘  │
│                       ↓                             │
│  ┌──────────────────────────────────────────────┐  │
│  │  ArgoCD Repository Server                    │  │
│  │  - Clones Git repository                     │  │
│  │  - Renders Helm charts                       │  │
│  │  - Generates Kubernetes manifests            │  │
│  │  - Caches manifests for performance          │  │
│  └──────────────────────────────────────────────┘  │
│                       ↓                             │
│  ┌──────────────────────────────────────────────┐  │
│  │  ArgoCD dex (Authentication)                 │  │
│  │  - OIDC provider integration                 │  │
│  │  - OAuth2 flows                              │  │
│  │  - SSO with company directory                │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
         ↓                              ↑
    Watches GitHub              Applies manifests
         ↓                              ↑
  ┌─────────────────────────────────────────────┐
  │      Kubernetes Cluster                     │
  │      (EKS)                                  │
  │      - Namespaces: dev, staging, production│
  │      - Services, Pods, ConfigMaps           │
  └─────────────────────────────────────────────┘
```

### ArgoCD Workflow
```
1. ArgoCD polls Git (every 3 minutes)
   ↓
2. Detects change in gitops/dev/values.yaml
   ↓
3. Repository Server renders Helm templates:
   helm template ai-chatbot ./helm/ai-chatbot \
     -f gitops/dev/values.yaml
   ↓
4. Generates Kubernetes manifests (YAML)
   ↓
5. Compares manifests:
   Git state (desired) vs Cluster state (actual)
   ↓
6. If different: sync required
   ↓
7. Apply sync policy:
   - Dev: auto-sync (apply immediately)
   - Prod: manual (wait for approval)
   ↓
8. For auto-sync:
   - Apply manifests to cluster
   - Update Deployment with new image tag
   - Kubernetes rolls out new pods
   ↓
9. Health check:
   - Wait for pods to become Ready
   - If successful: Application shows "Synced"
   - If failed: Application shows "OutOfSync" with error
```

---

## Section 3: App-of-Apps Pattern

### Why App-of-Apps?

Managing multiple applications in multiple environments:

Simple approach (doesn't scale):
```
User creates 7 Application CRDs manually:
  - argocd/application-dev.yaml
  - argocd/application-staging.yaml
  - argocd/application-prod.yaml
  - argocd/application-external-dns.yaml
  - argocd/application-cluster-autoscaler.yaml
  - argocd/application-monitoring.yaml
  - argocd/application-backup.yaml
  
Problem: Hard to manage, no dependencies, no ordering
```

App-of-Apps approach (scalable):
```
Single root Application:
  argocd-root-app.yaml
      ↓
  Points to gitops/app-of-apps directory
      ↓
  Contains ApplicationSet or multiple Applications
      ↓
  Each Application manages one component
      ↓
  Applications can have dependencies and sync waves
```

### Current Implementation

Root Application: `gitops/app-of-apps/argocd-root-app.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ai-chatbot-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/giridharan-official/ai-chatbot-infra.git
    targetRevision: main
    path: gitops/app-of-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Purpose:
- Entry point for all deployments
- Watches gitops/app-of-apps directory
- Creates/updates child Applications automatically

Environment Applications: `gitops/app-of-apps/argocd-env-apps.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ai-chatbot-dev
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: dev
  source:
    repoURL: https://github.com/giridharan-official/ai-chatbot-infra.git
    targetRevision: main
    path: helm/ai-chatbot
    helm:
      valueFiles:
        - ../../gitops/dev/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ai-chatbot-staging
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: staging
  source:
    repoURL: https://github.com/giridharan-official/ai-chatbot-infra.git
    targetRevision: main
    path: helm/ai-chatbot
    helm:
      valueFiles:
        - ../../gitops/staging/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: staging
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ai-chatbot-prod
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  project: prod
  source:
    repoURL: https://github.com/giridharan-official/ai-chatbot-infra.git
    targetRevision: main
    path: helm/ai-chatbot
    helm:
      valueFiles:
        - ../../gitops/prod/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    manual: {}
```

Sync Wave Ordering:
```
Sync Wave 1 (Dev):
  - Deploy to dev namespace first
  - Fastest feedback for developers
  
Sync Wave 2 (Staging):
  - Wait for dev to be healthy
  - Then deploy to staging
  - Test in staging environment
  
Sync Wave 3 (Prod):
  - Only manual sync for production
  - Requires human approval
  - No automatic deployment
```

### Sync Policies Explained

Development:
```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Sync if cluster drifts from Git
```

Behavior:
- Every Git change auto-syncs to dev
- If pod is manually deleted, it's automatically recreated
- Fast feedback loop for developers

Staging:
```yaml
syncPolicy:
  automated:
    prune: false     # Don't delete resources (safer)
    selfHeal: true   # Recreate if deleted
```

Behavior:
- Git changes auto-sync, but safer (don't delete)
- Useful for testing (manual resources stay)
- Prevent accidental data deletion

Production:
```yaml
syncPolicy:
  manual: {}         # No automatic sync
```

Behavior:
- Change detection: ArgoCD detects difference
- Status: Shows OutOfSync
- Approval: Human reviews change in UI
- Manual action: Click "Sync" button to deploy
- No automatic deployment ever

---

## Section 4: GitHub Repository Structure

### Repository Layout
```
ai-chatbot-infra/
│
├── gitops/
│   ├── app-of-apps/
│   │   ├── argocd-root-app.yaml          (root application)
│   │   └── argocd-env-apps.yaml          (dev, staging, prod)
│   │
│   ├── dev/
│   │   ├── chatbot.yaml                  (application manifest)
│   │   ├── values.yaml                   (dev-specific values)
│   │   └── nginx.yaml                    (test nginx)
│   │
│   ├── staging/
│   │   ├── chatbot.yaml
│   │   └── values.yaml                   (staging-specific values)
│   │
│   ├── prod/
│   │   ├── chatbot.yaml
│   │   └── values.yaml                   (prod-specific values)
│   │
│   └── bootstrap/                        (optional: one-time setup)
│       └── namespace.yaml
│
├── helm/
│   └── ai-chatbot/                       (parent chart)
│       ├── Chart.yaml
│       ├── values.yaml                   (default values)
│       ├── Chart.lock
│       ├── templates/
│       │   ├── configmap.yaml
│       │   ├── secrets.yaml
│       │   ├── ingress.yaml
│       │   └── mongodb-configmap.yaml
│       │
│       └── charts/
│           ├── backend/
│           ├── frontend/
│           ├── ml/
│           └── worker/
│
├── .github/workflows/
│   ├── ci-backend.yaml                   (build backend image)
│   ├── ci-frontend.yaml                  (build frontend image)
│   ├── ci-ml.yaml                        (build ml image)
│   └── ci-worker.yaml                    (build worker image)
│
└── docs/
    └── 04-GITOPS.md                      (this file)
```

### Key Files and Their Purposes

**argocd-root-app.yaml** (entry point):
- Single application that manages all others
- Points to gitops/app-of-apps
- Automatically creates dev/staging/prod applications

**argocd-env-apps.yaml** (environment applications):
- Defines three applications: dev, staging, production
- Each points to helm/ai-chatbot with environment-specific values
- Specifies sync policies (auto vs manual)

**gitops/dev/values.yaml** (dev configuration):
- Minimal resources (1 replica, small instances)
- Image tags: latest (auto-updates from CI)
- MongoDB enabled (small instance)
- Auto-sync enabled (fast feedback)

**gitops/staging/values.yaml** (staging configuration):
- Medium resources (2 replicas)
- Image tags: latest (auto-updates from CI)
- MongoDB M20 (20GB)
- Auto-sync enabled (test new features)

**gitops/prod/values.yaml** (production configuration):
- High resources (3+ replicas with autoscaling)
- Image tags: v1.0.0 (semantic versioning, manual)
- MongoDB M30+ (100GB+)
- Manual sync (requires approval)

---

## Section 5: CI/CD Integration

### GitHub Actions Workflow

Each service (backend, frontend, ml, worker) has a CI workflow.

Example: `.github/workflows/ci-backend.yaml`
```yaml
name: Backend CI

on:
  push:
    branches: [main]
    paths:
      - 'app/**'           # Only trigger on code changes
      - 'requirements.txt'
      - 'Dockerfile'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::ACCOUNT:role/GitHubActionsRole
          aws-region: ap-south-1
      
      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build and push Docker image
        id: image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: backend
          IMAGE_TAG: ${{ github.sha }}  # Use commit SHA as tag
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT
      
      - name: Update image tag in GitOps repo
        run: |
          git config user.name "CI Bot"
          git config user.email "ci@example.com"
          
          # Update dev values
          sed -i "s|tag: latest|tag: ${{ github.sha }}|g" \
            gitops/dev/values.yaml
          
          git add gitops/dev/values.yaml
          git commit -m "ci: update backend image to ${{ github.sha }}"
          git push origin main
```

Workflow Steps:
1. Code pushed to main branch
2. GitHub Actions checks if backend code changed
3. If yes: builds Docker image
4. Tags image with commit SHA: backend:abc123def
5. Pushes to ECR: 235494787667.dkr.ecr.ap-south-1.amazonaws.com/backend:abc123def
6. Updates gitops/dev/values.yaml with new tag
7. Commits back to GitHub
8. ArgoCD detects change (3 min later)
9. ArgoCD syncs (updates Deployment with new image)
10. Kubernetes rolls out new pods

### Image Tagging Strategy

Development:
```
Image tag: abc123def (commit SHA)
Deployed: Automatically to dev
Sync: Within 3 minutes
Rollback: git revert, push again
```

Staging:
```
Image tag: abc123def (same as dev, auto-updated)
Deployed: Automatically after dev succeeds
Sync: Within 6 minutes (after dev sync wave)
Test: Run integration tests
```

Production:
```
Image tag: v1.0.0 (semantic version)
Deployed: Manually approved
Sync: When release manager clicks "Sync" in ArgoCD UI
Promotion: Tag main branch with v1.0.0 release tag
Rollback: Revert to previous version tag (v0.9.5)
```

Release Process:
```
1. Test in staging with latest code
   
2. QA approves "ready for production"
   
3. Release manager creates release:
   - Tag main branch: git tag v1.0.0
   - Push tag: git push origin v1.0.0
   
4. GitHub Actions triggered by tag:
   - Builds image
   - Tags as v1.0.0 in ECR
   - Creates release notes
   
5. Release manager updates gitops/prod/values.yaml:
   - backend:
     tag: v1.0.0  # Changed from latest
   
6. Creates PR for review
   - Other release managers review
   - Approval required
   
7. After approval, merge to main
   
8. ArgoCD detects change
   - Shows as OutOfSync (not auto-synced)
   
9. Release manager in ArgoCD UI:
   - Views proposed changes
   - Clicks "Sync" button
   
10. Deployment starts:
    - Old backend pods: 3 running
    - New backend pods: 1 created
    - Health check passed: 2 running
    - Continue: 3 new pods running
    - Old pods: 0 running
    - Rollout complete (30-60 seconds)
    
11. Monitor metrics:
    - Error rate: should remain < 0.1%
    - Latency: should not increase
    - If issues: manually revert tag, sync again
```

---

## Section 6: Deployment Workflow Examples

### Scenario 1: Developer Fixes Bug in Backend
```
1. Developer creates branch: git checkout -b fix/conversation-memory
   
2. Modifies: app/dialogue_manager.py
   
3. Commits: git commit -m "fix: improve conversation memory"
   
4. Creates PR, gets reviewed and approved
   
5. Merges to main: git merge fix/conversation-memory
   
6. GitHub Actions detects:
   - Path changed: app/**
   - Trigger: CI backend workflow
   
7. CI workflow:
   - Checks out code at commit 7a8b9c0
   - Builds Docker image
   - Tests pass (docker build succeeds)
   - Pushes as: backend:7a8b9c0
   
8. Updates gitops/dev/values.yaml:
   - backend:
     tag: 7a8b9c0  (changed from previous commit)
   
9. ArgoCD polls (3-minute interval):
   - Detects gitops/dev/values.yaml changed
   - Renders Helm templates
   - Gets new manifest with backend:7a8b9c0
   
10. Syncs to dev:
    - Kubernetes applies new Deployment
    - New image: 235494787667.dkr.ecr.ap-south-1.amazonaws.com/backend:7a8b9c0
    - Old pods: 1 running (single dev pod)
    - New pod: 1 created
    - Readiness probe: passes
    - Old pod: terminated
    - New pod: 1 running
    
11. Developer tests:
    - Port-forward: kubectl port-forward -n dev svc/backend 8000:80
    - Tests: curl http://localhost:8000/health/live
    - Verifies bug is fixed
    
12. Staging auto-syncs (sync wave 2):
    - Same process, 2 replicas
    - Zero downtime rolling update
    
13. Production:
    - Shows OutOfSync (manual sync)
    - Release manager reviews when ready for release
```

### Scenario 2: Production Incident
```
1. Alert triggers: High error rate in production
   
2. On-call engineer:
   - Checks ArgoCD UI
   - Sees backend:v1.0.0 deployed
   - Checks logs: Pod crashing
   
3. Root cause: New dependency not installed
   
4. Immediate rollback:
   - Find previous stable version: git log
   - v0.9.5 was last stable
   
5. Rollback steps:
   a. Edit gitops/prod/values.yaml:
      backend:
        tag: v0.9.5  (changed from v1.0.0)
   
   b. Commit: git commit -m "revert: backend v1.0.0, restore v0.9.5"
   
   c. Push: git push origin main
   
   d. ArgoCD detects change
   
   e. Click "Sync" in ArgoCD UI
   
6. Deployment:
   - Old backend pods: 3 running v1.0.0
   - New backend pods: 3 starting v0.9.5
   - Health checks: all pass
   - Old pods: 0 running
   - Time to rollback: 30-60 seconds
   
7. Verify:
   - Error rate: back to normal
   - User impact: minimized to 1-2 minutes
   
8. Post-incident:
   - Root cause: Missing dependency
   - Fix: Update requirements.txt, test in staging
   - Release v0.9.6 with fix
   - Deploy v0.9.6 to production
```

### Scenario 3: Scheduled Maintenance
```
1. Operations team plans MongoDB upgrade
   
2. Pre-maintenance:
   - Backup database: aws s3 sync s3://prod-backups/
   - Notify users: "Maintenance window 2-3 AM UTC"
   
3. During maintenance:
   a. Edit gitops/prod/values.yaml:
      mongodb:
        enabled: false  # Disable MongoDB chart
      externalMongo:
        enabled: true   # Use external MongoDB (Atlas)
   
   b. Commit and push changes
   
   c. ArgoCD detects change (manual sync setup)
      - Shows: "MongoDB replicas scaled to 0"
      - Status: OutOfSync
   
   d. On-call confirms:
      - External MongoDB is healthy
      - All connections work
   
   e. Clicks "Sync" in ArgoCD UI
   
   f. Kubernetes scales MongoDB pods to 0
      - Pods drain gracefully
      - External MongoDB takes over
   
4. Perform upgrade:
   - MongoDB Atlas dashboard
   - Upgrade from 6.0 to 7.0
   - Takes 15-20 minutes
   - Automatic failover (no manual intervention)
   
5. Post-upgrade:
   a. Verify external MongoDB working
   
   b. If rolling back:
      - Edit gitops/prod/values.yaml:
        mongodb:
          enabled: true
        externalMongo:
          enabled: false
      
      - Push changes
      - ArgoCD syncs
      - In-cluster MongoDB starts
   
6. Close maintenance:
   - Notify users: "Maintenance complete"
   - Monitor metrics for 1 hour
```

---

## Section 7: ArgoCD Configuration

### ArgoCD Helm Values

Location: `argocd-values.yaml`
```yaml
global:
  image:
    tag: v2.10.4

# API Server (UI and REST API)
server:
  replicas: 2  # High availability
  extraArgs:
    - --insecure  # HTTP (behind ALB with HTTPS)
  
  # Ingress configuration
  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    hosts:
      - argocd.example.com

# Application Controller (sync engine)
controller:
  replicas: 1

# Repository Server (Git polling, Helm rendering)
repoServer:
  replicas: 2
  copyutil:
    enabled: false

# ApplicationSet Controller (create apps from templates)
applicationSet:
  replicas: 1

# Notifications
notifications:
  enabled: true
  # Integrate with Slack/email

# Disable features not needed
dex:
  enabled: false  # Using OAuth from GitHub instead

redis:
  enabled: false  # Use RDS or external Redis

redis-ha:
  enabled: false
```

### RBAC Configuration

Grant teams access to specific namespaces:
```yaml
# argocd-rbac-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:viewer  # Everyone can view by default
  
  policy.csv: |
    # Developers: Can sync dev and staging
    p, developers, applications, sync, dev/*, allow
    p, developers, applications, sync, staging/*, allow
    p, developers, applications, get, dev/*, allow
    p, developers, applications, get, staging/*, allow
    
    # Release managers: Can sync everything
    p, release-managers, applications, sync, */*, allow
    p, release-managers, applications, get, */*, allow
    
    # Security team: Read-only everywhere
    p, security-team, applications, get, */*, allow
    
    # Map SSO groups to roles
    g, devops-team, developers
    g, devops-team, release-managers
    g, security-team, security-team
```

---

## Section 8: Monitoring ArgoCD

### ArgoCD UI Status

Status indicators:
```
SYNC STATUS:
  Synced: Git and cluster match perfectly
  OutOfSync: Difference detected, change pending
  Syncing: In progress, applying changes
  Unknown: Can't determine status

HEALTH STATUS:
  Healthy: All resources are healthy
  Progressing: Deployment in progress
  Degraded: Some resources unhealthy
  Unknown: Can't determine health

OVERALL STATE:
  Synced + Healthy: Fully operational
  OutOfSync + Healthy: Changes pending, no issues
  Synced + Degraded: Issue with pod/service
  OutOfSync + Degraded: Changes pending AND issues
```

### Troubleshooting

Problem: Application shows OutOfSync
```
Diagnosis:
1. Click on application in UI
2. Compare Git state vs cluster state
3. Look at differences

Common causes:
a. New image pushed by CI
   - Expected, will auto-sync in dev
   
b. Manual kubectl change (drifted)
   - selfHeal: true will revert change
   - If persistent, check pod logs
   
c. Deployment failing
   - Check Events tab
   - Check pod logs: kubectl logs -n namespace pod-name
   
d. Network issue
   - ArgoCD can't reach Git repo
   - Check: Repo settings → Connection Status
   - Check: Network policies, firewall
```

Problem: Pods not starting after sync
```
Diagnosis:
1. Check Application details → Resources
2. Click on Deployment
3. View Pod details
4. Check Events and logs

Common causes:
a. Image pull failed
   - kubectl describe pod -n namespace pod-name
   - Check: "Failed to pull image" message
   - Verify: Image exists in ECR
   - Verify: Pod has ECR credentials (imagePullSecrets)
   
b. Readiness probe failing
   - kubectl logs -n namespace pod-name
   - Check: Health endpoint responding
   - Check: Database/Redis connection working
   
c. Resource quota exceeded
   - kubectl describe quota -n namespace
   - Check: Cluster resources available
   - Check: Node resources
   
d. Configuration issue
   - kubectl get secret -n namespace
   - kubectl describe configmap -n namespace
   - Verify: Secrets and ConfigMaps exist
```

Problem: Sync hanging (takes > 5 minutes)
```
Diagnosis:
1. Check Application Controller logs
   kubectl logs -n argocd deployment/argocd-application-controller
   
2. Check Repository Server logs
   kubectl logs -n argocd deployment/argocd-repo-server
   
Common causes:
a. Helm dependency download timeout
   - Check network connectivity
   - Check helm repo accessibility
   
b. Large number of resources
   - Normal if deploying 50+ resources
   
c. GitOps repository large
   - ArgoCD cloning repo is slow
   - Check repo size: git count-objects -v
```

---

## Section 9: Security Best Practices

### Git Repository Access
```yaml
# Only allow push from CI service account
# GitHub branch protection rules:
- Require pull request reviews (2 approvals)
- Require status checks to pass
- Require code review from CODEOWNERS
- Dismiss stale reviews when new commits pushed
- Require branches to be up-to-date
```

### Secret Management

Never commit secrets to Git!

Proper approach:
```yaml
# gitops/prod/values.yaml (in Git)
backend:
  secrets:
    enabled: true
    name: backend-secrets  # Reference, not content
    # Actual secret stored in AWS Secrets Manager
```
```bash
# Create secret separately (not in Git)
kubectl create secret generic backend-secrets \
  --from-literal=DATABASE_PASSWORD=xxxx \
  -n production
```

Or use external secrets operator:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
spec:
  provider:
    aws:
      service: SecretsManager
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: backend-secrets
spec:
  secretStoreRef:
    name: aws-secrets
  target:
    name: backend-secrets
  data:
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: prod/backend/database-password
```

### ArgoCD Access Control
```yaml
# Only CI/CD has push access to Git
GitHub:
  Settings > Collaborators > Teams
  CI Bot team: Push (can write to repo)
  Developers: Pull Request (can propose changes)
  
# Only release managers can click Sync in prod
ArgoCD RBAC:
  release-managers: Can sync */*, get */*, create */*, override *//*
  developers: Can sync dev/*, staging/*, get dev/*, staging/*
  security-team: Can get */*
```

---

## Section 10: Disaster Recovery

### Cluster Loss Scenario
```
Scenario: EKS cluster completely destroyed

Recovery steps:
1. Provision new EKS cluster
   
2. Install ArgoCD:
   helm repo add argo https://argoproj.github.io/argo-helm
   helm install argocd argo/argo-cd \
     -n argocd --create-namespace \
     -f argocd-values.yaml
   
3. Apply root application:
   kubectl apply -f gitops/app-of-apps/argocd-root-app.yaml
   
4. ArgoCD automatically:
   - Fetches all manifests from Git
   - Creates all Applications (dev, staging, prod)
   - Syncs all namespaces
   - Deploys all workloads
   - Restores to exact previous state
   
5. Result: Cluster back to production-ready state
   Time to recovery: 10-15 minutes
   Data loss: Only since last backup
```

### Database Loss Scenario
```
Scenario: MongoDB data corrupted or deleted

Recovery steps:
1. Detect issue:
   - High error rate in logs
   - Queries returning 0 results
   
2. Stop writes (optional):
   - Scale backend to 0:
     kubectl scale deployment backend --replicas=0 -n prod
   
3. Restore from backup:
   - MongoDB Atlas restore from snapshot
   - Or: Download S3 backup, restore to cluster
   
4. Verify data integrity:
   - Check record counts
   - Spot check data
   
5. Resume service:
   - Scale backend back to 3 replicas
     kubectl scale deployment backend --replicas=3 -n prod
   
6. Post-incident:
   - Document what happened
   - Review backup strategy
   - Test restore procedure regularly
```

---

## Section 11: Cost Optimization with GitOps

### Environment-Specific Scaling

Dev values:
```yaml
backend:
  replicaCount: 1
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
```

Staging values:
```yaml
backend:
  replicaCount: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 4
```

Production values:
```yaml
backend:
  replicaCount: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
```

Cost impact:
- Dev: $176/month (minimal resources)
- Staging: $222/month (medium resources)
- Prod: $250/month (high resources, auto-scaling)
- Total: ~$650/month for all compute

Savings:
- If all three used prod config: $250 × 3 = $750/month
- Actual cost: $650/month
- Savings: $100/month (13% reduction)

---

## Section 12: Helm Chart Structure

### helm/ai-chatbot/Chart.yaml
```yaml
apiVersion: v2
name: ai-chatbot
description: AI Chatbot Framework Helm Chart
type: application
version: 0.1.0
appVersion: 1.0.0

dependencies:
  - name: backend
    version: 0.1.0
    repository: file://./charts/backend
  
  - name: frontend
    version: 0.1.0
    repository: file://./charts/frontend
  
  - name: ml
    version: 0.1.0
    repository: file://./charts/ml
  
  - name: worker
    version: 0.1.0
    repository: file://./charts/worker
  
  - name: mongodb
    version: 15.6.5
    repository: https://charts.bitnami.com/bitnami
    condition: mongodb.enabled
```

### helm/ai-chatbot/templates/configmap.yaml
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-app-config
  namespace: {{ .Release.Namespace }}
data:
  ENVIRONMENT: {{ .Values.global.environment | quote }}
  LOG_LEVEL: {{ .Values.global.logLevel | default "info" | quote }}
```

### helm/ai-chatbot/templates/ingress.yaml
```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-ingress
  annotations:
    {{- range $key, $value := .Values.ingress.annotations }}
    {{ $key }}: {{ $value | quote }}
    {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ $.Release.Name }}-{{ .serviceName }}
                port:
                  number: {{ .servicePort }}
          {{- end }}
    {{- end }}
{{- end }}
```

---

## Summary

GitOps with ArgoCD provides:

1. Git as single source of truth
2. Automatic deployments for dev/staging
3. Manual approval for production
4. Full audit trail of changes
5. Easy rollbacks via Git
6. Disaster recovery capability
7. Environment-specific configurations via values.yaml
8. App-of-Apps pattern for multi-environment management
9. CI/CD integration with automated image tag updates
10. RBAC for team access control

Current implementation status:
- Root application: argocd-root-app.yaml deployed
- Dev/Staging/Prod applications: Created and syncing
- CI/CD integration: GitHub Actions pushing image tags
- Sync policies: Dev/Staging auto-sync, Prod manual
- Status: All environments running and healthy

---

## References

- ArgoCD Documentation: https://argo-cd.readthedocs.io/
- ArgoCD Best Practices: https://argo-cd.readthedocs.io/en/stable/user-guide/best-practices/
- GitOps Principles: https://opengitops.dev/
- Helm Documentation: https://helm.sh/docs/

