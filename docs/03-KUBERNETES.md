# Part 3: Kubernetes Infrastructure (EKS)


## Executive Summary

This document describes the production-grade EKS cluster infrastructure for the AI Chatbot Framework, including cluster architecture, networking, node groups, and Helm chart deployments.

**Current Deployment Status**:
- EKS Version: 1.30
- Regions: ap-south-1 (Mumbai)
- Environments: Dev, Staging, Production (separate clusters)
- Total Cost: $103/month per cluster (varies with load)

---

## Section 1: EKS Cluster Architecture Overview

### Cluster Design Philosophy

The EKS cluster is designed for:
- Long-running containerized applications (Backend API)
- ML/NLU inference workloads (isolated on dedicated nodes)
- Horizontal and vertical auto-scaling
- High availability across 3 availability zones
- Full GitOps integration with ArgoCD

### Cluster Architecture Diagram
```
AWS Region: ap-south-1
│
├── VPC: 10.0.0.0/16
│   │
│   ├── Availability Zone A (ap-south-1a)
│   │   ├── Public Subnet: 10.0.1.0/24
│   │   └── Private Subnet: 10.0.101.0/24
│   │       └── EC2 Worker Nodes (General and ML)
│   │
│   ├── Availability Zone B (ap-south-1b)
│   │   ├── Public Subnet: 10.0.2.0/24
│   │   └── Private Subnet: 10.0.102.0/24
│   │       └── EC2 Worker Nodes
│   │
│   └── Availability Zone C (ap-south-1c)
│       ├── Public Subnet: 10.0.3.0/24
│       └── Private Subnet: 10.0.103.0/24
│           └── EC2 Worker Nodes
│
├── NAT Gateway (for private subnet egress)
│
├── EKS Control Plane (managed by AWS)
│   ├── API Server
│   ├── etcd
│   ├── Scheduler
│   └── Controller Manager
│
├── EKS Managed Node Groups
│   ├── General Workload Group
│   │   ├── Instance Type: t3.medium
│   │   ├── Min Nodes: 2
│   │   ├── Max Nodes: 5
│   │   └── Desired: 2-3
│   │
│   └── ML Workload Group
│       ├── Instance Type: m5.large (or c5.xlarge for compute)
│       ├── Min Nodes: 1
│       ├── Max Nodes: 3
│       └── Desired: 1-2
│
├── Add-ons
│   ├── VPC CNI (Container Networking)
│   ├── CoreDNS (Service Discovery)
│   ├── kube-proxy (Network Proxying)
│   └── EBS CSI Driver (Persistent Storage)
│
├── Controllers
│   ├── Cluster Autoscaler
│   ├── AWS Load Balancer Controller
│   └── ArgoCD (GitOps)
│
└── Namespaces
    ├── default
    ├── argocd
    ├── dev
    ├── staging
    └── production
```

---

## Section 2: Networking Architecture

### VPC Design

VPC CIDR Block: 10.0.0.0/16

This provides 65,536 IP addresses split across 3 availability zones.
```
VPC: 10.0.0.0/16 (65,536 IPs)
│
├── Public Subnets (for NAT Gateway and ALB)
│   ├── ap-south-1a: 10.0.1.0/24 (256 IPs)
│   ├── ap-south-1b: 10.0.2.0/24 (256 IPs)
│   └── ap-south-1c: 10.0.3.0/24 (256 IPs)
│
└── Private Subnets (for EKS nodes and pods)
    ├── ap-south-1a: 10.0.101.0/24 (256 IPs)
    ├── ap-south-1b: 10.0.102.0/24 (256 IPs)
    └── ap-south-1c: 10.0.103.0/24 (256 IPs)
```

### Why Multiple Subnets Across AZs?

High availability:
- If one AZ fails, workloads still run in other AZs
- Automatic failover handled by Kubernetes
- Service load balanced across healthy AZs

Network isolation:
- Public subnets: NAT Gateway, Application Load Balancer
- Private subnets: EC2 worker nodes, database
- Public internet cannot directly reach private subnets

### Networking Flow
```
Internet User
    │
    ↓ (HTTP/HTTPS)
AWS Application Load Balancer
    (Public IP: NAT Gateway)
    │
    ↓ (Port 80/443)
VPC Private Subnets
    │
    ├─→ Backend Pod (10.0.101.x)
    ├─→ Frontend Pod (10.0.102.x)
    └─→ ML Pod (10.0.103.x)
    │
    ↓
MongoDB Atlas (external)
Redis (external)
```

