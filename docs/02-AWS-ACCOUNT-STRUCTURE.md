# Part 2: AWS Account Structure & Security

**Document Version**: 1.0  
**Last Updated**: January 29, 2026  
**Audience**: AWS Architects, Security Engineers, DevOps Teams

---

## Executive Summary

This document outlines a production-grade AWS account structure for deploying the AI Chatbot Framework with strong security isolation, centralized logging, and governance controls.

The design follows AWS best practices using AWS Organizations and Control Tower, with separate accounts for environments (dev, staging, UAT, production), security functions, and shared services.

**Total Cost**: ~$200-300/month for account infrastructure and security services

---

## Section 1: Why Multi-Account Architecture?

### Single-Account Risks

Deploying all environments in one AWS account creates dangerous blast radius scenarios:

1. Accidental resource deletion
   - One developer deletes production database by mistake
   - All customers affected
   - No account-level protection

2. Security breach escalation
   - Attacker gains access to dev credentials
   - Attacker can pivot to production
   - All resources compromised at once

3. Compliance violations
   - Auditors see all resources mixed together
   - Hard to prove production is properly isolated
   - Difficult to maintain separate change logs

4. Billing opacity
   - Can't separately bill engineering vs. operations
   - Can't track cost per environment
   - Chargebacks are complex

### Multi-Account Benefits

With separate AWS accounts:

- Strong isolation: Attacker in dev account cannot access prod
- Compliance: Production account has stricter controls
- Billing: Each environment has separate bill
- Access control: Team members access only their environment
- Blast radius: Mistakes affect only one environment
- Audit trail: CloudTrail logs can't be deleted across accounts

---

## Section 2: Proposed AWS Account Structure

### Account Hierarchy
```
AWS Organizations Root
│
├── Management Account
│   └── Billing, Organizations, SCPs
│
├── Security / Audit Account
│   └── CloudTrail, Config, GuardDuty, Security Hub
│
├── Shared Services Account
│   └── ECR, Route53, ACM, S3 for logs
│
├── Sandbox Account
│   └── Experimentation, learning
│
├── Development Account
│   └── Dev EKS, databases
│
├── UAT / Staging Account
│   └── Staging EKS, pre-prod testing
│
└── Production Account
    └── Production EKS, live application
```

### Account Inventory

| Account Name | Account Purpose | Resources | Access |
|--------------|-----------------|-----------|--------|
| Management | Organization root, billing governance | AWS Organizations, billing alerts | C-level, Finance |
| Security/Audit | Centralized logging and monitoring | CloudTrail, Config, GuardDuty, Security Hub | Security team |
| Shared Services | Common infrastructure | ECR repositories, DNS, certificates, shared S3 | DevOps, All teams |
| Sandbox | Safe experimentation | EKS test cluster, temporary resources | Developers, QA |
| Development | Active development | Dev EKS cluster, MongoDB, Redis | Development team |
| Staging | Pre-production testing | Staging EKS, test databases | QA team, Staging |
| Production | Live application | Production EKS, prod databases, backups | On-call team, limited |

---

## Section 3: Individual Account Roles and Responsibilities

### Management Account

Purpose: Organization administration and billing

Responsibilities:
- Create/delete AWS accounts
- Set organization-wide Service Control Policies (SCPs)
- Manage consolidated billing
- Configure AWS CloudTrail organization trail
- Set up AWS Control Tower

Resources deployed: None (governance only)

Access:
- AWS Organizations administrators
- Finance/billing team
- Security team (read-only)

Cost:
- No EC2/ECS/EKS charges
- Organization trail logging: < $1/month
- AWS Organizations: Free

Protection:
- Root user protected with MFA and hardware token
- MFA requirement for all human users
- SCPs prevent account closure

