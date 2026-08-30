#!/usr/bin/env bash
# Teardown completo de la infraestructura AWS del pipeline OTel
# Orden: NLBs → IRSA stacks → Terraform → IAM policies → CloudWatch logs
set -euo pipefail

CLUSTER_NAME="otel-cluster"
REGION="us-east-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TERRAFORM_DIR="$(dirname "$0")/../terraform/aws"

echo "======================================================"
echo "  TEARDOWN AWS — Pipeline OTel"
echo "  Cluster : $CLUSTER_NAME"
echo "  Region  : $REGION"
echo "  Account : $AWS_ACCOUNT_ID"
echo "======================================================"
echo ""
read -p "¿Confirmas que quieres destruir TODA la infraestructura? (escribe 'si'): " confirm
if [[ "$confirm" != "si" ]]; then
  echo "Cancelado."
  exit 0
fi

# ─── 1. Conectar kubectl al cluster ───────────────────────────────────────────
echo ""
echo "==> [1/6] Conectando kubectl al cluster..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null || \
  echo "  Cluster no encontrado o ya eliminado, continuando..."

# ─── 2. Eliminar servicios LoadBalancer (borra los NLBs de AWS) ───────────────
echo ""
echo "==> [2/6] Eliminando servicios LoadBalancer para que AWS borre los NLBs..."
kubectl delete service jaeger-ui      -n observability --ignore-not-found
kubectl delete service prometheus-ui  -n observability --ignore-not-found
kubectl delete service grafana        -n observability --ignore-not-found
kubectl delete service service-a      -n default       --ignore-not-found

echo "  Esperando 60s para que los NLBs se eliminen en AWS..."
sleep 60

# ─── 3. Eliminar todos los workloads de Kubernetes ────────────────────────────
echo ""
echo "==> [3/6] Eliminando workloads del cluster..."
kubectl delete namespace observability --ignore-not-found
kubectl delete -f "$(dirname "$0")/../k8s/aws/otel-collector.yaml" --ignore-not-found
kubectl delete -f "$(dirname "$0")/../k8s/aws/jaeger.yaml"         --ignore-not-found
kubectl delete -f "$(dirname "$0")/../k8s/aws/prometheus.yaml"     --ignore-not-found
kubectl delete -f "$(dirname "$0")/../k8s/aws/grafana.yaml"        --ignore-not-found
kubectl delete -f "$(dirname "$0")/../k8s/aws/grafana-provisioning.yaml" --ignore-not-found

helm uninstall service-a -n default 2>/dev/null || true
helm uninstall service-b -n default 2>/dev/null || true
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

kubectl delete -f "$(dirname "$0")/../k8s/postgres.yaml" --ignore-not-found

# ─── 4. Eliminar IRSA service accounts (CloudFormation stacks via eksctl) ─────
echo ""
echo "==> [4/6] Eliminando IAM service accounts IRSA..."
eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" --region="$REGION" \
  --namespace=observability --name=otel-collector 2>/dev/null || true

eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" --region="$REGION" \
  --namespace=observability --name=grafana 2>/dev/null || true

eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" --region="$REGION" \
  --namespace=kube-system --name=aws-load-balancer-controller 2>/dev/null || true

# ─── 5. Terraform destroy (VPC, EKS, ECR, IAM roles Terraform-managed) ────────
echo ""
echo "==> [5/6] Ejecutando terraform destroy..."
cd "$TERRAFORM_DIR"
terraform destroy -auto-approve

# ─── 6. Limpiar recursos IAM creados manualmente y CloudWatch logs ─────────────
echo ""
echo "==> [6/6] Limpiando IAM policies y CloudWatch log groups..."

for policy in GrafanaCloudWatchLogsPolicy OTelCollectorCloudWatchPolicy AWSLoadBalancerControllerIAMPolicy; do
  POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy}"
  aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null && \
    echo "  Eliminada policy: $policy" || \
    echo "  Policy no encontrada: $policy"
done

for log_group in /otel/service-a/logs /otel/service-b/logs /otel/pipeline/logs; do
  aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null && \
    echo "  Eliminado log group: $log_group" || \
    echo "  Log group no encontrado: $log_group"
done

echo ""
echo "======================================================"
echo "  TEARDOWN COMPLETO"
echo "  Verifica en la consola AWS que no queden recursos:"
echo "  - EC2 > Load Balancers"
echo "  - EKS > Clusters"
echo "  - VPC > Your VPCs"
echo "======================================================"