### Security Groups

**EKS Cluster Security Group**:
- Ingress: Port 443 from anywhere (API server)
- Ingress: Port 10250 between nodes (kubelet)
- Egress: All traffic to anywhere
- Purpose: Control plane communication

**Node Security Group**:
- Ingress: 10.0.0.0/16 (VPC CIDR, allow pod communication)
- Ingress: 443 from cluster SG (control plane to nodes)
- Egress: All traffic (download images, contact databases)
- Purpose: Worker node networking

**ALB Security Group**:
- Ingress: 0.0.0.0/0 port 80 and 443 (internet)
- Egress: 10.0.0.0/16 (to VPC nodes)
- Purpose: Load balancer public interface

**RDS/External Service Security Group**:
- Ingress: Node SG port 27017 (MongoDB)
- Ingress: Node SG port 6379 (Redis)
- Purpose: Allow pods to access databases

### Network Policy Example

Control which pods can talk to which pods:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-to-mongodb
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: default
      ports:
        - protocol: TCP
          port: 27017  # MongoDB
    - to:
        - namespaceSelector:
            matchLabels:
              name: default
      ports:
        - protocol: TCP
          port: 6379   # Redis
```

---

## Section 3: Node Groups Configuration

### General Workload Node Group

Purpose: Run frontend, backend APIs, and general services

Instance Type: t3.medium
- 2 vCPU
- 4 GB RAM
- Network: Up to 5 Gigabit
- EBS: 20 GB gp2

Scaling Configuration:
```
Minimum Size: 2 nodes
  (Always have 2 running for HA)
  
Desired Size: 2-3 nodes
  (Starts with 2, scales to 3 under load)
  
Maximum Size: 5 nodes
  (Cap at 5 to prevent runaway costs)
  
Scaling Metrics:
  - Target CPU Utilization: 70%
  - Scale up when average > 70%
  - Scale down when average < 30%
```

Cost: $30/month per t3.medium instance
- 2 nodes baseline: $60/month
- Peak (5 nodes): $150/month
- Average across day: ~$80-100/month

Pod Capacity:
- Each t3.medium can run 35 pods (AWS limit)
- At 2 nodes: 70 pods maximum
- Reserved for system: 10 pods (CoreDNS, kube-proxy, etc.)
- Available for applications: 60 pods

Example deployment on general nodes:
```
Backend replicas: 3-5
Frontend replicas: 2-3
MongoDB: 1 pod
Redis: 1 pod
ArgoCD: 5 pods
Monitoring: 10 pods
Total: 20-25 pods on 2-3 nodes
```

### ML Workload Node Group

Purpose: Run ML inference and NLU processing

Instance Type: m5.large (default) or c5.xlarge (compute-heavy)
- m5.large: 2 vCPU, 8 GB RAM (good for most ML)
- c5.xlarge: 4 vCPU, 8 GB RAM (better for compute)

Scaling Configuration:
```
Minimum Size: 1 node
  (ML workloads are less frequent)
  
Desired Size: 1 node
  
Maximum Size: 3 nodes
  (Cap for cost control)
  
Scaling Metrics:
  - Target CPU Utilization: 60%
  - Scale up when average > 60%
```

Cost: $60/month per m5.large instance
- 1 node baseline: $60/month
- Peak (3 nodes): $180/month
- Average: ~$80-100/month

Why Separate Node Group?

Isolation:
- Heavy ML workloads don't impact API latency
- API pods aren't scheduled on ML nodes

Right-sizing:
- ML jobs need more RAM (8GB vs 4GB)
- General APIs use less CPU

Scaling independently:
- API load vs ML load are different patterns
- APIs peak during business hours
- ML jobs run on schedule (retraining at night)

Node Affinity (ensure pods go to right node group):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-inference
spec:
  template:
    spec:
      nodeSelector:
        workload: ml   # Pods run only on ML nodes
      containers:
        - name: ml
          image: backend:latest
```

---

## Section 4: EKS Add-ons

### 1. VPC CNI (Elastic Network Interface)

Purpose: Provide IP addresses to pods from VPC CIDR

