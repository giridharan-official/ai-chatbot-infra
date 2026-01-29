# Part 1: Architecture Design - Service Analysis & Infrastructure Selection

**Document Version**: 1.0  
**Last Updated**: January 29, 2026  
**Audience**: DevOps Engineers, Solution Architects, Technical Decision Makers

---

## 📋 Executive Summary

This document outlines the AWS infrastructure recommendations for the AI Chatbot Framework, analyzing each application component and justifying infrastructure choices.

### Final Architecture Decisions

| Layer | Service | Reasoning |
|-------|---------|-----------|
| **Compute** | Amazon EKS | Long-running stateful APIs with ML workloads |
| **Database** | MongoDB Atlas | Document-based, schema-flexible, already integrated |
| **Caching** | ElastiCache Redis | Session storage, conversation context, fast access |
| **Messaging** | Amazon SQS | Async background jobs, decoupling |
| **Storage** | Amazon S3 | Static assets, logs, ML artifacts, infrastructure state |

---

## 🎯 Part 1: Compute Infrastructure Analysis

### Application Component: Backend Service

**Characteristics:**
- NLU (Natural Language Understanding) processing
- ML inference (heavy CPU/memory)
- REST APIs (FastAPI)
- Long-running requests (some queries take 2-5 seconds)
- Stateful conversation management
- Needs isolation and independent scaling

**Key Requirements:**
- Handle variable load (peak during business hours)
- Support multiple concurrent conversations
- Fine-grained resource allocation
- Easy integration with ML models

---

## 🔍 Option 1: AWS Lambda - ❌ **NOT Suitable**

### What is Lambda?

AWS Lambda is a serverless compute service where you upload code and AWS runs it in response to events.
```
User Request
    ↓
Lambda triggered
    ↓
Function executes (up to 15 minutes)
    ↓
Lambda stops
    ↓
Response sent
```

### Why Lambda Works Well For:

✅ Short-duration requests (< 1 minute)  
✅ Event-driven processing (file uploads, database changes)  
✅ Spiky traffic patterns (long idle periods)  
✅ Small, focused functions  
✅ Minimal operational overhead  

**Example use case:** Processing uploaded documents → Lambda is perfect

### Problems for AI Chatbot Backend:

❌ **Cold Start Delays**
- Lambda function startup: 3-10 seconds
- For chat responses, this is unacceptable
- Users expect < 1 second response times

❌ **15-Minute Execution Limit**
- ML model inference can be slow
- Complex conversations might approach limits
- Retraining jobs definitely exceed 15 minutes

❌ **WebSocket/Streaming Limitations**
- Lambda doesn't support persistent connections
- Chat platforms need bidirectional real-time updates
- Lambda is request-response only

❌ **Stateful Memory Management**
- Each Lambda invocation is isolated
- Conversation context must be re-loaded from database each time
- No persistent in-memory caching between requests

❌ **Cost at Scale**
- High-frequency chat API would incur per-request charges
- 1,000 requests/hour × 30 days = 720,000 invocations
- At $0.20 per 1M invocations, cost adds up quickly
- Fixed EKS cluster is cheaper for predictable load

### Cost Comparison: Lambda vs EKS for Chatbot

**Lambda Scenario:**
- 100 requests/minute = 144,000/day
- Average execution: 3 seconds = 432,000 GB-seconds/day
- Cost: ~$17.28/day or ~$518/month

**EKS Scenario:**
- EKS control plane: ~$73/month
- 2-4 t3.medium nodes: ~$200-400/month
- Total: ~$273-473/month

**Verdict: EKS is cheaper at scale + better performance**

### Verdict: ❌ Lambda is NOT suitable for this backend

---

## 🔍 Option 2: AWS App Runner - ⚠️ **Limited Fit**

### What is App Runner?

AWS App Runner is a fully managed container service - simpler than EKS but less flexible.
```
You push Docker image → App Runner manages containers → Auto-scales
```

### Why App Runner Works Well For:

✅ Simple containerized web apps  
✅ No Kubernetes expertise required  
✅ Automatic scaling  
✅ Minimal operational overhead  
✅ Good for proof-of-concepts  

**Example use case:** Hosting a simple web API with predictable load

### Problems for AI Chatbot Backend:

❌ **Limited Scaling Control**
- Can't specify exact resource limits per request
- ML workloads need fine-grained CPU allocation
- No pod-level resource guarantees

❌ **No Native GitOps**
- App Runner doesn't integrate with ArgoCD
- Manual deployments required
- Harder to manage multiple environments

❌ **Restricted Observability**
- Limited CloudWatch integration
- Can't instrument individual containers
- ML model performance tracking is difficult

❌ **No Multi-Node Deployment**
- Scales horizontally but less transparent
- Can't separate general vs ML workloads

### Verdict: ⚠️ App Runner is good for PoC, not production ML workloads

---

## 🔍 Option 3: Amazon ECS on EC2 - ✅ **Valid Alternative**

### What is ECS on EC2?

You manage EC2 instances, ECS orchestrates containers on those instances.
```
You provision EC2 instances
    ↓
ECS launches Docker containers on them
    ↓
You manage instance lifecycle (scaling, patching)
```

### Why ECS EC2 Works Well For:

✅ Better cost efficiency than ECS Fargate  
✅ More control than App Runner  
✅ Simpler than Kubernetes  
✅ Native AWS service (tight CloudWatch integration)  
✅ Good for steady, predictable workloads  

### Advantages Over ECS Fargate:

- Lower cost (you manage compute)
- More control over instance selection
- Better for right-sizing workloads

### Problems for AI Chatbot Backend:

❌ **Less Granular Scaling**
- Scales by EC2 instances, not individual containers
- If you have 1 instance, you can't scale below it

❌ **ML & API Sharing Compute**
- Can't easily isolate ML workloads
- One heavy model can impact API responses

❌ **No Native Helm Support**
- Must write ECS task definitions (different from industry standard)
- Harder to share configurations across teams

❌ **Slower Scaling**
- Launching EC2 instance takes 2-5 minutes
- Kubernetes node scaling is faster

❌ **More Operational Work**
- Must manage EC2 patching
- Must monitor EC2 health
- Must handle instance failures

### Cost Comparison: ECS EC2 vs EKS

**ECS EC2:**
- 2 x t3.medium: ~$30/month
- Data transfer: variable
- Simple but more ops work

**EKS:**
- Control plane: $73/month
- 2 x t3.medium: ~$30/month
- Total: ~$103/month
- Better orchestration, GitOps, industry standard

**For 1-2 applications, ECS EC2 is slightly cheaper**  
**For 3+ applications, EKS becomes better ROI**

### Verdict: ✅ Valid production option, but more operational overhead than EKS

---

## 🔍 Option 4: Amazon EKS (Kubernetes) - ✅ **CHOSEN**

### What is EKS?

Amazon Elastic Kubernetes Service is a fully managed Kubernetes cluster.
```
AWS manages:
- Control plane (API server, scheduler, etcd)
- Patching and upgrades
- High availability

You manage:
- Worker nodes
- Application deployments
- Helm charts
```

### Why EKS Works Well For AI Chatbot:

✅ **Designed for Complex Workloads**
- Backend + ML inference + caching all on same cluster
- Each can have different resource requirements

✅ **Industry Standard**
- Kubernetes is standard in production environments
- Skills transfer to other companies
- Huge ecosystem of tools

✅ **Fine-Grained Autoscaling**
- Horizontal Pod Autoscaler (HPA): Scales pods based on CPU/memory
- Cluster Autoscaler: Scales nodes automatically
- Can scale from 2 to 10 nodes in 30 seconds

✅ **Environment Isolation**
- Different namespaces for dev/staging/prod
- Different node groups for different workload types
- Network policies for pod-to-pod communication

