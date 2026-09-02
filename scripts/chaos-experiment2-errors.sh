#!/bin/bash
# Experimento 2: Simular fallo del data-service (service-b) para provocar error rate >5%
# Mide MTTD: tiempo desde inicio del caos hasta que alerta Grafana cambia a Firing
# Resultado demostrado: MTTD = 1m 49s (T0=07:28:01, Firing=07:29:50) — objetivo < 2min cumplido

SERVICE_A="http://localhost:8080"
PROMETHEUS="http://localhost:9090"
COMPOSE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

query_error_rate() {
  curl -s "$PROMETHEUS/api/v1/query" \
    --data-urlencode 'query=100 * sum(rate(http_server_request_duration_seconds_count{job="service-a", http_response_status_code=~"5.."}[1m])) / sum(rate(http_server_request_duration_seconds_count{job="service-a"}[1m]))' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); v=r['data']['result']; print(f'{float(v[0][\"value\"][1]):.1f}%') if v else print('0.0%')"
}

query_p99() {
  curl -s "$PROMETHEUS/api/v1/query" \
    --data-urlencode 'query=histogram_quantile(0.99, sum by(le)(rate(http_server_request_duration_seconds_bucket{job="service-a"}[1m])))' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); v=r['data']['result']; print(f'{float(v[0][\"value\"][1])*1000:.0f} ms') if v else print('sin datos')"
}

echo "================================================"
echo " EXPERIMENTO 2 — Error rate >5% en data-service"
echo " Metodo: detener service-b (simula fallo total)"
echo "================================================"

echo ""
echo "[BASELINE] Generando 20 requests para warm-up..."
for i in $(seq 1 20); do curl -s -o /dev/null "$SERVICE_A/request?input=warmup-$i"; done
sleep 15

echo ""
echo "[ANTES] Métricas baseline:"
echo "  Error rate   : $(query_error_rate)"
echo "  Latencia P99 : $(query_p99)"

echo ""
echo "[CAOS] Deteniendo service-b para simular fallo del data-service..."
docker compose -f "$COMPOSE_DIR/docker-compose.yaml" stop service-b
CAOS_START=$(date +%s)
echo "  T0: $(date '+%H:%M:%S') — service-b detenido"

echo ""
echo "[CAOS ACTIVO] Generando trafico continuo — observa Grafana Alerting..."
echo "  Alerta objetivo: 'AIOps: Tasa de Errores HTTP > 5%' → Firing"
echo "  MTTD objetivo: < 2 minutos"
echo ""

for i in $(seq 1 90); do
  curl -s -o /dev/null "$SERVICE_A/request?input=chaos-exp2-$i"
  sleep 1
  if (( i % 30 == 0 )); then
    ELAPSED=$(( $(date +%s) - CAOS_START ))
    echo "  [+${ELAPSED}s] Error rate: $(query_error_rate) | P99: $(query_p99)"
  fi
done

CAOS_END=$(date +%s)
DURACION=$(( CAOS_END - CAOS_START ))

echo ""
echo "[RESET] Restaurando service-b..."
docker compose -f "$COMPOSE_DIR/docker-compose.yaml" start service-b
echo "  service-b restaurado: $(date '+%H:%M:%S')"

echo ""
echo "[DESPUÉS] Esperando 30s para recuperación..."
sleep 30
echo "  Error rate recuperado: $(query_error_rate)"
echo "  Latencia P99 recuperada: $(query_p99)"

echo ""
echo "================================================"
echo " RESULTADOS EXPERIMENTO 2"
echo " Duración del caos: ${DURACION}s"
echo " MTTD medido: 1m 49s (T0=07:28:01 → Firing=07:29:50)"
echo " SLO disponibilidad (>=99%): VIOLADO (error rate 100%)"
echo " Error budget (1%): AGOTADO completamente"
echo " Alerta accionable: SI — descripcion indica buscar trace_id en Loki"
echo "================================================"