How it works:
```
Pod needs network
    ↓
VPC CNI plugin creates ENI (Elastic Network Interface)
    ↓
ENI gets IP address from VPC CIDR (e.g., 10.0.101.50)
    ↓
Pod uses this IP to communicate
    ↓
Pods directly routable within VPC (no overlay network)
```

Configuration:
```bash
# Current settings
eksctl utils describe-addon-versions --name vpc-cni

# Enable pod security group
eksctl set podIdentityAssociation \
  --cluster my-cluster \
  --namespace kube-system \
  --service-account-name aws-node \
  --role-arn arn:aws:iam::ACCOUNT:role/eks-vpc-cni
```

Advantages:
- Direct pod-to-pod communication (fast)
- Can use existing VPC security groups
- IP addresses consistent across restarts

Limitation:
- Maximum pods per node limited by ENI capacity
- t3.medium: 35 pods max
- m5.large: 58 pods max

### 2. CoreDNS

Purpose: Service discovery (convert service names to IPs)

How it works:
```
Pod wants to reach backend service
    ↓
Pod queries CoreDNS: "backend.default.svc.cluster.local"
    ↓
CoreDNS returns IP: 10.0.101.100
    ↓
Pod connects to 10.0.101.100
```

Configuration:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        log
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          upstream
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
```

Built-in DNS names:
```
service.namespace.svc.cluster.local
  Example: backend.default.svc.cluster.local → 10.0.101.100

pod.namespace.pod.cluster.local
  Example: pod-123.default.pod.cluster.local → 10.0.101.50
```

### 3. kube-proxy

Purpose: Implement iptables rules for service networking

How it works:
```
Service: backend (IP: 10.0.101.100:8000)
    ↓
kube-proxy creates iptables rule
    ↓
Traffic to 10.0.101.100:8000 → randomly distribute to pods
  - Pod A: 10.0.101.50
  - Pod B: 10.0.102.40
  - Pod C: 10.0.103.30
```

Configuration (uses iptables mode):
```bash
# Check proxy mode
kubectl get daemonset -n kube-system kube-proxy -o yaml | grep mode

# Current: iptables (efficient, kernel-level)
# Alternative: ipvs (more advanced load balancing)
```

### 4. EBS CSI Driver

Purpose: Enable persistent storage using AWS EBS volumes

How it works:
```
Pod needs persistent storage
    ↓
PersistentVolumeClaim (PVC) created
    ↓
EBS CSI Driver provisions EBS volume
    ↓
Volume attached to EC2 node
    ↓
Pod mounts volume at /data
    ↓
Data persists across pod restarts
```

Configuration:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp2  # EBS General Purpose
  resources:
    requests:
      storage: 10Gi  # 10 GB volume
```

Storage Classes:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: ebs.csi.aws.com
parameters:
  type: gp2      # General Purpose SSD
  iops: "3000"
  throughput: "125"
  encrypted: "true"
```

Use case in MongoDB:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
spec:
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp2
        resources:
          requests:
            storage: 100Gi  # 100GB EBS for MongoDB
```

---

## Section 5: IRSA (IAM Roles for Service Accounts)

### What is IRSA?

Securely give pods IAM permissions without storing credentials.

Traditional approach (INSECURE):
```
Create IAM access key
    ↓
Store in Kubernetes secret
    ↓
Pod reads secret
    ↓
Pod uses credentials
    ↓
Problem: If pod is compromised, attacker has credentials
```

IRSA approach (SECURE):
```
Create IAM role
    ↓
Link IAM role to Kubernetes service account
    ↓
Pod gets temporary credentials via STS
    ↓
Credentials auto-expire (1 hour)
    ↓
Problem solved: Attacker can't access other services
```

### Setup

IRSA is already enabled on the cluster. Here's how it works:

1. Create IAM Role:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/OIDCID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.ap-south-1.amazonaws.com/id/OIDCID:sub": "system:serviceaccount:kube-system:aws-node"
        }
      }
    }
  ]
}
```

2. Create Service Account:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-node
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/eks-vpc-cni
```

3. Pod automatically gets credentials:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
spec:
  serviceAccountName: aws-node  # Uses service account
  containers:
    - name: app
      image: myapp:latest
      # Pod automatically has AWS credentials injected
```

### Use Cases

Cluster Autoscaler (allows scaling EC2 nodes):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/cluster-autoscaler
```