✅ **Native Helm Integration**
- Frontend, backend, database all deployed with Helm
- Templating for dev/staging/prod configurations
- Industry standard package management

✅ **Perfect GitOps Match**
- ArgoCD watches git repo
- Automatic deployments on code changes
- Declarative infrastructure
- Easy rollbacks

✅ **Observability Built-In**
- Prometheus metrics available
- Container logs in CloudWatch
- Distributed tracing possible
- Deep visibility into pod behavior

### EKS Architecture for This Project
```
┌─────────────────────────────────────────┐
│         EKS Cluster (Managed)           │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────┬──────────────┐       │
│  │  General NG  │   ML Node    │       │
│  │ (t3.medium)  │  (c5.xlarge) │       │
│  │   2-5 nodes  │   1-3 nodes  │       │
│  └──────┬───────┴──────┬───────┘       │
│         │              │               │
│    ┌────▼──────┐  ┌────▼──────┐      │
│    │  Backend  │  │   ML Pod  │      │
│    │  Frontend │  │ Inference │      │
│    │ MongoDB   │  │           │      │
│    └───────────┘  └───────────┘      │
│                                         │
└─────────────────────────────────────────┘
```

### Scaling Strategy

**Horizontal Pod Autoscaling (HPA)**
```
Backend pods:
- Min: 2 replicas
- Max: 10 replicas
- Scale at: 70% CPU utilization
- Scales in 30-60 seconds
```

**Vertical Pod Autoscaling (VPA)**
```
Optional: Recommends right-sized resource limits
Helps optimize cost
```

**Cluster Autoscaling**
```
Worker nodes:
- General workloads: 2-5 t3.medium nodes
- ML workloads: 1-3 c5.xlarge nodes
- Auto-adds nodes when needed
- Auto-removes idle nodes
```

### Cost Analysis: EKS

**Fixed Costs:**
- EKS control plane: $73/month

**Compute Costs (2-4 t3.medium nodes at normal traffic):**
- Dev: 1 node @ $30/month
- Staging: 2 nodes @ $60/month
- Prod: 3 nodes @ $90/month

**Total: ~$253/month for 3 environments**

**Scaling Benefit:**
- At peak: 4-6 nodes
- At off-peak: 1-2 nodes per environment
- Average cost: ~$150-200/month
- Much cheaper than fixed-size ECS or Lambda

### Verdict: ✅ **EKS is BEST for this project**

**Reasoning Summary:**
- Supports long-running stateful APIs ✓
- Supports ML inference isolation ✓
- Scales efficiently from 1-100+ requests/sec ✓
- Native Helm support ✓
- Perfect ArgoCD integration ✓
- Cost-effective at scale ✓
- Industry standard ✓

---

## 💾 Part 2: Database Infrastructure Analysis

### Application Component: Data Storage

**Data Types:**
- Conversations (growing, historical)
- Session memory (temporary, TTL-based)
- Bot configurations (reference data)
- Training intents/entities (evolving schema)

**Key Requirements:**
- Flexible schema (intents/entities change)
- Fast document queries
- TTL-based expiration
- High availability and backups
- No complex joins

---

## 🔍 Option 1: Amazon RDS (MySQL/PostgreSQL) - ❌ **NOT Suitable**

### What is RDS?

Managed relational database with fixed schema (tables, columns, rows).

### Why RDS Works Well For:

✅ Financial transactions  
✅ Clear relational structure (orders → items → payments)  
✅ Strong ACID guarantees  
✅ Complex reporting with JOINs  

### Problems for Chatbot Data:

❌ **Inflexible Schema**
```sql
-- Example: RDS requires predefined structure
CREATE TABLE conversations (
  id INT,
  user_id INT,
  message TEXT,
  intent VARCHAR(50),
  entities JSON  -- JSON is secondary, not native
);

-- Adding new fields requires ALTER TABLE
-- Intents might change: {"type": "order_status"} → {"type": "order_status", "priority": "high"}
-- Each schema change locks the table temporarily
```

