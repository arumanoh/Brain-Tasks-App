# Brain Tasks App — DevOps Deployment

A full AWS CI/CD pipeline deployment of [Brain-Tasks-App](https://github.com/arumanoh/Brain-Tasks-App) (a pre-built static React/Vite `dist/` bundle) to Amazon EKS, built as a DevOps assessment project.

---

## Architecture Overview

```
GitHub (main branch push)
        │
        ▼
  CodePipeline (brain-tasks-app-pipeline)
        │
        ├── Source Stage  → GitHub App connection
        │
        └── Build Stage   → CodeBuild (brain-tasks-app-build)
                                │
                                ├── docker build → push to ECR
                                └── kubectl apply → deploy to EKS
                                        │
                                        ▼
                              EKS Cluster (brain-tasks-cluster)
                                        │
                                Deployment (2 replicas, nginx:1.27-alpine)
                                        │
                                Service (LoadBalancer / NLB)
                                        │
                                        ▼
                                  End users (internet)
```

Logs from every stage (build, cluster control plane, and running application pods) are shipped to **CloudWatch Logs** for monitoring.

---

## Environment

| Component | Detail |
|---|---|
| EC2 (ops/admin host) | Ubuntu 26.04, `t3.small`, region `eu-north-1` |
| EC2 IAM role | `brain-tasks-app-ec2-role` — ECR full access, inline `eks:*`, `CloudWatchLogsReadOnlyAccess` |
| Working directory | `~/Brain-Tasks-App` |
| Source repo | `https://github.com/arumanoh/Brain-Tasks-App` (`main` branch) |

---

## 1. Containerization (Docker)

- **`Dockerfile`** — based on `nginx:1.27-alpine`, serves the pre-built static `dist/` bundle.
- **`nginx.conf`** — configured to listen on port 3000, with SPA fallback routing (`try_files` → `index.html`) so client-side React routes resolve correctly.
- Built and verified locally in a browser before pushing to ECR.

## 2. Image Registry (Amazon ECR)

- Repository: `brain-tasks-app` in `eu-north-1`
- Image URI: `367061003285.dkr.ecr.eu-north-1.amazonaws.com/brain-tasks-app`
- Status: `ACTIVE`, confirmed pushed successfully.

## 3. Kubernetes Cluster (Amazon EKS)

- Cluster: `brain-tasks-cluster`, created via `eksctl`
- Nodes: 2 × `t3.small`, Kubernetes version `1.34`, status `Ready`
- Control-plane logging: all 5 CloudWatch log types enabled (API server, audit, authenticator, controller manager, scheduler)

## 4. Kubernetes Manifests

- **`k8s/deployment.yaml`** — 2 replicas, readiness/liveness probes, resource limits set
- **`k8s/service.yaml`** — `type: LoadBalancer` with NLB annotation

Deployed and verified reachable via the Network Load Balancer:

```
arn:aws:elasticloadbalancing:eu-north-1:367061003285:loadbalancer/net/a097e0edcbe054381ae69dfb7caa746e/b814358c06e3bc51
```

## 5. Version Control

All infrastructure and deployment files committed to `main`:
- `Dockerfile`
- `nginx.conf`
- `.dockerignore`
- `k8s/deployment.yaml`, `k8s/service.yaml`
- `buildspec.yml`

## 6. CI — Amazon CodeBuild

- Project: `brain-tasks-app-build`
- Service role: `brain-tasks-codebuild-role`
  - ECR push permissions
  - Inline policy: `eks:DescribeCluster`, `eks:ListClusters`
- Kubernetes RBAC: role mapped to `system:masters` via
  ```
  eksctl create iamidentitymapping ...
  ```
- Build behavior (`buildspec.yml`): builds the Docker image → pushes to ECR → runs `kubectl apply` against the EKS cluster
- Verified: new pod revisions roll out successfully after each build

## 7. CD — AWS CodePipeline

- Pipeline: `brain-tasks-app-pipeline`
- Stages:
  1. **Source** — GitHub (via GitHub App connection)
  2. **Build** — CodeBuild (deploy step runs inside the buildspec; no separate deploy stage)
- Verified: a `git push` to `main` automatically triggers the pipeline end-to-end, both stages succeed.

### Issues encountered and resolved
- **GitHub connection silent failure**: the first CodeStar/CodeConnections GitHub connection showed as "Authorized" but was never actually installed as a GitHub App, so the pipeline never triggered. Fixed by deleting the connection and recreating it, this time completing the full **Install & Authorize** step in GitHub.
- **Pipeline service role missing permission**: added inline policy `AllowGitHubConnectionUse` (`codestar-connections:UseConnection`, `codeconnections:UseConnection`) to the CodePipeline service role.

## 8. Monitoring — CloudWatch

Three log sources feed into CloudWatch:

| Source | Log group | What it captures |
|---|---|---|
| CodeBuild | `/aws/codebuild/brain-tasks-app-build` | Build and deploy step output (enabled by default) |
| EKS control plane | `/aws/eks/brain-tasks-cluster/cluster` | API server, audit, authenticator, controller manager, scheduler |
| Application pods | `/aws/containerinsights/brain-tasks-cluster/application` | nginx access/error logs from running pods, via CloudWatch Container Insights + Fluent Bit |

**Application log pipeline setup:**
1. Attached `CloudWatchAgentServerPolicy` to the EKS node IAM role (`eksctl-brain-tasks-cluster-nodegro-NodeInstanceRole-...`).
2. Deployed the CloudWatch Container Insights quickstart manifest (CloudWatch Agent + Fluent Bit DaemonSets) to the `amazon-cloudwatch` namespace.
3. Verified both DaemonSets running (`1/1 Ready` on all nodes).
4. Confirmed all 4 Container Insights log groups created (`application`, `dataplane`, `host`, `performance`).
5. Verified live nginx access-log entries flowing from the `brain-tasks-app` pods into the `application` log group, including both `kube-probe` health-check traffic and real HTTP requests.

---

## Repository Structure

```
Brain-Tasks-App/
├── dist/                  # Pre-built static React/Vite bundle
├── Dockerfile
├── nginx.conf
├── .dockerignore
├── buildspec.yml
└── k8s/
    ├── deployment.yaml
    └── service.yaml
```

---

## Key Identifiers Reference

| Resource | Value |
|---|---|
| ECR image URI | `367061003285.dkr.ecr.eu-north-1.amazonaws.com/brain-tasks-app` |
| EKS cluster | `brain-tasks-cluster` (eu-north-1, k8s 1.34) |
| NLB ARN | `arn:aws:elasticloadbalancing:eu-north-1:367061003285:loadbalancer/net/a097e0edcbe054381ae69dfb7caa746e/b814358c06e3bc51` |
| CodeBuild project | `brain-tasks-app-build` |
| CodePipeline | `brain-tasks-app-pipeline` |
| Application log group | `/aws/containerinsights/brain-tasks-cluster/application` |

---

## Screenshots

See accompanying submission document (Word) for step-by-step verification screenshots covering Docker build/test, ECR push, EKS cluster creation, deployment rollout, pipeline execution, and CloudWatch log verification.
