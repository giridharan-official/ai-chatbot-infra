# Pending Work

**Document Version**: 1.0  
**Last Updated**: January 29, 2026

---

## Completed

Part 1: Architecture Design - DONE
Part 2: AWS Account Structure - DONE
Part 3: Kubernetes Infrastructure - DONE
Part 4: GitOps with ArgoCD - DONE (ArgoCD and GitHub Actions working)
Part 5: Observability - DONE

---

## Pending Items

### 1. CD Pipeline Error

GitHub Actions workflow has an error that needs to be fixed.

Issue: The image tag update in gitops/dev/values.yaml is not working correctly in CI pipeline.

Current state: Images are built and pushed to ECR successfully, but the values.yaml update step has issues.

Work needed: Debug and fix the CI workflow to properly update image tags.

### 2. ACM Certificate Configuration

Ingress is configured to use TLS certificate, but the certificate ARN is a placeholder.

Limitation: Domain chatbot.example.com is not available, so ACM certificate cannot be created.

Current workaround: Using HTTP (port 80) via ALB without TLS.

Work needed: When domain is available, create ACM certificate and update ingress with correct certificate ARN.

---

## Summary

Two items pending:

1. Fix CD pipeline image tag update (required)
2. Configure ACM certificate with actual domain (when domain available)

ArgoCD and GitHub Actions are working. Manual sync in ArgoCD UI functions correctly.