❌ **Schema Migration Pain**
- Adding a new intent type requires migration
- Downtime or careful coordination required
- Not ideal for rapidly evolving NLU systems

❌ **Poor Fit for Document Data**
- Conversations are hierarchical (user → messages → intents)
- Fitting into relational tables is awkward
- Requires multiple JOINs to reconstruct

❌ **Limited Horizontal Scaling**
- Reads can scale with read replicas
- Writes must go to single master
- At 1,000 concurrent users, single writer becomes bottleneck

### Cost Comparison: RDS vs MongoDB

**RDS (db.t3.medium):**
- ~$60/month

**MongoDB Atlas (M10 cluster):**
- ~$57/month

**Cost is similar, but MongoDB is better fit**

### Verdict: ❌ RDS is wrong model for chatbot data

---

## 🔍 Option 2: Amazon DynamoDB - ⚠️ **Possible but Suboptimal**

### What is DynamoDB?

AWS-native NoSQL key-value store, serverless and infinitely scalable.

### Why DynamoDB Works Well For:

✅ Simple key lookups  
✅ Massive scale (millions of requests/sec)  
✅ No servers to manage  
✅ Pay-per-request pricing  

### Problems for Chatbot Data:

❌ **Complex Querying Difficult**
```python
# With MongoDB, easy:
db.conversations.find({"user_id": 123, "timestamp": {"$gt": yesterday}})

# With DynamoDB, complex:
# - Requires DynamoDB Query or Scan
# - Scan is slow and expensive on large tables
# - Secondary indexes add complexity
```

❌ **Changing Access Patterns**
- Today: "Find conversations by user"
- Tomorrow: "Find conversations by bot_id"
- Each new pattern might require new index

❌ **Code Rewrite Required**
- Project already uses MongoDB drivers
- Switching to DynamoDB requires code changes
- Risk of bugs during migration

❌ **JSON-like Data is Awkward**
```python
# DynamoDB item example
{
  "user_id": "123",  # Must be String in DynamoDB
  "conversation": {
    "messages": [  # Complex nested structures are stored as strings
      {"text": "...", "intent": "..."}
    ]
  }
}

# MongoDB handles this natively with rich types
```

### Cost Analysis: DynamoDB

**On-Demand Pricing:**
- Read: $1.25 per 1M reads
- Write: $6.25 per 1M writes

**For 1,000 conversations/day, each with 5 reads + 1 write:**
- Reads: 5,000/day = 150,000/month = $0.19/month
- Writes: 1,000/day = 30,000/month = $0.19/month
- Total: ~$0.38/month (very cheap!)

**Provisioned Capacity:**
- 100 RCUs + 50 WCUs = ~$50/month
- Better for predictable workloads

**Verdict: DynamoDB is cheaper, but requires code changes**

### Verdict: ⚠️ **Technically possible, but requires major refactoring**

---

## 🔍 Option 3: MongoDB Atlas - ✅ **CHOSEN**

### What is MongoDB Atlas?

Fully managed MongoDB in the cloud. Document database with flexible schema.

### Why MongoDB is Perfect for This Project:

✅ **Already Integrated**
- Project uses PyMongo (Python MongoDB driver)
- Zero code changes required
- Immediate deployment

✅ **Natural Document Model**
```python
# MongoDB stores documents natively
conversation = {
    "user_id": "123",
    "messages": [
        {
            "text": "What's my order status?",
            "intent": "order_status",
            "confidence": 0.95,
            "entities": {"order_id": "456"}
        },
        {
            "text": "Your order 456 is shipped",
            "type": "bot_response"
        }
    ],
    "created_at": datetime.now(),
    "session_data": {
        "context": {...},
        "memory": {...}
    }
}

# Store directly - no schema mapping needed
db.conversations.insert_one(conversation)
```

✅ **Schema Flexibility**
- Intents can evolve without migrations
- New fields added on-the-fly
- Different conversations can have different structures

