#!/bin/bash
# ================================================================
#  EXAMEN FINAL — Cloud Computing | Universidad Da Vinci GT
#  Script: scripts/setup.sh
#  Descripcion: Configura el entorno, sustituye todos los
#               placeholders en los YAMLs, construye las
#               imagenes Docker y aplica los manifests en GKE.
#
#  USO:
#    cd examen-gke-repo
#    bash scripts/setup.sh <TU_APELLIDO>
#
#  EJEMPLO:
#    bash scripts/setup.sh garcia
# ================================================================

set -euo pipefail

# ── Colores para la terminal ──────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}\n"; }

# ── Validar argumento de apellido ─────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo ""
  echo -e "${RED}USO INCORRECTO${NC}"
  echo "  bash scripts/setup.sh <tu-apellido>"
  echo ""
  echo "  Ejemplo: bash scripts/setup.sh garcia"
  echo ""
  exit 1
fi

APELLIDO=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
if [[ -z "$APELLIDO" ]]; then
  error "El apellido solo puede contener letras y numeros."
fi

NAMESPACE="examen-${APELLIDO}"

# ── Verificar que estamos en la raiz del repositorio ──────────────
if [[ ! -f "scripts/setup.sh" ]]; then
  error "Ejecuta este script desde la raiz del repositorio:\n  cd examen-gke-repo && bash scripts/setup.sh <apellido>"
fi

# ── Obtener PROJECT_ID y ZONE ─────────────────────────────────────
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
ZONE=$(gcloud config get-value compute/zone 2>/dev/null)

[[ -z "$PROJECT_ID" ]] && error "No hay proyecto GCP configurado. Ejecuta: gcloud config set project [PROJECT_ID]"
[[ -z "$ZONE" ]]       && error "No hay zona GCP configurada. Ejecuta: gcloud config set compute/zone [TU_ZONA_ASIGNADA]"

# ── Resumen pre-ejecucion ─────────────────────────────────────────
header "CONFIGURACION DETECTADA"
echo -e "  Apellido   : ${BOLD}${APELLIDO}${NC}"
echo -e "  Namespace  : ${BOLD}${NAMESPACE}${NC}"
echo -e "  Project ID : ${BOLD}${PROJECT_ID}${NC}"
echo -e "  Zona GCP   : ${BOLD}${ZONE}${NC}"
echo ""
read -rp "$(echo -e ${YELLOW}¿Estos datos son correctos? [s/N]:${NC} )" CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || error "Abortado por el usuario. Verifica la zona con: gcloud config get-value compute/zone"

# ================================================================
#  PASO 1 — Crear copias de trabajo de los YAMLs
# ================================================================
header "PASO 1/6 — Preparando archivos YAML"

WORK_DIR="$(pwd)/.work-${APELLIDO}"
rm -rf "$WORK_DIR"
cp -r k8s "$WORK_DIR"
info "Directorio de trabajo: ${WORK_DIR}"

# Sustituir todos los placeholders en las copias de trabajo
find "$WORK_DIR" -name "*.yaml" | while read -r f; do
  sed -i "s|NAMESPACE_PLACEHOLDER|${NAMESPACE}|g"    "$f"
  sed -i "s|PROJECT_ID_PLACEHOLDER|${PROJECT_ID}|g"  "$f"
done

# Sustituir placeholder en nginx.conf (frontend)
cp frontend/nginx.conf "${WORK_DIR}/nginx.conf"
sed -i "s|NAMESPACE_PLACEHOLDER|${NAMESPACE}|g" "${WORK_DIR}/nginx.conf"

success "Placeholders sustituidos en todos los YAMLs"

# Mostrar namespace en cada archivo para confirmacion visual
info "Verificando sustituciones:"
grep -rh "namespace:" "$WORK_DIR"/*.yaml "$WORK_DIR"/**/*.yaml 2>/dev/null | sort -u | while read -r line; do
  echo "    ${line}"
done

# ================================================================
#  PASO 2 — Crear el namespace personal del estudiante
# ================================================================
header "PASO 2/6 — Creando namespace ${NAMESPACE}"

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  warn "El namespace '${NAMESPACE}' ya existe. Se usara el existente."
else
  kubectl create namespace "$NAMESPACE"
  success "Namespace '${NAMESPACE}' creado"
fi

kubectl config set-context --current --namespace="$NAMESPACE"
success "Namespace '${NAMESPACE}' establecido como activo"

# ================================================================
#  PASO 3 — Aplicar ConfigMap y Secret
# ================================================================
header "PASO 3/6 — Aplicando ConfigMap y Secret"

# Generar API key unica para este estudiante
UNIQUE_KEY="ExamenGKE-2025-${APELLIDO}-${RANDOM}"
ENCODED_KEY=$(echo -n "$UNIQUE_KEY" | base64)