Example SCP (preventing resource deletion):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "ec2:TerminateInstances",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1"
        }
      }
    }
  ]
}
```

---

### Security / Audit Account

Purpose: Centralized security logging and threat detection

Responsibilities:
- Receive CloudTrail logs from all accounts
- Analyze logs for suspicious activity
- Store logs long-term for compliance
- Run GuardDuty threat detection
- Manage AWS Config rules

Resources:
- CloudTrail organization trail (logs all accounts)
- S3 bucket for log storage with versioning
- GuardDuty detector (admin account)
- AWS Config aggregator
- Security Hub for findings

Access:
- Security team: Full access
- Auditors: Read-only access
- Developers: No access

Cost:
- CloudTrail: $2/100,000 API calls per organization = ~$5/month
- GuardDuty: $30/month per account × 7 accounts = $210/month
- AWS Config: $0.003 per configuration item
- Total: ~$250/month

Protection:
- S3 MFA Delete enabled (can't delete logs without MFA)
- S3 versioning enabled
- Bucket policies prevent account deletion of objects
- Log file validation enabled in CloudTrail

---

### Shared Services Account

Purpose: Resources shared across multiple accounts

Responsibilities:
- Host ECR repositories for Docker images
- Manage Route53 hosted zones
- Store ACM certificates
- Provide shared S3 buckets

Resources:
- ECR repositories (backend, frontend, ml, worker)
- Route53 hosted zone (chatbot.example.com)
- ACM certificates (TLS/SSL)
- S3 bucket for shared artifacts
- S3 bucket for Terraform state

Access:
- DevOps team: Full access
- CI/CD: Pull/push ECR images
- All accounts: Read ECR images
- Developers: Read-only

Cost:
- ECR storage: ~$5/month (at 5 images × 500MB)
- Route53: $0.50/month + $0.40 per 1M queries
- ACM: Free (AWS certificates)
- S3: < $5/month
- Total: ~$12/month

Protection:
- ECR image scanning enabled (finds vulnerabilities)
- ECR private repositories
- Route53 DNSSEC enabled
- S3 versioning enabled
- Cross-account role-based access

Example ECR cross-account access:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::DEV_ACCOUNT_ID:role/EKSNodeRole"
      },
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ]
    }
  ]
}
```

---

### Sandbox Account

Purpose: Safe experimentation and learning

Responsibilities:
- Allow developers to test AWS services
- Prevent impact on production
- Control costs through budgets

Resources:
- EKS test cluster (optional)
- EC2 instances for testing
- RDS/MongoDB for experiments
- Temporary resources

Access:
- Developers: Full access
- Financial controls: Budget alerts at $100/month

Cost:
- Developer configured (expected < $100/month)
- Budget alert at $50/month

Protection:
- Budget alert prevents runaway costs
- No production data allowed
- Annual resource cleanup (delete unused)

---

### Development Account

Purpose: Active development and feature work

Responsibilities:
- Run development EKS cluster
- Host dev databases
- Deploy development versions of app
- Test integrations

Resources:
- EKS cluster (1 node for dev)
- MongoDB Atlas M10 (dev)
- ElastiCache Redis (small)
- SQS queues for testing
- CloudWatch logs

Access:
- Development team: Full access
- DevOps: Full access
- QA: Read access
- Production team: No access

Cost:
- EKS: $73/month control plane + 1 node @ $30 = $103/month
- MongoDB Atlas: $57/month
- Redis: $11/month (micro)
- Data transfer: ~$5/month
- Total: ~$176/month

Protection:
- CloudTrail logging (all API calls)
- CloudWatch log retention: 30 days
- No public RDS endpoints
- Network policies for pod security

---

### UAT / Staging Account

Purpose: Pre-production testing environment

Responsibilities:
- Mirror production architecture
- Run integration tests
- Perform load testing
- Validate deployments before prod

Resources:
- EKS cluster (2 nodes for staging)
- MongoDB Atlas M20 (staging)
- ElastiCache Redis (cache.t4g.small)
- SQS for testing async jobs
- CloudWatch dashboards

Access:
- QA team: Full access
- Development team: Limited (no destructive actions)
- DevOps: Full access
- Production team: Read-only

Cost:
- EKS: $73 + 2 nodes @ $30 = $133/month
- MongoDB Atlas: $85/month (M20)
- Redis: $18/month (small)
- Total: ~$236/month

Protection:
- Similar to production (testing production setup)
- CloudTrail logging
- VPC Flow Logs for network monitoring
- Automated backup of MongoDB
- Read replicas for redundancy

---

### Production Account

Purpose: Live application serving customers

Responsibilities:
- Run production EKS cluster
- Maintain production databases
- Ensure high availability
- Respond to incidents

Resources:
- EKS cluster (3-10 nodes)
- MongoDB Atlas M30+ (production)
- ElastiCache Redis (cache.r7g.large)
- Auto Scaling Groups
- CloudWatch alarms
- SNS for alerts

Access:
- On-call team: Emergency access only
- Developers: Read-only (no delete)
- DevOps: Full access
- Security team: Audit access
- Product team: Metrics/dashboards

Cost:
- EKS: $73 + 3-6 nodes @ $30 = $163-253/month
- MongoDB Atlas: $200+/month (M30)
- Redis: $100+/month (HA)
- Data transfer: $20-50/month
- Total: ~$450-600/month