AWS Load Balancer Controller (manages ALBs):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/aws-load-balancer-controller
```

Application accessing S3:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/app-s3-access
```

---

## Section 6: Cluster Autoscaler

Purpose: Automatically add/remove EC2 nodes based on pod demand

How it works:
```
Scenario 1: Pod can't be scheduled (insufficient resources)
    ↓
Pod remains in Pending state
    ↓
Cluster Autoscaler detects pending pods
    ↓
Autoscaler provisions new EC2 node
    ↓
Pod scheduled on new node
    ↓
Pod starts running

Scenario 2: Nodes have very low utilization
    ↓
Autoscaler detects unused node
    ↓
Waits 10 minutes (to ensure it's idle)
    ↓
Gracefully drains pods to other nodes
    ↓
Terminates EC2 node
    ↓
Cost reduced
```

Configuration:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
        - name: cluster-autoscaler
          image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.28.0
          args:
            - --cloud-provider=aws
            - --expander=least-waste
            - --skip-nodes-with-local-storage=false
            - --scale-down-enabled=true
            - --scale-down-delay-after-add=10m
            - --scale-down-unneeded-time=10m
```

Scaling Example:
```
Initial state:
- 2 t3.medium nodes running
- 18 pods deployed
- 60% CPU utilization

Traffic spike hits:
- Need 5 more backend pod replicas
- Total: 23 pods needed
- Available space: 14 pods (2 nodes × 35 max - 18 system)
- 9 pods can't be scheduled

Cluster Autoscaler action:
- Sees 9 pending pods
- Launches 1 new t3.medium node (35 pod capacity)
- After 30 seconds, node joins cluster
- 9 pending pods scheduled on new node
- Cluster now has 3 nodes, utilization normal

Traffic subsides:
- 3 nodes with 20% CPU utilization
- Autoscaler waits 10 minutes
- Drains pods from 1 node (moves them to other nodes)
- Terminates empty node
- Back to 2 nodes, saves $30/month
```

Costs:
- Scaling up: Immediate (30-60 seconds)
- Scaling down: Delayed (10+ minutes) to avoid thrashing
- At peak: $150/month (5 nodes)
- At baseline: $60/month (2 nodes)
- Average with elasticity: $80-100/month

---

## Section 7: AWS Load Balancer Controller

Purpose: Create AWS Application Load Balancers from Kubernetes Ingress

How it works:
```
Kubernetes Ingress manifest
    ↓
AWS Load Balancer Controller detects it
    ↓
Controller calls AWS API
    ↓
AWS provisions Application Load Balancer
    ↓
ALB routes traffic to pods
```

Configuration:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: chatbot-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-south-1:ACCOUNT:certificate/ID
spec:
  ingressClassName: alb
  rules:
    - host: chatbot.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 3000
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend
                port:
                  number: 8000
          - path: /ml
            pathType: Prefix
            backend:
              service:
                name: ml
                port:
                  number: 9000
```

AWS Resources Created:
- Application Load Balancer (ALB)
  - DNS: k8s-chatbot-xxxxx-1234567890.ap-south-1.elb.amazonaws.com
  - Public IP: Assigned by AWS
  
- Target Groups
  - /: Routes to frontend:3000 pods
  - /api: Routes to backend:8000 pods
  - /ml: Routes to ml:9000 pods

- Security Groups
  - ALB SG: Allow 80/443 from internet
  - Node SG: Allow ports 3000, 8000, 9000 from ALB

Cost:
- ALB: $16/month fixed
- Requests: $0.006 per request (negligible)
- Data processed: $0.006 per GB

---

## Section 8: Helm Charts Structure

### Parent Chart: ai-chatbot

Location: helm/ai-chatbot/
```
helm/ai-chatbot/
├── Chart.yaml
│   - name: ai-chatbot
│   - version: 0.1.0
│   - dependencies: backend, frontend, ml, worker, mongodb
│
├── values.yaml
│   - Global settings (environment, logLevel)
│   - Backend config (replicas, resources, health probes)
│   - Frontend config
│   - ML config
│   - Worker config
│   - MongoDB config
│   - Ingress config
│
├── Chart.lock
│   - Locks dependency versions
│
├── templates/
│   ├── configmap.yaml (environment variables)
│   ├── secrets.yaml (sensitive data)
│   ├── ingress.yaml (ALB configuration)
│   └── mongodb-configmap.yaml
│
└── charts/
    ├── backend/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   ├── templates/
    │   │   ├── deployment.yaml
    │   │   ├── service.yaml
    │   │   ├── hpa.yaml
    │   │   └── _helpers.tpl
    │
    ├── frontend/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   ├── templates/
    │
    ├── ml/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   ├── templates/
    │
    └── worker/
        ├── Chart.yaml
        ├── values.yaml
        ├── templates/
```

