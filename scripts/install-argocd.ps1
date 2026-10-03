<#
.SYNOPSIS
  Installs Argo CD into the current kubectl context and registers the ml-api app.

.PARAMETER SkipApp
  Install Argo CD only; do not apply argocd/project.yaml and argocd/application.yaml.
#>
param(
    [switch]$SkipApp
)

# Not "Stop": Windows PowerShell 5.1 treats kubectl warnings on stderr as
# terminating errors. Failures are checked through $LASTEXITCODE.
$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "kubectl context: $(kubectl config current-context)"

kubectl apply -f "$RepoRoot\argocd\namespace.yaml"

# --server-side is required: the Argo CD CRDs are too large for the
# last-applied-configuration annotation used by client-side apply.
kubectl apply -n argocd --server-side --force-conflicts `
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
if ($LASTEXITCODE -ne 0) { throw "Argo CD install failed." }

Write-Host "Waiting for Argo CD to become ready..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
kubectl get pods -n argocd

if (-not $SkipApp) {
    $app = Get-Content "$RepoRoot\argocd\application.yaml" -Raw
    if ($app -match "YOUR_USERNAME") {
        Write-Warning "argocd/application.yaml and project.yaml still contain YOUR_USERNAME. Skipping app registration."
    } else {
        kubectl apply -f "$RepoRoot\argocd\project.yaml"
        kubectl apply -f "$RepoRoot\argocd\application.yaml"
        kubectl get applications -n argocd
    }
}

$encoded = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
$password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))

Write-Host ""
Write-Host "Argo CD UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443"
Write-Host "             then open https://localhost:8080"
Write-Host "Username:    admin"
Write-Host "Password:    $password"