Protection (Strict):
- CloudTrail logging (all API calls)
- GuardDuty threat detection
- AWS Config continuous monitoring
- Security Hub for compliance
- VPC Flow Logs (all network traffic)
- KMS encryption for data at rest
- Secrets stored in AWS Secrets Manager
- No SSH/RDP access to instances
- All changes via CI/CD pipeline only
- MFA required for human access
- Production access requires additional approval

Example production access requirement:
```
1. Engineer wants to access production logs
2. Engineer assumes role: assume-role-prod-read-only
3. STS requires MFA code
4. CloudTrail records: who, what, when
5. Session logs to central account
6. Time-limited (1 hour)
7. IP restriction (office only)
```

---

## Section 4: AWS Organizations & Service Control Policies

### Using AWS Organizations

AWS Organizations provides:
- Centralized account management
- Consolidated billing
- Service Control Policies (enforce governance)
- CloudTrail organization trail

Setup:
```bash
# Create organization (in management account)
aws organizations create-organization --FeatureSet ALL

# Create OU (Organizational Unit)
aws organizations create-organizational-unit \
  --parent-id r-abc123 \
  --name "Production"

# Create account
aws organizations create-account \
  --email prod-account@company.com \
  --account-name "Production"

# Attach SCP
aws organizations put-policy \
  --content file://policy.json \
  --description "Prevent production deletion" \
  --name "PreventProdDeletion" \
  --type SERVICE_CONTROL_POLICY
```

### AWS Control Tower (Recommended)

Control Tower automates account setup and governance:

Features:
- Pre-configured landing zone
- Automated security baseline
- Centralized logging enabled by default
- CloudTrail organization trail created
- GuardDuty enabled across accounts
- AWS Config enabled

Setup costs:
- Control Tower: Free
- Additional logging: ~$100-200/month
- GuardDuty: ~$30/month per account

Control Tower guardrails:
- Preventive: Stop disallowed actions (SCP-based)
- Detective: Alert on non-compliance (Config-based)

Example guardrails to enable:
- Disallow public RDS snapshots
- Require CloudTrail enabled
- Require MFA on root account
- Restrict EC2 instance types
- Require encryption for S3
- Prevent region usage outside approved list

---

## Section 5: Identity & Access Management with SSO

### Why AWS SSO?

Traditional IAM users have problems:
- Hard to manage 50+ developers with individual IAM users
- Difficult to enforce MFA
- No integration with company directory (Active Directory)
- Provisioning/deprovisioning takes manual work

AWS SSO solves this:
- Connects to company directory (AD, Okta, OneLogin)
- Automatic provisioning
- Enforces MFA
- Fine-grained role-based access
- Audit trail of who accessed what

### SSO Setup
```bash
# 1. Enable AWS SSO (in management account)
aws sso create-instance

# 2. Connect to company directory
# - In AWS Console: AWS SSO > Settings > Change identity source
# - Select: Active Directory or External identity provider
# - Complete connection flow

# 3. Create user groups in SSO
# - Developers
# - QA
# - DevOps
# - Security

# 4. Create permission sets (roles)
# - DeveloperAccess
# - QAAccess
# - DevOpsAccess
# - SecurityReadOnly
# - ProdOnCallAccess

# 5. Assign users to groups to accounts
# - Developers group -> Dev account with DeveloperAccess
# - QA group -> Staging account with QAAccess
# - DevOps -> All accounts with DevOpsAccess
```

### Role-Based Access Control

Example access matrix:

| Role | Dev Account | Staging | Production | Security/Audit |
|------|-------------|---------|------------|----------------|
| Developer | Full | Limited | None | None |
| QA | Read-only | Full | Read-only | None |
| DevOps | Full | Full | Full | Read-only |
| Security | Read-only | Read-only | Read-only | Full |
| On-Call | Read-only | Read-only | Full (emergencies) | None |
| Finance | Billing only | Billing only | Billing only | None |

### Production Access Requirements

For production, implement additional controls:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeClusters",
        "logs:GetLogEvents"
      ],
      "Resource": "*",
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": "10.0.0.0/8"  // Office VPN only
        },
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"  // MFA required
        }
      }
    }
  ]
}
```

Workflow for production changes:
```
1. Engineer creates change request in Jira
2. Manager reviews and approves
3. Change enters change window (scheduled time)
4. Engineer uses CI/CD to deploy (not manual)
5. On-call engineer monitors deployment
6. CloudTrail records all actions
7. Post-incident review if issues occur
```

---

## Section 6: Centralized Security & Monitoring Services

### AWS CloudTrail

Records all API calls to AWS services.

Configuration:
```bash
# Create organization trail (logs all accounts)
aws cloudtrail create-trail \
  --name organization-trail \
  --s3-bucket-name org-cloudtrail-logs \
  --is-multi-region-trail