# Sobreescribir el valor del secret con uno unico por estudiante
sed -i "s|api_key:.*|api_key: ${ENCODED_KEY}|g" "${WORK_DIR}/config/secret.yaml"

kubectl apply -f "${WORK_DIR}/config/configmap.yaml"
kubectl apply -f "${WORK_DIR}/config/secret.yaml"

success "ConfigMap 'app-config' aplicado"
success "Secret 'app-secret' aplicado (key unica generada para: ${APELLIDO})"

info "Verificando ConfigMap:"
kubectl get configmap app-config -o jsonpath='{.data}' | python3 -m json.tool 2>/dev/null || \
  kubectl get configmap app-config -o yaml | grep -A4 "^data:"

# ================================================================
#  PASO 4 — Construir imagenes Docker con Cloud Build
# ================================================================
header "PASO 4/6 — Construyendo imagenes Docker con Cloud Build"

info "Construyendo imagen del Backend (Python/Flask)..."
gcloud builds submit ./backend \
  --tag "gcr.io/${PROJECT_ID}/backend-api:1.0" \
  --quiet
success "Imagen backend-api:1.0 subida a gcr.io/${PROJECT_ID}/backend-api:1.0"

info "Preparando frontend con nginx.conf del estudiante..."
# Copiar nginx.conf con namespace correcto al directorio frontend
cp "${WORK_DIR}/nginx.conf" ./frontend/nginx.conf

info "Construyendo imagen del Frontend (Nginx)..."
gcloud builds submit ./frontend \
  --tag "gcr.io/${PROJECT_ID}/frontend-app:1.0" \
  --quiet
success "Imagen frontend-app:1.0 subida a gcr.io/${PROJECT_ID}/frontend-app:1.0"

# Restaurar nginx.conf original para no contaminar el repo
cp "k8s/../frontend/nginx.conf" ./frontend/nginx.conf 2>/dev/null || \
  sed -i "s|${NAMESPACE}|NAMESPACE_PLACEHOLDER|g" ./frontend/nginx.conf

# ================================================================
#  PASO 5 — Aplicar Deployments y Services
# ================================================================
header "PASO 5/6 — Desplegando en GKE"

info "Aplicando Deployment del Backend..."
kubectl apply -f "${WORK_DIR}/backend/deployment.yaml"

info "Aplicando Service del Backend (ClusterIP)..."
kubectl apply -f "${WORK_DIR}/backend/service.yaml"

info "Aplicando Deployment del Frontend..."
kubectl apply -f "${WORK_DIR}/frontend/deployment.yaml"

info "Aplicando Service del Frontend (ClusterIP)..."
kubectl apply -f "${WORK_DIR}/frontend/service.yaml"

# ================================================================
#  PASO 6 — Esperar pods y verificar
# ================================================================
header "PASO 6/6 — Verificando despliegue"

info "Esperando que el Backend este listo..."
kubectl rollout status deployment/backend-api \
  -n "$NAMESPACE" --timeout=120s

info "Esperando que el Frontend este listo..."
kubectl rollout status deployment/frontend-app \
  -n "$NAMESPACE" --timeout=120s

echo ""
success "Todos los deployments estan listos"
echo ""

# ── Estado final de todos los recursos ───────────────────────────
echo -e "${BOLD}Estado de recursos en namespace '${NAMESPACE}':${NC}"
kubectl get all -n "$NAMESPACE"

# ================================================================
#  RESUMEN FINAL — Instrucciones para el estudiante
# ================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║         SETUP COMPLETADO EXITOSAMENTE                    ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Para acceder a la aplicacion, abre DOS terminales en Cloud Shell:${NC}"
echo ""
echo -e "  ${CYAN}# Terminal 1 — Port-forward Backend (mantener abierto)${NC}"
echo -e "  ${BOLD}kubectl port-forward svc/backend-api-svc 8080:80 -n ${NAMESPACE} &${NC}"
echo ""
echo -e "  ${CYAN}# Terminal 2 — Port-forward Frontend (mantener abierto)${NC}"
echo -e "  ${BOLD}kubectl port-forward svc/frontend-svc 8081:80 -n ${NAMESPACE} &${NC}"
echo ""
echo -e "  ${CYAN}# Verificar el Backend API:${NC}"
echo -e "  ${BOLD}sleep 3 && curl -s http://localhost:8080/api/health | python3 -m json.tool${NC}"
echo ""
echo -e "  ${CYAN}# Verificar el Frontend (debe devolver HTML):${NC}"
echo -e "  ${BOLD}curl -s http://localhost:8081 | grep '<title>'${NC}"
echo ""
echo -e "${YELLOW}Directorio de trabajo con tus YAMLs finales: ${WORK_DIR}${NC}"
echo -e "${YELLOW}Namespace activo: ${NAMESPACE}${NC}"
echo ""
