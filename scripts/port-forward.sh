#!/bin/bash
# ================================================================
#  EXAMEN FINAL — Cloud Computing | Universidad Da Vinci GT
#  Script: scripts/port-forward.sh
#  Descripcion: Abre los dos port-forwards necesarios para
#               acceder a la aplicacion desde Cloud Shell.
#
#  USO:
#    bash scripts/port-forward.sh <TU_APELLIDO>
#
#  RESULTADO:
#    Backend  -> http://localhost:8080/api/health
#    Frontend -> http://localhost:8081
# ================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

if [[ $# -lt 1 ]]; then
  echo -e "${RED}USO:${NC} bash scripts/port-forward.sh <tu-apellido>"
  exit 1
fi

APELLIDO=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
NAMESPACE="examen-${APELLIDO}"

# Matar port-forwards previos para evitar conflictos de puerto
echo -e "${YELLOW}Deteniendo port-forwards anteriores...${NC}"
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 1

echo -e "${BLUE}Iniciando port-forwards para namespace '${NAMESPACE}'...${NC}"

# Port-forward Backend en background
kubectl port-forward svc/backend-api-svc 8080:80 \
  -n "$NAMESPACE" > /tmp/pf-backend.log 2>&1 &
PF_BACKEND_PID=$!

# Port-forward Frontend en background
kubectl port-forward svc/frontend-svc 8081:80 \
  -n "$NAMESPACE" > /tmp/pf-frontend.log 2>&1 &
PF_FRONTEND_PID=$!

echo -e "  Backend  PID: ${BOLD}${PF_BACKEND_PID}${NC}"
echo -e "  Frontend PID: ${BOLD}${PF_FRONTEND_PID}${NC}"

# Esperar a que los tuneles esten listos
echo -e "${YELLOW}Esperando 4 segundos a que los tuneles se establezcan...${NC}"
sleep 4

# Verificar que los procesos siguen vivos
if ! kill -0 "$PF_BACKEND_PID" 2>/dev/null; then
  echo -e "${RED}[ERROR] Port-forward del Backend fallo. Log:${NC}"
  cat /tmp/pf-backend.log
  exit 1
fi
if ! kill -0 "$PF_FRONTEND_PID" 2>/dev/null; then
  echo -e "${RED}[ERROR] Port-forward del Frontend fallo. Log:${NC}"
  cat /tmp/pf-frontend.log
  exit 1
fi

# Prueba automatica del Backend
echo ""
echo -e "${BOLD}Prueba automatica del Backend (/api/health):${NC}"
if curl -sf http://localhost:8080/api/health | python3 -m json.tool 2>/dev/null; then
  echo -e "${GREEN}[OK] Backend respondiendo correctamente${NC}"
else
  echo -e "${YELLOW}[WARN] Backend aun no responde — espera unos segundos e intenta manualmente:${NC}"
  echo "  curl -s http://localhost:8080/api/health"
fi

echo ""
echo -e "${BOLD}Prueba automatica del Frontend (titulo HTML):${NC}"
if curl -sf http://localhost:8081 | grep -o '<title>[^<]*</title>'; then
  echo -e "${GREEN}[OK] Frontend respondiendo correctamente${NC}"
else
  echo -e "${YELLOW}[WARN] Frontend aun no responde — intenta manualmente:${NC}"
  echo "  curl -s http://localhost:8081 | grep title"
fi

echo ""
echo -e "${GREEN}${BOLD}Port-forwards activos:${NC}"
echo -e "  ${CYAN}Backend  ->  http://localhost:8080/api/health${NC}"
echo -e "  ${CYAN}Backend  ->  http://localhost:8080/api/items${NC}"
echo -e "  ${CYAN}Frontend ->  http://localhost:8081${NC}"
echo ""
echo -e "${YELLOW}Para detener los port-forwards: ${BOLD}pkill -f 'kubectl port-forward'${NC}"
echo -e "${YELLOW}Los logs se guardan en: /tmp/pf-backend.log y /tmp/pf-frontend.log${NC}"
echo ""