# Start logging
aws cloudtrail start-logging --trail-name organization-trail

# Enable for all members
aws cloudtrail put-event-selectors \
  --trail-name organization-trail \
  --advanced-event-selectors '[{
    "Field": "eventCategory",
    "Equals": ["Management", "Data"]
  }]'
```

Use cases:
- Audit: Who deleted that database?
- Compliance: Prove all prod changes are logged
- Incident response: Reconstruct attack timeline
- Cost analysis: Find who provisioned expensive resources

Retention:
- Security/Audit account: 7 years (compliance)
- Other accounts: 90 days

---

### Amazon GuardDuty

Detects threats and suspicious activity.

Configuration:
```bash
# Enable in Security account (admin)
aws guardduty create-detector --enable

# Add member accounts
aws guardduty create-members \
  --detector-id xxx \
  --account-details '[{
    "AccountId": "dev-account-id",
    "Email": "dev@company.com"
  }]'

# Auto-enable for new accounts
aws guardduty update-organization-configuration \
  --detector-id xxx \
  --auto-enable true
```

Detections:
- Unusual API calls (unauthorized access attempts)
- Cryptocurrency mining (compromised instances)
- Network reconnaissance (port scanning)
- Data exfiltration (large uploads)

Response:
- Findings sent to Security Hub
- SNS notifications to security team
- Automatic remediation (optional)

---

### AWS Config

Monitors resource configurations and detects drift.

Configuration:
```bash
# Enable AWS Config
aws configservice put-config-recorder \
  --config-recorder-name default

# Enable aggregator (in Security account)
aws configservice put-configuration-aggregator \
  --configuration-aggregator-name org-aggregator \
  --account-aggregation-sources '[{
    "AllAwsRegions": true,
    "AccountIds": ["all"]
  }]'

# Add rules
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "s3-bucket-server-side-encryption",
    "Source": {
      "SourceIdentifier": "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
    }
  }'
```

Rules to enforce:
- S3 buckets have encryption
- RDS uses encryption
- EC2 security groups restrict SSH
- IAM password policies enforced
- EBS volumes have backups
- VPC Flow Logs enabled

---

### AWS Security Hub

Central dashboard for all security findings.

Configuration:
```bash
# Enable Security Hub
aws securityhub create-hub

# Connect GuardDuty
aws securityhub update-standards-control \
  --standards-control-arn arn:aws:securityhub:region:account:standards-control/guardduty

# Enable organizational finding aggregation
aws securityhub create-finding-aggregator \
  --region-linking-mode ALL_REGIONS
```

Dashboard shows:
- Critical findings (immediate action needed)
- High severity (address this week)
- Medium severity (plan to fix)
- Compliance status (CIS benchmark, PCI-DSS)

Example critical findings:
- Unauthorized API calls (GuardDuty)
- S3 bucket made public (Config)
- RDS with public endpoint (Config)
- Root account usage (CloudTrail)

---

### Amazon CloudWatch

Aggregates logs and metrics from all services.

Setup:
```bash
# EKS logs to CloudWatch
aws logs create-log-group --log-group-name /eks/chatbot

# Lambda logs automatically
# RDS logs to CloudWatch

# Create dashboards
aws cloudwatch put-dashboard \
  --dashboard-name ChatbotDashboard \
  --dashboard-body file://dashboard.json

# Set up alarms
aws cloudwatch put-metric-alarm \
  --alarm-name HighCPUUsage \
  --alarm-actions arn:aws:sns:region:account:AlertTopic
```

Logs aggregation:
- EKS pod logs → CloudWatch
- RDS slow query logs → CloudWatch
- Application logs → CloudWatch
- VPC Flow Logs → CloudWatch
- CloudTrail → CloudWatch (optional)

Retention policy:
- Dev: 7 days (save cost)
- Staging: 30 days
- Production: 90 days
- Security/Audit: 1 year

---

## Section 7: Account Creation Workflow

### New Environment Setup

When creating a new account:
```
1. Request account in Service Now
2. Finance approves budget
3. Management account admin creates account
4. Control Tower configures baseline (automated)
5. Logging enabled automatically
6. Team notified with account access
7. Terraform provisions resources
8. Application deployed via CI/CD
9. Monitoring dashboards created
10. Access audit completed
```

Automation:
```bash
# Use AWS Control Tower API to create account
aws controltower create-managed-account \
  --managed-account-configuration '{
    "Name": "staging-2",
    "Email": "staging-2@company.com"
  }' \
  --tags "Environment=Staging"