✅ **Powerful Queries**
```python
# Find conversations by user, sorted by recency
conversations = db.conversations.find(
    {"user_id": user_id}
).sort("created_at", -1).limit(10)

# Find by intent type (across nested documents)
intent_stats = db.conversations.aggregate([
    {"$unwind": "$messages"},
    {"$match": {"messages.intent": "order_status"}},
    {"$group": {"_id": "$user_id", "count": {"$sum": 1}}}
])
```

✅ **High Availability**
- Automatic replication across 3 zones
- Automatic failover
- Point-in-time backup

✅ **Scalability**
- Vertical: Bigger instance size
- Horizontal: Sharding (if needed)
- MongoDB Atlas handles ops

### MongoDB Atlas Pricing

**M10 Cluster (Dev/Staging):**
- 2GB storage
- $57/month
- Suitable for 10,000+ conversations

**M20 Cluster (Production):**
- 20GB storage
- $213/month
- Suitable for 100,000+ conversations

**Total for 3 environments: ~$285/month**

### Comparison with DocumentDB

AWS DocumentDB is MongoDB-compatible alternative:
- More expensive per month (~$100+)
- Still requires setup and maintenance
- MongoDB Atlas is fully managed with better pricing

### Verdict: ✅ **MongoDB Atlas is PERFECT choice**

**Reasons:**
- Zero code changes ✓
- Natural document model ✓
- Fully managed operations ✓
- Flexible schema ✓
- Proven reliability ✓
- Cost-effective ✓

---

## ⚡ Part 3: Caching Strategy

### Problem: Why Cache at All?

Without caching, every request hits the database and recomputes intents:
```
User sends message
    ↓
Backend receives request
    ↓
Query DB for bot config (200ms)
    ↓
Query DB for user session (150ms)
    ↓
Run NLU processing (500ms)
    ↓
Total: 850ms before response
    ↓
User sees delay
```

With caching:
```
User sends message
    ↓
Check Redis for bot config (2ms) ← HIT
    ↓
Check Redis for user session (2ms) ← HIT
    ↓
Run NLU processing (500ms)
    ↓
Total: 504ms - 340ms improvement!
```

---

## 🔍 Option 1: ElastiCache Redis - ✅ **CHOSEN**

### What is Redis?

In-memory key-value store with advanced data structures.

### Why Redis for Chatbot:

✅ **Extremely Low Latency**
- 1-2ms response time vs 200ms+ database

✅ **Shared Cache**
- All 5 backend pods access same cache
- Conversation context shared across replicas

✅ **TTL Support**
```python
# Session expires after 1 hour
cache.setex("session:user123", 3600, session_data)
```

✅ **Advanced Structures**
- Lists: Recent intents
- Sets: User interactions
- Sorted sets: Leaderboards
- Hashes: Bot configurations

### Use Cases in Chatbot:
```python
# 1. Conversation Context
cache.set(f"context:user_{user_id}", context_data, ex=3600)

# 2. Bot Configurations
cache.set("bot_config:default", config_json, ex=86400)

# 3. User Session State
cache.hset(f"session:{session_id}", mapping=session_state)

# 4. Rate Limiting
cache.incr(f"ratelimit:{user_id}:requests")

# 5. Frequently Accessed Intents
cache.zadd("popular_intents", {"order_status": 100, "faq": 50})
```

### Redis Pricing

**cache.t4g.micro (dev):**
- 0.5GB
- $11/month

**cache.t4g.small (staging):**
- 1.37GB
- $18/month

**cache.r7g.large (prod):**
- 15.5GB
- $100/month

**Total: ~$130/month for 3 environments**

### High Availability Options

**Single Node (Dev):**
- $11/month
- No redundancy

**Multi-AZ Replica (Staging/Prod):**
- Automatic failover
- Extra cost (~50% more)
- Recommended for prod: $150/month

### Verdict: ✅ **Redis is ESSENTIAL for performance**

---

## 🔍 Option 2: ElastiCache Memcached - ⚠️ **Simpler Alternative**