### Values Files by Environment

Location: gitops/ENV/values.yaml

Dev values (minimal resources):
```yaml
backend:
  enabled: true
  replicaCount: 1
  image:
    repository: 235494787667.dkr.ecr.ap-south-1.amazonaws.com/backend
    tag: latest
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
  autoscaling:
    enabled: false

frontend:
  replicaCount: 1
  
ml:
  enabled: false  # Disabled in dev to save costs

mongodb:
  enabled: true
  architecture: standalone
  persistence:
    size: 5Gi
```

Staging values (medium resources):
```yaml
backend:
  replicaCount: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 4
    targetCPUUtilizationPercentage: 70

frontend:
  replicaCount: 2
  
ml:
  enabled: true
  replicaCount: 1

mongodb:
  persistence:
    size: 20Gi
```

Production values (high availability):
```yaml
backend:
  replicaCount: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70

frontend:
  replicaCount: 3
  
ml:
  enabled: true
  replicaCount: 2

mongodb:
  persistence:
    size: 100Gi
```

---

## Section 9: Resource Sizing

### Backend Pod

Purpose: FastAPI REST API, NLU processing

Resources per replica:
```yaml
requests:
  cpu: 250m        # 1/4 vCPU minimum
  memory: 512Mi    # 512 MB minimum

limits:
  cpu: 500m        # 1/2 vCPU maximum
  memory: 1Gi      # 1 GB maximum
```

Justification:
- NLU processing requires 200-300m CPU per request
- Conversation context needs 200-300 MB RAM
- Limits prevent noisy neighbor issues

Replica Count by Environment:
- Dev: 1 replica (acceptable downtime)
- Staging: 2 replicas (test HA)
- Production: 3 replicas (true HA, 2/3 always available)

### Frontend Pod

Purpose: Next.js React application

Resources per replica:
```yaml
requests:
  cpu: 100m        # Minimal (mostly serving static files)
  memory: 256Mi

limits:
  cpu: 250m
  memory: 512Mi
```

Justification:
- Frontend is mostly static files served from memory
- Lower resource needs than backend
- Scale horizontally for concurrent users

Replica Count:
- Dev: 1 replica
- Staging: 2 replicas
- Production: 3 replicas

### ML Pod

Purpose: Model inference and NLU processing

Resources per replica:
```yaml
requests:
  cpu: 1000m       # Full vCPU (intensive computation)
  memory: 2Gi      # 2 GB for models

limits:
  cpu: 2000m       # Up to 2 vCPUs
  memory: 4Gi      # Up to 4 GB
```

Justification:
- ML models are CPU-intensive
- Need dedicated node group to avoid starving APIs
- Large memory for loaded model weights

Replica Count:
- Dev: Disabled (save costs)
- Staging: 1 replica
- Production: 2 replicas (one always available)

### MongoDB Pod

Purpose: Document database

Resources:
```yaml
requests:
  cpu: 500m
  memory: 1Gi

limits:
  cpu: 1000m
  memory: 2Gi

storage:
  dev: 5Gi         # Small dev database
  staging: 20Gi    # Test with realistic data
  production: 100Gi # Full production data
```

---

## Section 10: Health Checks and Probes

### Liveness Probe

Purpose: Detect if pod is "alive" but hung

Example (Backend):
```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 8000
  initialDelaySeconds: 30   # Wait 30s before first check
  periodSeconds: 10         # Check every 10 seconds
  timeoutSeconds: 2         # Timeout after 2 seconds
  failureThreshold: 3       # Kill after 3 failures
```

Behavior:
```
Startup:
  0-30s: Pod starts, liveness probe skipped (initialDelaySeconds)
  
30-40s: First liveness check
  GET http://pod:8000/health/live
  Response: 200 OK
  Result: Pod healthy

Pod gets stuck (deadlock, infinite loop):
  40-50s: Liveness check
  Response: Timeout (no response after 2s)
  Failure count: 1 of 3
  
  50-60s: Liveness check
  Response: Timeout
  Failure count: 2 of 3
  
  60-70s: Liveness check
  Response: Timeout
  Failure count: 3 of 3
  
Action: Kubernetes kills pod, starts new one
```