# Trigger Terraform to provision resources
terraform apply -var="aws_account_id=123456789"

# Deploy application
helm install ai-chatbot ./helm/ai-chatbot \
  -n production \
  -f values/prod.yaml
```

---

## Section 8: Disaster Recovery Across Accounts

### Account-Level Backup Strategy

Backup approach:
```
Production MongoDB
    ↓
Daily backup to S3 (prod account)
    ↓
Copy to Shared Services S3 (cross-account)
    ↓
Copy to separate region (disaster recovery)
    ↓
Retention: 30 days production, 1 year archive
```

Cross-account backup:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::SHARED_SERVICES_ACCOUNT:root"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::prod-backups/*"
    }
  ]
}
```

Recovery procedure:
1. Detect issue in production account
2. Notify disaster recovery team
3. Request backup restore from Shared Services account
4. Restore to staging account for validation
5. Verify data integrity
6. Decide: restore to prod or keep using staging

---

## Section 9: Cost Allocation & Chargeback

### Cost Tracking

Use cost allocation tags:
```bash
# Tag resources by environment
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=Environment,Value=production Key=Application,Value=chatbot

# Use cost categories in AWS Cost Explorer
# Filter by: Environment, Application, Team
# View: Cost per environment per month
```

Cost allocation:
- Engineering team: Dev + Staging costs
- Operations team: Production + Security/Audit costs
- Finance: Management account for billing

Monthly breakdown:
```
Development: $176/month
Staging: $236/month
Production: $500/month
Security/Audit: $250/month
Shared Services: $12/month
Management: Free
Total: $1,174/month for all 7 accounts
```

---

## Section 10: Compliance & Auditing

### Compliance Frameworks

The multi-account setup supports:

- SOC2: Separate prod account, centralized logging
- PCI-DSS: Restricted prod access, encryption, audit logs
- HIPAA: KMS encryption, audit trails, data isolation
- GDPR: Data residency (specific regions), deletion policies

### Quarterly Audit Process
```
1. Run AWS Config compliance check
   - Result: 95% compliant
   
2. Review GuardDuty findings
   - Result: 2 low-severity findings (false positives)
   
3. Analyze CloudTrail logs
   - Result: All prod access via CI/CD, no manual changes
   
4. Check Security Hub
   - Result: 0 critical, 3 medium findings (remediated)
   
5. Validate backups
   - Result: All backups current, tested restore successful
   
6. Review IAM permissions
   - Result: 2 developers had unnecessary permissions (removed)
   
7. Generate compliance report
   - Result: Organization 98% compliant with standards
```

---

## Summary of Account Structure

| Account | Purpose | Cost/Month | Critical |
|---------|---------|-----------|----------|
| Management | Governance | Free | Yes |
| Security/Audit | Logging & monitoring | $250 | Yes |
| Shared Services | Common resources | $12 | Yes |
| Sandbox | Experimentation | $100 | No |
| Development | Feature development | $176 | No |
| Staging | Pre-production | $236 | Yes |
| Production | Live application | $500 | Yes |
| **TOTAL** | | **$1,274** | |

---

## Key Takeaways

1. Multi-account architecture provides security boundaries
2. AWS Control Tower automates baseline setup
3. AWS SSO integrates with company directory
4. Centralized logging in Security/Audit account
5. Production account has strictest controls
6. CI/CD is only way to change production
7. Cross-account access via assumed roles
8. Compliance and auditing built-in

---

## Next Steps

1. Enable AWS Organizations in management account
2. Set up AWS Control Tower
3. Create accounts for each environment
4. Configure AWS SSO with company directory
5. Enable CloudTrail organization trail
6. Set up GuardDuty and Security Hub
7. Create compliance baseline
8. Provision VPCs and networking
9. Deploy EKS clusters
10. Configure cross-account roles

---

## References

- AWS Organizations: https://docs.aws.amazon.com/organizations/
- AWS Control Tower: https://docs.aws.amazon.com/controltower/
- AWS SSO: https://docs.aws.amazon.com/singlesignon/
- AWS CloudTrail: https://docs.aws.amazon.com/cloudtrail/
- Security Best Practices: https://aws.amazon.com/architecture/security-identity-compliance/

