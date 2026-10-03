# argocd-mlops-gitops

GitOps ML/AI deployment platform: **FastAPI → Docker → ECR → Argo CD → EKS → ALB**.

See [docs/architecture.md](docs/architecture.md) for the design and roadmap.

## Prerequisites

AWS CLI, kubectl, eksctl, Helm, Git, Docker.

```powershell
aws --version; kubectl version --client; eksctl version; helm version; docker --version
aws sts get-caller-identity
```

## 1. Placeholders (already filled in for this repo)

| Value | Files |
|-------------|-------|
| AWS account `482545366109` | `k8s/deployment.yaml`, `helm/ml-api/values.yaml` |
| GitHub user `avinashjaiengineer` | `argocd/application.yaml`, `argocd/project.yaml` |

## 2. Run locally

```powershell
docker build -t argocd-ml-api:1.0.0 .\app
docker run --rm -p 8000:8000 argocd-ml-api:1.0.0
# http://localhost:8000  /health  /predict  /docs
```

## 3. Push to GitHub

```powershell
git add .
git commit -m "Initial GitOps ML platform"
git remote add origin https://github.com/avinashjaiengineer/argocd-mlops-gitops.git
git push -u origin main
```

If the repo is private, register it with Argo CD:
`argocd repo add <url> --username <user> --password <PAT>`.

## 4. Create the AWS resources (this costs money)

```powershell
.\scripts\create-cluster.ps1
```

This creates the EKS cluster (with OIDC turned on) and the ECR repo, and
prints the ECR URI. **Tear it down when you're finished:**

```powershell
eksctl delete cluster --name argocd-mlops --region us-east-1
```

## 5. Push the first image

```powershell
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$ECR_URI = "$ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/argocd-ml-api"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com"
docker tag argocd-ml-api:1.0.0 "${ECR_URI}:1.0.0"
docker push "${ECR_URI}:1.0.0"
```

## 6. Install Argo CD and register the app

```powershell
.\scripts\install-argocd.ps1
kubectl port-forward svc/argocd-server -n argocd 8080:443   # https://localhost:8080
kubectl get pods -n ml-platform
```

## 7. Try the GitOps loop

Change `replicas: 2` to `3` in `k8s/deployment.yaml`, then commit and push.
Argo CD syncs the change within about 3 minutes, and
`kubectl get pods -n ml-platform` shows 3 pods.

## 8. CI: GitHub Actions to ECR

`.github/workflows/build-push.yaml` runs on every push that changes `app/`.
Setup:

1. Add GitHub as an OIDC identity provider in IAM:
   `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
2. Create an IAM role that trusts it, limited to
   `main` of this repo, and attach ECR push permissions (for example
   `AmazonEC2ContainerRegistryPowerUser`). GitHub now puts owner and repo IDs
   in the `sub` claim
   (`repo:avinashjaiengineer@331991776/argocd-mlops-gitops@1402965963:ref:refs/heads/main`),
   so allow both that form and the older
   `repo:avinashjaiengineer/argocd-mlops-gitops:ref:refs/heads/main`. If the
   step fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`,
   look up the `AssumeRoleWithWebIdentity` event in CloudTrail to see the
   exact `sub` that GitHub sent.
3. Add a repo variable `AWS_ROLE_ARN` with the role's ARN
   (Settings → Secrets and variables → Actions → Variables).
4. If `main` is a protected branch, allow `github-actions[bot]` to push to it,
   because the workflow commits the new image tag there.
