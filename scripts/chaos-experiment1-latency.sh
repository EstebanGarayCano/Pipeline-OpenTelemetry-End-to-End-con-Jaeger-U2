#!/bin/bash
# Experimento 1: Inyección de latencia 200ms en service-b (vía Toxiproxy)
# Mide latencia P99 antes/durante/después y verifica degradación del SLO

TOXIPROXY_API="http://localhost:8474"
SERVICE_A="http://localhost:8080"
PROMETHEUS="http://localhost:9090"

query_p99() {
  curl -s "$PROMETHEUS/api/v1/query" \
    --data-urlencode 'query=histogram_quantile(0.99, sum by(le)(rate(http_server_request_duration_seconds_bucket{job="service-a"}[1m])))' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); v=r['data']['result']; print(f'{float(v[0][\"value\"][1])*1000:.0f} ms' if v else 'sin datos')"
}

query_error_rate() {
  curl -s "$PROMETHEUS/api/v1/query" \
    --data-urlencode 'query=100 * sum(rate(http_server_request_duration_seconds_count{job="service-a", http_response_status_code=~"5.."}[1m])) / sum(rate(http_server_request_duration_seconds_count{job="service-a"}[1m]))' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); v=r['data']['result']; print(f'{float(v[0][\"value\"][1]):.1f}%' if v else '0.0%')"
}

generate_load() {
  for i in $(seq 1 $1); do
    curl -s -o /dev/null "$SERVICE_A/request?input=chaos-exp1-$i" &
  done
  wait
}

echo "================================================"
echo " EXPERIMENTO 1 — Latencia 200ms en service-b"
echo "================================================"

echo ""
echo "[BASELINE] Generando 20 requests para warm-up..."
generate_load 20
sleep 15

echo ""
echo "[ANTES] Métricas baseline (P99 latencia / error rate):"
echo "  Latencia P99 : $(query_p99)"
echo "  Error rate   : $(query_error_rate)"

echo ""
echo "[CAOS] Inyectando latencia 200ms en Toxiproxy..."
RESULT=$(curl -s -X POST "$TOXIPROXY_API/proxies/service-b/toxics" \
  -H "Content-Type: application/json" \
  -d '{"name":"latency-200ms","type":"latency","stream":"downstream","toxicity":1.0,"attributes":{"latency":200,"jitter":10}}')
echo "  Toxic creado: $RESULT"

CAOS_START=$(date +%s)
echo ""
echo "[DURANTE] Generando 40 requests con caos activo..."
generate_load 40
sleep 15

echo ""
echo "[DURANTE] Métricas con caos activo:"
echo "  Latencia P99 : $(query_p99)"
echo "  Error rate   : $(query_error_rate)"
echo "  Hora inicio caos: $(date -r $CAOS_START '+%H:%M:%S')"

echo ""
echo "[RESET] Eliminando toxic de latencia..."
curl -s -X DELETE "$TOXIPROXY_API/proxies/service-b/toxics/latency-200ms" > /dev/null
echo "  Toxic eliminado — sistema normal"

echo ""
echo "[DESPUÉS] Generando 20 requests post-caos..."
generate_load 20
sleep 15

echo ""
echo "[DESPUÉS] Métricas recuperadas:"
echo "  Latencia P99 : $(query_p99)"
echo "  Error rate   : $(query_error_rate)"

echo ""
echo "================================================"
echo " SLO target: Latencia P99 < 500ms"
echo " Observa el dashboard Grafana: Network & Security Golden Signals"
echo "================================================"
