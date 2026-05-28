# 🔧 Project 5: Enterprise Jenkins CI/CD - Multi-Environment Pipeline

[![Jenkins](https://img.shields.io/badge/Jenkins-2.426-red)](https://jenkins.io)
[![Blue-Green](https://img.shields.io/badge/Deployment-Blue/Green-blue)](https://martinfowler.com/bliki/BlueGreenDeployment.html)

## 🏗️ Pipeline Architecture

```
Git Push
   │
   ▼ Kubernetes-based Jenkins agents (ephemeral)
┌──────────────────────────────────────────────┐
│  Stage 1: Checkout & Setup                   │
│  Stage 2: Parallel Tests                     │
│    ├── Unit Tests (pytest + coverage)        │
│    ├── Integration Tests                     │
│    └── SonarQube Quality Gate                │
│  Stage 3: Security Scan (Trivy + secrets)    │
│  Stage 4: Build & Push (with cache)          │
│  Stage 5: Deploy DEV (Rolling)               │ ← auto
│  Stage 6: Deploy STAGING (Canary: 10%→100%) │ ← auto
│  Stage 7: Prod Gate (Manual approval 24hr)   │ ← manual
│  Stage 8: Deploy PROD (Blue-Green)           │ ← approved
└──────────────────────────────────────────────┘
   │
   ▼ Post: Slack notification + Email on failure
```

## 🚀 Deployment Strategies

### Development: Rolling Update
```
Old pods → Gradually replaced → New pods
maxSurge: 1, maxUnavailable: 0
```

### Staging: Canary Deployment
```
10% traffic → Monitor 5min → Check error rate → 100% if healthy
```

### Production: Blue-Green
```
Current (blue) → Deploy new (green) → Switch traffic → Keep blue for rollback
Rollback: kubectl patch svc to point back to blue
```

## 🏛️ Jenkins Infrastructure

- **Jenkins Master**: EC2 t3.xlarge + EFS (persistent JENKINS_HOME)
- **Build Agents**: Kubernetes-based (ephemeral pods, auto-scale)
- **Tools in agents**: Docker, Helm, kubectl, Python, Node.js
- **Auth**: OIDC with AWS (no static credentials)

## 🛠️ Tech Stack

| Component | Technology |
|-----------|-----------|
| CI/CD Server | Jenkins 2.426 on Kubernetes |
| Agents | Kubernetes pods (ephemeral) |
| Code Quality | SonarQube |
| Container Registry | AWS ECR / GitHub CR |
| Secret Management | Jenkins Credentials + Vault |
| Notifications | Slack + Email |
| Infrastructure | Terraform (Jenkins master + EFS) |

## 🚀 Quick Start

```bash
# Deploy Jenkins on Kubernetes
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins \
  -f jenkins-values.yaml \
  --namespace jenkins --create-namespace

# Get admin password
kubectl exec -n jenkins jenkins-0 -- \
  cat /run/secrets/additional/chart-admin-password

# Configure pipeline:
# 1. New Item → Pipeline
# 2. Pipeline from SCM → Git → Your repo
# 3. Jenkinsfile path: Jenkinsfile
```

## 📚 Learning Objectives

1. ✅ Declarative Pipeline syntax
2. ✅ Parallel stages for faster CI
3. ✅ Kubernetes-based ephemeral agents
4. ✅ Manual approval gates
5. ✅ Canary + Blue-Green deployment strategies
6. ✅ SonarQube quality gate integration
7. ✅ Post-pipeline notifications (Slack + Email)
8. ✅ Jenkins infrastructure as code (Terraform)
