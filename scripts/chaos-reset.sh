#!/bin/bash
# Limpia todos los toxics activos en Toxiproxy (resetea al estado normal)

TOXIPROXY_API="http://localhost:8474"

echo "Eliminando todos los toxics del proxy service-b..."
curl -s -X DELETE "$TOXIPROXY_API/proxies/service-b/toxics/latency-200ms" 2>/dev/null && echo "  latency-200ms eliminado" || true
curl -s -X DELETE "$TOXIPROXY_API/proxies/service-b/toxics/error-rate-10"  2>/dev/null && echo "  error-rate-10 eliminado"  || true

echo ""
echo "Estado actual del proxy:"
curl -s "$TOXIPROXY_API/proxies/service-b" | python3 -m json.tool 2>/dev/null || curl -s "$TOXIPROXY_API/proxies/service-b"
echo ""
echo "Sistema restaurado a estado normal."