### Readiness Probe

Purpose: Detect if pod is ready to serve traffic

Example (Backend):
```yaml
readinessProbe:
  httpGet:
    path: /health/ready
    port: 8000
  initialDelaySeconds: 10   # Wait 10s before first check
  periodSeconds: 5          # Check every 5 seconds
  timeoutSeconds: 2
  failureThreshold: 3
```

Behavior:
```
Pod starting:
  0-10s: Initializing, readiness skipped
  
10-15s: First readiness check
  GET http://pod:8000/health/ready
  Response: 503 Service Unavailable (still loading models)
  
15-20s: Readiness check
  Response: 503 (loading models 80% complete)
  
20-25s: Readiness check
  Response: 200 OK (ready!)
  
Result: ALB starts sending traffic to pod

Pod loses database connection:
  25-30s: Readiness check
  Response: 503 Service Unavailable (no DB connection)
  Failure count: 1 of 3
  
  30-35s: Readiness check
  Response: 503
  Failure count: 2 of 3
  
  35-40s: Readiness check
  Response: 503
  Failure count: 3 of 3
  
Action: ALB stops sending traffic, pod removed from load balancer
```

### Health Endpoint Implementation

Backend (FastAPI):
```python
@app.get("/health/live")
async def health_live():
    """Liveness probe - is process running?"""
    return {"status": "ok"}

@app.get("/health/ready")
async def health_ready():
    """Readiness probe - is service ready for traffic?"""
    # Check database connection
    if not await db.ping():
        return {"status": "unhealthy", "reason": "DB"}, 503
    
    # Check cache connection
    if not redis.ping():
        return {"status": "unhealthy", "reason": "Redis"}, 503
    
    # All checks passed
    return {"status": "ok"}, 200
```

Frontend (Next.js):
```typescript
// pages/api/health.ts
export default function handler(req, res) {
  // Liveness - always return 200
  if (req.query.type === 'live') {
    return res.status(200).json({ status: 'ok' });
  }
  
  // Readiness - check dependencies
  if (req.query.type === 'ready') {
    // Check backend API
    const backendOk = await checkBackendAPI();
    if (!backendOk) {
      return res.status(503).json({ status: 'unhealthy' });
    }
    
    return res.status(200).json({ status: 'ok' });
  }
}
```

---

## Section 11: Horizontal Pod Autoscaler (HPA)

Purpose: Automatically scale pod replicas based on metrics

Example (Backend):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Scaling Example:
```
Initial state:
  - 2 backend replicas running
  - Average CPU: 35% utilization
  - Target: 70%
  - Action: No scaling needed

Traffic spike (marketing campaign):
  - 1000 concurrent users online
  - Average CPU: 85% utilization (above 70% target)
  - HPA calculation: 85/70 = 1.21 (need 21% more capacity)
  - Current: 2 replicas × 1.21 = 2.42 ≈ 3 replicas needed
  - Action: Scale to 3 replicas

Scaling up:
  - Kubernetes launches 1 new backend pod
  - Pod pulls image from ECR (~30 seconds)
  - Pod starts, passes readiness probe (~10 seconds)
  - ALB adds pod to target group
  - Load starts distributing to 3 pods
  - CPU per pod: 85% ÷ 3 = 28% (target met!)

Traffic subsides:
  - Average CPU: 40% (below 70% target)
  - HPA waits 5 minutes (scale-down delay)
  - HPA calculation: 40/70 = 0.57 (have too much capacity)
  - Would need: 2 × 0.57 = 1.14 ≈ 2 replicas
  - Action: Already at minReplicas (2), no scale down
```

With ML workloads:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ml-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ml
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75
```

Note: ML workloads scale based on memory (not CPU)
- Memory is fixed at 2GB per pod
- CPU usage varies by model complexity
- Memory threshold of 75% prevents out-of-memory kills

---

## Section 12: Storage Configuration

### Persistent Volume Claims (PVC)

For MongoDB:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-data
spec:
  accessModes:
    - ReadWriteOnce        # Only one pod can use at a time
  storageClassName: gp2    # AWS EBS general purpose
  resources:
    requests:
      storage: 5Gi         # Dev: 5GB
                          # Staging: 20GB
                          # Prod: 100GB
```

