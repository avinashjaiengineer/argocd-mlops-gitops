import os

from fastapi import FastAPI

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")

app = FastAPI(title="GitOps ML API", version=APP_VERSION)


@app.get("/")
def root():
    return {
        "service": "gitops-ml-api",
        "version": APP_VERSION,
        "status": "healthy",
    }


@app.get("/health")
def health():
    """Used by Kubernetes liveness/readiness probes and the ALB health check."""
    return {"status": "ok"}


@app.get("/predict")
def predict():
    # Placeholder - replace with a real model (e.g. fraud detection) in Level 6.
    return {
        "prediction": 0,
        "probability": 0.91,
    }