### What is Memcached?

Ultra-simple in-memory cache, key-value only.

### Differences from Redis:

| Feature | Redis | Memcached |
|---------|-------|-----------|
| Data Structures | Lists, Sets, Sorted Sets, Hashes | Key-Value only |
| Persistence | Optional RDB/AOF | None |
| TTL | Per-key | Global or per-key |
| Replication | Yes (cluster mode) | No |
| Transactions | Yes | No |

### When Memcached is Better:

✅ Extremely simple use case  
✅ No need for advanced structures  
✅ Throwaway cache (OK to lose on restart)  

### Problems for Chatbot:

❌ Can't store complex session data (needs hashes/lists)  
❌ No persistence (lose cache on restart)  
❌ No replication (single point of failure)  

### Verdict: ⚠️ **Memcached is too simple for chatbot needs**

---

## 📤 Part 4: Messaging & Async Processing

### Problem: Why Messaging Needed?

**Without messaging:**
```
User sends message
    ↓
API processes request
    ↓
Save to MongoDB
    ↓
Update analytics
    ↓
Trigger model retraining
    ↓
Send Slack notification
    ↓
Wait for ALL to complete (5+ seconds)
    ↓
Send response to user (slow!)
```

**With messaging:**
```
User sends message
    ↓
API processes request
    ↓
Save to MongoDB (quick)
    ↓
Put "log_conversation" message in SQS
    ↓
Put "update_analytics" message in SQS
    ↓
Return response to user (fast! < 1 second)
    ↓
(Background) Workers pick up SQS messages
    ↓
(Background) Workers update analytics
    ↓
(Background) Workers trigger retraining
```

---

## 🔍 Option 1: Amazon SQS - ✅ **CHOSEN**

### What is SQS?

Simple queue service: producer puts messages, consumer picks them up.
```
┌─────────────┐
│   Backend   │ (Producer)
│ API Service │
└──────┬──────┘
       │ Put message
       ▼
┌──────────────────────┐
│   Amazon SQS         │
│   (Message Queue)    │
└──────┬───────────────┘
       │ Poll message
       ▼
┌──────────────────────┐
│  Worker Pods         │ (Consumers)
│  (Process messages)  │
└──────────────────────┘
```

### Why SQS for Chatbot:

✅ **Decouples Components**
- API doesn't wait for logging
- Workers independently scale

✅ **Reliable Delivery**
- Messages retained for 14 days (default)
- Automatic retries
- Dead-letter queue for failures

✅ **Async Processing**
```python
# Backend API
def chat_message(message):
    # Process quickly
    response = nlu.process(message)
    
    # Queue slow tasks
    sqs.send_message(
        QueueUrl='analytics-queue',
        MessageBody=json.dumps({
            'user_id': user_id,
            'intent': response.intent
        })
    )
    
    return response  # Return immediately!

# Worker (separate pods)
def process_analytics():
    while True:
        message = sqs.receive_messages(MaxNumberOfMessages=10)
        for msg in message:
            # Takes 2+ seconds, but doesn't block user
            update_analytics_database(msg.body)
            msg.delete()
```

✅ **Cheap**
- $0.40 per million requests
- At 1,000 messages/day: $0.00012/month

✅ **Auto-scaling**
- Workers scale based on queue depth
- If 10,000 messages pile up, scale workers to 100

### Use Cases in Chatbot:
```python
1. Conversation Logging
   - Save chat history asynchronously

2. Analytics Update
   - Track intent distribution
   - User behavior analysis

3. Model Retraining
   - Trigger weekly retraining
   - Don't block API

4. Notifications
   - Send Slack/email alerts
   - Don't wait for external services

5. Data Export
   - Export conversations for backup
   - Long-running task
```

### SQS Configuration

**Standard Queue (Recommended):**
- At-least-once delivery (might get duplicates)
- Unlimited throughput
- $0.40 per million requests