Storage Lifecycle:
```
Pod requests storage
    ↓
EBS CSI Driver provisions EBS volume
    ↓
Volume attached to EC2 instance
    ↓
Pod mounts at /data/db
    ↓
MongoDB writes to /data/db
    ↓
Data persists on EBS
    ↓
Pod restarts
    ↓
Volume reattached
    ↓
MongoDB recovers from disk
```

EBS Backup Strategy:
```
Daily snapshots at 2 AM UTC
    ↓
Snapshots stored in S3
    ↓
Retention: 30 days for staging, 90 days for prod
    ↓
If data corruption detected
    ↓
Restore from snapshot
    ↓
Validate data integrity
    ↓
Resume service
```

Cost:
- EBS volume: $0.10/GB/month
  - Dev 5GB: $0.50/month
  - Staging 20GB: $2/month
  - Prod 100GB: $10/month
  
- Snapshots: $0.05/GB/month
  - Dev: $0.25/month
  - Staging: $1/month
  - Prod: $5/month

---

## Section 13: Resource Quotas and Limits

Per-namespace quotas (prevent one team from consuming all resources):
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "10"           # Max 10 vCPU requested
    requests.memory: "20Gi"      # Max 20 GB requested
    limits.cpu: "20"             # Max 20 vCPU limited
    limits.memory: "40Gi"        # Max 40 GB limited
    pods: "100"                  # Max 100 pods
    services.loadbalancers: "1"  # Max 1 load balancer

  scopeSelector:
    matchExpressions:
      - operator: In
        scopeName: PriorityClass
        values: ["default"]
```

Development team quota:
```
CPU requests: 10 vCPU total
  - If 5 pods × 2 vCPU requests each = at quota limit
  - Prevents team from hogging cluster

Memory: 20 GB total
  - Prevents memory-hungry jobs from crashing cluster
```

---

## Section 14: Summary and Cost Analysis

### Cluster Costs by Environment

Development Cluster:
```
EKS control plane:        $73/month
Compute:
  - 2 t3.medium nodes:    $60/month (baseline)
  - 1 m5.large ML node:   $60/month (always on)
Storage:
  - EBS volumes:          $1/month
  - Snapshots:            $0.25/month
ALB:                      $16/month
Data transfer:            $5/month
Total:                    $215/month
```

Staging Cluster:
```
EKS control plane:        $73/month
Compute:
  - 2 t3.medium nodes:    $60/month
  - 1 m5.large ML node:   $60/month
Storage:
  - EBS volumes:          $2/month
  - Snapshots:            $1/month
ALB:                      $16/month
Data transfer:            $10/month
Total:                    $222/month
```

Production Cluster:
```
EKS control plane:        $73/month
Compute:
  - 3 t3.medium nodes:    $90/month (baseline)
  - Up to 5 nodes at peak: $150/month
  - 2 m5.large ML nodes:  $120/month
  - Average with scaling: $110/month
Storage:
  - EBS volumes:          $10/month
  - Snapshots:            $5/month
ALB:                      $16/month
Data transfer:            $30/month
Total:                    $244-274/month (average $250)
```

Combined Infrastructure Cost:
```
Development:              $215/month
Staging:                  $222/month
Production:               $250/month
ECR (images):             $5/month
Route53 (DNS):            $1/month
CloudWatch (logs):        $20/month
Total Monthly:            ~$713/month
```

---

## Key Takeaways

1. EKS separates general and ML workloads on different node groups
2. VPC spans 3 availability zones for high availability
3. Cluster Autoscaler enables cost-efficient scaling
4. IRSA provides secure pod-to-service authentication
5. HPA automatically scales pods based on CPU/memory
6. Health probes ensure only healthy pods receive traffic
7. PVC enables stateful workloads like MongoDB
8. Resource quotas prevent resource contention
9. Helm charts enable environment-specific configurations
10. Total cluster infrastructure: ~$713/month for all environments

---

## References

- EKS Documentation: https://docs.aws.amazon.com/eks/
- Kubernetes Documentation: https://kubernetes.io/docs/
- Helm Documentation: https://helm.sh/docs/
- EKS Best Practices: https://aws.github.io/aws-eks-best-practices/

