#!/bin/bash
# Experimento 2: Error rate 10% en data-service (service-b vía Toxiproxy)
# Mide MTTD: tiempo desde inicio del caos hasta que alerta Grafana cambia a Firing

TOXIPROXY_API="http://localhost:8474"
SERVICE_A="http://localhost:8080"
PROMETHEUS="http://localhost:9090"

query_error_rate() {
  curl -s "$PROMETHEUS/api/v1/query" \
    --data-urlencode 'query=100 * sum(rate(http_server_request_duration_seconds_count{job="service-a", http_response_status_code=~"5.."}[1m])) / sum(rate(http_server_request_duration_seconds_count{job="service-a"}[1m]))' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); v=r['data']['result']; print(f'{float(v[0][\"value\"][1]):.1f}%' if v else '0.0%')"
}

query_p99() {
  curl -s "$PROMETHEUS/api/v1/query" \
    --data-urlencode 'query=histogram_quantile(0.99, sum by(le)(rate(http_server_request_duration_seconds_bucket{job="service-a"}[1m])))' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); v=r['data']['result']; print(f'{float(v[0][\"value\"][1])*1000:.0f} ms' if v else 'sin datos')"
}

generate_load_continuous() {
  # Genera 1 request por segundo durante N segundos en background
  local COUNT=$1
  for i in $(seq 1 $COUNT); do
    curl -s -o /dev/null "$SERVICE_A/request?input=chaos-exp2-$i"
    sleep 1
  done
}

echo "================================================"
echo " EXPERIMENTO 2 — Error rate 10% en data-service"
echo "================================================"

echo ""
echo "[BASELINE] Generando 20 requests para warm-up..."
for i in $(seq 1 20); do curl -s -o /dev/null "$SERVICE_A/request?input=warmup-$i" & done
wait
sleep 15

echo ""
echo "[ANTES] Métricas baseline:"
echo "  Error rate   : $(query_error_rate)"
echo "  Latencia P99 : $(query_p99)"

echo ""
echo "[CAOS] Inyectando 10% de timeouts en Toxiproxy (simula fallo data-service)..."
RESULT=$(curl -s -X POST "$TOXIPROXY_API/proxies/service-b/toxics" \
  -H "Content-Type: application/json" \
  -d '{"name":"error-rate-10","type":"timeout","stream":"downstream","toxicity":0.1,"attributes":{"timeout":100}}')
echo "  Toxic creado: $RESULT"

CAOS_START=$(date +%s)
echo ""
echo "[CAOS ACTIVO] Inicio: $(date '+%H:%M:%S') — Generando tráfico continuo..."
echo "  Observa en Grafana → Alerting: cuándo 'Tasa de Errores HTTP > 5%' cambia a Firing"
echo "  MTTD objetivo: < 2 minutos desde $(date '+%H:%M:%S')"
echo ""

# Tráfico continuo durante 3 minutos (suficiente para que alert dispare con for=1m)
generate_load_continuous 180 &
LOAD_PID=$!

# Polling cada 30s para reportar métricas
for CHECK in 1 2 3 4 5 6; do
  sleep 30
  ELAPSED=$(( $(date +%s) - CAOS_START ))
  echo "  [+${ELAPSED}s] Error rate: $(query_error_rate) | P99: $(query_p99)"
done

kill $LOAD_PID 2>/dev/null
wait $LOAD_PID 2>/dev/null

CAOS_END=$(date +%s)
DURACION=$(( CAOS_END - CAOS_START ))

echo ""
echo "[RESET] Eliminando toxic de error rate..."
curl -s -X DELETE "$TOXIPROXY_API/proxies/service-b/toxics/error-rate-10" > /dev/null
echo "  Toxic eliminado — sistema normal"

echo ""
echo "[DESPUÉS] Esperando 30s para recuperación..."
sleep 30
echo "  Error rate recuperado: $(query_error_rate)"
echo "  Latencia P99 recuperada: $(query_p99)"

echo ""
echo "================================================"
echo " Duración del experimento: ${DURACION}s"
echo " MTTD: verifica en Grafana la hora en que la alerta"
echo "        'AIOps: Tasa de Errores HTTP > 5%' cambió a Firing"
echo " SLO target: error rate < 1% (budget agotado si >1%)"
echo " Error budget consumido: SI (10% >> 1% SLO)"
echo "================================================"