**FIFO Queue:**
- Exactly-once delivery
- 300 messages/second max
- $0.50 per million requests
- Useful for critical sequences

**For chatbot: Standard Queue is fine**
- Analytics duplicates don't hurt
- Throughput is unlimited

### Pricing

**At 1,000 messages/hour (24,000/day):**
- 720,000 messages/month
- Cost: 720,000 / 1,000,000 × $0.40 = $0.29/month

**Very cheap!**

### Verdict: ✅ **SQS is IDEAL for async tasks**

---

## 🔍 Option 2: Amazon SNS (Pub/Sub) - ⚠️ **Supportive Role**

### What is SNS?

Publish-subscribe service: one message → multiple subscribers.
```
Backend publishes event
    ↓
SNS distributes to subscribers:
├─ Email
├─ Slack webhook
├─ SQS queue
└─ HTTP endpoint
```

### When SNS Works:

✅ Broadcasting events to many targets  
✅ Fan-out notifications  
✅ Pub/sub patterns  

### For Chatbot:

**Limited use cases:**
- Alert ops team when error rate spikes
- Notify admins of model retraining completion
- Broadcast to multiple monitoring systems

**Not suitable as main messaging**

### Verdict: ⚠️ **SNS useful for notifications, not main messaging**

---

## 🔍 Option 3: Amazon EventBridge - ⚠️ **Over-Engineering**

### What is EventBridge?

Event bus with rule-based routing, schema validation, integrations.

### When EventBridge Works:

✅ Many microservices  
✅ Complex event workflows  
✅ SaaS integrations  
✅ Event schema validation  

### For Chatbot:

**Currently overkill:**
- Single backend service
- Simple event patterns
- No multi-service orchestration

**Future consideration:**
- If 5+ microservices: consider EventBridge
- Today: SQS is simpler

### Verdict: ⚠️ **EventBridge is over-engineering for current scope**

---

## 💾 Part 5: Object Storage

### Problem: Where to Store Non-Database Data?

**Data that doesn't fit in database:**
- Frontend static assets (HTML, CSS, JS)
- User-uploaded files
- Log files and exports
- Trained ML models
- Terraform state files
- Backup data

---

## 🔍 Option 1: Amazon S3 - ✅ **CHOSEN**

### What is S3?

Object storage service: store any file in the cloud.
```
Frontend app → CloudFront (CDN) → S3 bucket
              (Caches files globally)
```

### Why S3 for Chatbot:

✅ **Hosting Static Frontend**
```
1. Build Next.js app: npm run build
2. Deploy to S3 bucket
3. CloudFront caches globally
4. Users get instant load times
5. Cost: pennies/month
```

✅ **Logs & Exports**
```python
# Export conversations
export_data = get_conversations()
s3.put_object(
    Bucket='chatbot-exports',
    Key=f'exports/{date}/conversations.json',
    Body=json.dumps(export_data)
)
```

✅ **ML Artifacts**
- Trained models stored in S3
- Workers download models from S3
- New versions deployed without container rebuild

✅ **Backup Storage**
- Daily backups of MongoDB exported to S3
- 11 nines durability
- Lifecycle policies move old files to Glacier

✅ **Terraform State**
- terraform.tfstate stored in S3
- Lock file in DynamoDB
- Team collaboration on infrastructure

### S3 Pricing

**At 10GB of data:**
- Storage: 10GB × $0.023/GB = $0.23/month
- GET requests: minimal cost
- **Total: < $1/month**

**With CloudFront (frontend delivery):**
- CloudFront egress: $0.085/GB
- For 1TB/month traffic: $85/month
- With caching, typical: 10-20% hit, so $8-16/month

