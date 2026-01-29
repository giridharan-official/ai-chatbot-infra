# Part 1: Architecture Design - Service Analysis & Infrastructure Selection

## Executive Summary

This document outlines AWS infrastructure recommendations for the AI Chatbot Framework.

Final architecture decisions:

| Layer | Service | Reason |
|-------|---------|--------|
| Compute | Amazon EKS | Long-running APIs with ML workloads |
| Database | MongoDB Atlas | Document-based, schema-flexible, already integrated |
| Caching | ElastiCache Redis | Session storage and conversation context |
| Messaging | Amazon SQS | Async background job processing |
| Storage | Amazon S3 | Static assets, logs, models, state files |

---

## Compute: Amazon EKS

### What is EKS?

Managed Kubernetes service. AWS manages control plane, you manage worker nodes.

### Why EKS?

Backend service requirements:
- Long-running API server (not serverless)
- ML inference workloads (need resources)
- Stateful conversation management
- Concurrent user handling

### Alternatives Considered

Lambda: Cold starts (3-10 seconds), 15-minute execution limit, no persistent connections.

App Runner: Less control over resources, no ML workload isolation, limited observability.

ECS EC2: Works but more operational overhead, less flexible than Kubernetes.

### Cost

- EKS control plane: $73/month
- 2-4 t3.medium nodes (general): $60-120/month
- 1-2 m5.large nodes (ML): $60-120/month
- Total per environment: ~$200/month

### Scaling

- Horizontal: Add/remove pods automatically (HPA)
- Vertical: Add/remove nodes automatically (Cluster Autoscaler)
- Fine-grained: Pod-level resource allocation

---

## Database: MongoDB Atlas

### What is MongoDB Atlas?

Fully managed MongoDB cloud service.

### Why MongoDB Atlas?

Data characteristics:
- Conversations (hierarchical, nested)
- Session memory (flexible structure)
- Bot configs (evolving schema)
- Training data (variable structure)

MongoDB advantages:
- Application already uses PyMongo (no code changes)
- Document model naturally fits conversation data
- Schema flexibility (intents/entities evolve)
- Full text search, indexing
- Replication and automated backups

### Alternatives Considered

RDS (MySQL/PostgreSQL): Relational model poor fit for hierarchical conversation data. Schema migrations required when intents change.

DynamoDB: Works but requires application refactoring. Complex queries difficult.

### Cost

- M10 cluster (dev/staging): $57/month
- M20 cluster (production): $213/month
- Total for 3 environments: ~$285/month

### High Availability

- Automatic replication across 3 zones
- Automatic failover
- Point-in-time backups

---

## Caching: ElastiCache Redis

### What is Redis?

In-memory key-value store with data structures.

### Why Redis?

Chatbot caching needs:
- Conversation context (needs TTL expiration)
- Bot configuration (frequently accessed)
- User session state (complex structures)
- Rate limiting counters

Redis provides:
- Extremely low latency (1-2ms)
- Advanced data structures (hashes, lists, sets)
- TTL support (session expiration)
- Shared across all backend pods
- Replication for high availability

### Alternatives Considered

Memcached: Simpler but no persistence, no replication, no advanced structures.

### Cost

- Single node (dev): $11/month
- Small cluster (staging): $18/month
- Large cluster with replication (prod): $100/month
- Total: ~$130/month

---

## Messaging: Amazon SQS

### What is SQS?

Simple message queue service.

### Why SQS?

Async processing needs:
- Conversation logging (don't block API)
- Analytics updates (background job)
- Model retraining (long-running)
- External notifications (don't wait for external services)

SQS provides:
- Decoupling (API doesn't wait for workers)
- Automatic retries
- Dead-letter queue for failures
- Independent worker scaling
- Very cheap

### Alternatives Considered

SNS: Publication/subscription (not needed, focus is async queuing).

EventBridge: Overkill for single service (not multi-service architecture).

### Cost

- $0.40 per million requests
- At 1000 messages/day: ~$0.29/month

---

## Storage: Amazon S3

### What is S3?

Object storage service.

### Why S3?

Storage needs:
- Frontend static files (HTML, CSS, JS)
- Application logs
- Database exports and backups
- ML model artifacts
- Terraform state files

S3 provides:
- High durability (11 nines)
- Very cheap storage
- CloudFront integration for global distribution
- Lifecycle policies (move old data to cheaper storage)
- Versioning for safety

### Alternatives Considered

EBS: Instance-bound storage, not shareable, wrong abstraction.

EFS: More expensive, designed for shared filesystems (not needed).

### Cost

- Storage: < $1/month
- With CloudFront (CDN): $10-20/month

---

## Complete Architecture Cost Summary

| Component | Service | Cost/Month |
|-----------|---------|-----------|
| Compute (EKS) | 3 environments | $250 |
| Database (MongoDB) | 3 environments | $285 |
| Caching (Redis) | 3 environments | $130 |
| Messaging (SQS) | All | < $1 |
| Storage (S3) | All | < $5 |
| CDN (CloudFront) | Optional | $10-20 |
| Monitoring (CloudWatch) | All | $20-30 |
| **TOTAL** | | **$700-750/month** |

---

## Scaling Strategy

Development Environment:
- 1 backend pod
- 1 frontend pod
- Minimal resources

Staging Environment:
- 2 backend pods
- 2 frontend pods
- Medium resources
- Autoscaling enabled

Production Environment:
- 3+ backend pods
- 3+ frontend pods
- High resources
- Autoscaling enabled (scale to 10 pods at peak)

---

## Summary

Selected architecture provides:
- Cost-effective infrastructure for 3 environments
- Suitable for long-running stateful APIs
- Natural fit for document-based conversation data
- Flexible caching and async processing
- Industry standard tools (Kubernetes, MongoDB)
- Easy integration with GitOps (Helm, ArgoCD)

