# Architecture

```
                    GitHub
                       │
                 application code (app/)
                       │
                       ▼
                 GitHub Actions  (.github/workflows/build-push.yaml)
                       │
          build image, tag = short commit SHA
                       │
                       ▼
                     ECR  (argocd-ml-api)
                       │
     workflow commits new tag to k8s/deployment.yaml
                       │
                       ▼
              Kubernetes manifests (k8s/)
                       │
                       ▼
                    Argo CD  (argocd/application.yaml)
                       │
                       ▼
                      EKS  (namespace: ml-platform)
                       │
                       ▼
                 ML/AI API Pods
                       │
                       ▼
          AWS ALB (k8s/ingress.yaml, via AWS LB Controller)
                       │
                       ▼
                    Internet
```

## How a change reaches the cluster

1. A developer pushes a change under `app/` to `main`.
2. GitHub Actions logs in to AWS through OIDC, builds the image and pushes
   it to ECR, tagged with the 7-character commit SHA.
3. The workflow rewrites the `image:` line in `k8s/deployment.yaml` and
   commits it back to `main`. That commit only touches `k8s/`, so it does not
   start the workflow again.
4. Argo CD polls the repo (every 3 minutes by default), sees the manifest
   change and syncs it to EKS.
5. Roll back by reverting the manifest commit (`git revert`), or with
   Argo CD's History and Rollback. Note that auto-sync puts back whatever is
   in Git, so reverting the commit in Git is the lasting fix.

Changes to infrastructure only (replica count, resources) skip steps 2 and 3:
edit `k8s/*.yaml`, push, and Argo CD syncs it.

## Components

| Path | Purpose |
|------|---------|
| `app/` | FastAPI service: `/`, `/health`, `/predict` |
| `k8s/` | Plain manifests that Argo CD syncs (top level only) |
| `k8s/ingress.yaml` | ALB Ingress (requires the AWS Load Balancer Controller) |
| `helm/ml-api/` | Level 2: the same app as a Helm chart, plus dev/prod values |
| `argocd/` | Argo CD namespace, AppProject and Application |
| `scripts/` | Create the EKS cluster and ECR repo, install Argo CD |

## Roadmap

- **Level 1:** Applications, sync, auto-sync, self-heal, prune, rollback
- **Level 2:** Point the Application at `helm/ml-api` with `valueFiles`
- **Level 3:** `environments/{dev,staging,production}/values.yaml`
- **Level 4:** ApplicationSet, AppProject RBAC, sync waves, hooks
- **Level 5:** AWS LB Controller, External Secrets, CloudWatch,
  Prometheus/Grafana, HPA
- **Level 6:** Replace `/predict` with a real model (e.g. fraud detection)