### S3 Best Practices
```python
# 1. Versioning enabled (safe rollback)
s3.put_bucket_versioning(Bucket='chatbot-exports', VersioningConfiguration={'Status': 'Enabled'})

# 2. Lifecycle policies (cost optimization)
# Move old exports to Glacier after 90 days
# Delete after 2 years

# 3. Server-side encryption
s3.put_object(
    Bucket='chatbot-exports',
    Key='data.json',
    ServerSideEncryption='AES256'
)

# 4. Public access blocked (security)
s3.put_public_access_block(
    Bucket='chatbot-exports',
    PublicAccessBlockConfiguration={
        'BlockPublicAcls': True,
        'BlockPublicPolicy': True,
        'IgnorePublicAcls': True,
        'RestrictPublicBuckets': True
    }
)
```

### Verdict: ✅ **S3 is essential, universal choice**

---

## 🔍 Option 2: Amazon EBS - ❌ **NOT Suitable**

### What is EBS?

Block storage attached to EC2 instances (like a hard drive).

### When EBS Works:

✅ OS disks for servers  
✅ Database volumes  
✅ Single-instance persistent storage  

### For Chatbot:

❌ **Data is bound to one server**
- If EC2 dies, data is lost (unless snapshot)
- Can't be shared across pods

❌ **Stuck to EKS nodes**
- Pods run in different nodes
- Can't migrate pod to different node

❌ **Wrong abstraction**
- Chatbot data is ephemeral
- Backend pods are stateless (state in MongoDB/Redis)

### Verdict: ❌ **EBS is not suitable**

---

## 🔍 Option 3: Amazon EFS - ⚠️ **Overcomplicated**

### What is EFS?

Shared network file system (like NFS).

### When EFS Works:

✅ Multiple instances sharing files  
✅ Stateful workloads  
✅ Legacy apps needing shared storage  

### For Chatbot:

❌ **App is already stateless**
- MongoDB holds state
- Redis caches state
- No need for shared file system

❌ **More expensive than S3**
- EFS: $0.30/GB/month
- S3: $0.023/GB/month
- 13x more expensive!

### Verdict: ⚠️ **EFS is overkill for chatbot**

---

## 📊 Final Architecture Summary Table

| Component | Service | Cost/Month | Justification |
|-----------|---------|-----------|---------------|
| **Compute** | EKS | $73 + $100 | Long-running APIs, ML isolation, Helm + GitOps |
| **Database** | MongoDB Atlas M10 | $57 × 3 = $171 | Document model, existing code, flexible schema |
| **Caching** | ElastiCache Redis | ~$130 | Session storage, conversation context, performance |
| **Messaging** | SQS | < $1 | Async processing, decoupling, cheap |
| **Storage** | S3 | < $5 | Static frontend, logs, models, Terraform state |
| **Frontend CDN** | CloudFront | $10-20 | Global distribution, caching |
| **ECR** | Container Registry | < $1 | Docker image storage |
| **Monitoring** | CloudWatch | $10-20 | Logs, metrics, alarms |
| **TOTAL/MONTH** | | **$560** | All 3 environments (dev, staging, prod) |

---

## 🎓 Key Takeaways

### Compute
- **EKS** beats Lambda/AppRunner/ECS because:
  - Long-running stateful APIs need it
  - ML workloads need fine-grained resource control
  - Industry standard with Helm + GitOps integration

### Database
- **MongoDB Atlas** beats RDS/DynamoDB because:
  - Existing codebase uses MongoDB
  - Document model fits conversation data
  - Schema flexibility for evolving NLU

### Cache
- **Redis** beats Memcached because:
  - Advanced structures for complex state
  - Replication for HA
  - TTL for sessions

### Messaging
- **SQS** beats SNS/EventBridge because:
  - Simple queue for async tasks
  - Cheap
  - Workers scale independently

### Storage
- **S3** is universal because:
  - Cheap
  - Durable
  - Perfect for static assets, logs, models

---

## ✅ Final Conclusion

**The selected architecture balances operational simplicity, scalability, and cost efficiency while aligning with the existing codebase and supporting future growth of the AI chatbot platform.**

Total estimated cost: **$560/month** for 3 production-grade environments

Next: See [AWS Account Structure](02-AWS-ACCOUNT-STRUCTURE.md) for security and multi-account design.

