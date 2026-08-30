#!/usr/bin/env bash
# Levanta el stack completo de observabilidad en Kubernetes local (Docker Desktop)
set -euo pipefail

echo "======================================================"
echo "  START — Pipeline OTel U3 — Kubernetes Local"
echo "======================================================"

# 1. Cambiar contexto a docker-desktop
echo ""
echo "==> [1/5] Configurando contexto Kubernetes..."
kubectl config use-context docker-desktop

# 2. Crear namespace si no existe
echo ""
echo "==> [2/5] Creando namespace observability..."
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# 3. Construir imágenes locales con docker compose
echo ""
echo "==> [3/5] Construyendo imágenes Docker..."
docker compose build service-a service-b

# 4. Aplicar todos los manifiestos
echo ""
echo "==> [4/5] Aplicando manifiestos Kubernetes..."
kubectl apply -f k8s/local/postgres.yaml
kubectl apply -f k8s/local/otel-collector.yaml
kubectl apply -f k8s/local/jaeger.yaml
kubectl apply -f k8s/local/loki.yaml
kubectl apply -f k8s/local/prometheus.yaml
kubectl apply -f k8s/local/grafana.yaml
kubectl apply -f k8s/local/service-b.yaml
kubectl apply -f k8s/local/service-a.yaml

# 5. Esperar a que los pods estén listos
echo ""
echo "==> [5/5] Esperando pods..."
kubectl rollout status deployment/postgres      -n observability --timeout=120s
kubectl rollout status deployment/otel-collector -n observability --timeout=120s
kubectl rollout status deployment/jaeger        -n observability --timeout=120s
kubectl rollout status deployment/loki          -n observability --timeout=120s
kubectl rollout status deployment/prometheus    -n observability --timeout=120s
kubectl rollout status deployment/grafana       -n observability --timeout=120s
kubectl rollout status deployment/service-b     -n observability --timeout=120s
kubectl rollout status deployment/service-a     -n observability --timeout=120s

echo ""
echo "======================================================"
echo "  STACK LISTO"
echo ""
echo "  service-a  → http://localhost:8080/request?input=test"
echo "  Grafana    → http://localhost:3000  (admin / admin1)"
echo "  Jaeger     → http://localhost:16686"
echo "  Prometheus → http://localhost:9090"
echo "======================================================"
