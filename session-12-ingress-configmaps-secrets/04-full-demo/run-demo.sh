#!/usr/bin/env bash
# Deploys the full Session 12 stack in dependency order.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 1/5 ConfigMap"
kubectl apply -f configmap.yaml
echo "==> 2/5 Secret"
kubectl apply -f secret.yaml
echo "==> 3/5 Backend (source ConfigMap + Deployment + Service)"
kubectl apply -f backend.yaml
echo "==> 4/5 Frontend (Deployment + Service)"
kubectl apply -f frontend.yaml
echo "==> 5/5 Ingress"
kubectl apply -f ingress.yaml

echo "==> waiting for rollouts"
kubectl rollout status deployment/yatri-backend  --timeout=300s
kubectl rollout status deployment/yatri-frontend --timeout=300s

echo "==> stack is up"
kubectl get configmap,secret,deploy,svc,ingress -l app=yatri-app
