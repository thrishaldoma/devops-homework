#!/usr/bin/env bash
# Removes everything run-demo.sh created. --ignore-not-found keeps this idempotent.
set -euo pipefail
cd "$(dirname "$0")"

for f in ingress.yaml frontend.yaml backend.yaml secret.yaml configmap.yaml; do
  echo "==> deleting $f"
  kubectl delete -f "$f" --ignore-not-found
done

echo "==> remaining app resources (expect none):"
kubectl get configmap,secret,deploy,svc,ingress -l app=yatri-app 2>&1 || true
