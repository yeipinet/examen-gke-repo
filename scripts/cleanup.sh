#!/bin/bash
# ================================================================
#  EXAMEN FINAL — Cloud Computing | Universidad Da Vinci GT
#  Script: scripts/cleanup.sh
#  Descripcion: Elimina TODOS los recursos GCP del examen.
#               EJECUTAR AL FINALIZAR — OBLIGATORIO (10 pts)
#
#  USO:
#    bash scripts/cleanup.sh
# ================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BOLD}══ $* ══${NC}\n"; }

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
ZONE=$(gcloud config get-value compute/zone 2>/dev/null)

header "LIMPIEZA DE RECURSOS DEL EXAMEN"
warn "Este script eliminara permanentemente:"
echo "   • Cluster GKE: examen-cluster"
echo "   • Imagen Docker: gcr.io/${PROJECT_ID}/backend-api:1.0"
echo "   • Imagen Docker: gcr.io/${PROJECT_ID}/frontend-app:1.0"
echo "   • Directorio de trabajo: .work-*"
echo ""
echo -e "${RED}Esta accion es IRREVERSIBLE.${NC}"
echo ""
read -rp "$(echo -e ${YELLOW}Escribe CONFIRMAR para proceder:${NC} )" CONFIRM

if [[ "$CONFIRM" != "CONFIRMAR" ]]; then
  warn "Abortado. No se elimino ningun recurso."
  exit 0
fi

# ── Matar port-forwards activos ───────────────────────────────────
header "Deteniendo port-forwards activos"
pkill -f "kubectl port-forward" 2>/dev/null && success "Port-forwards detenidos" || info "No habia port-forwards activos"

# ── Eliminar cluster GKE ──────────────────────────────────────────
header "Eliminando cluster GKE"
if gcloud container clusters describe examen-cluster --zone="$ZONE" &>/dev/null; then
  info "Eliminando examen-cluster en zona ${ZONE}..."
  gcloud container clusters delete examen-cluster \
    --zone="$ZONE" \
    --quiet
  success "Cluster eliminado"
else
  warn "Cluster 'examen-cluster' no encontrado (ya fue eliminado o nunca existio)"
fi

# ── Eliminar imagenes de Container Registry ───────────────────────
header "Eliminando imagenes Docker de gcr.io"

for IMG in "backend-api:1.0" "frontend-app:1.0"; do
  FULL_IMG="gcr.io/${PROJECT_ID}/${IMG}"
  if gcloud container images describe "$FULL_IMG" &>/dev/null; then
    gcloud container images delete "$FULL_IMG" \
      --force-delete-tags --quiet
    success "Imagen eliminada: ${FULL_IMG}"
  else
    warn "Imagen no encontrada: ${FULL_IMG} (ya fue eliminada o nunca existio)"
  fi
done

# ── Limpiar directorio de trabajo ─────────────────────────────────
header "Limpiando archivos temporales"
rm -rf .work-* 2>/dev/null && success "Directorios .work-* eliminados" || info "No habia directorios temporales"

# ── Restaurar nginx.conf original ────────────────────────────────
if grep -q "NAMESPACE_PLACEHOLDER" frontend/nginx.conf 2>/dev/null; then
  info "nginx.conf ya tiene el placeholder original"
else
  sed -i "s|examen-[a-z0-9]*\.svc\.cluster\.local|NAMESPACE_PLACEHOLDER.svc.cluster.local|g" \
    frontend/nginx.conf 2>/dev/null || true
fi

# ── Verificacion final ────────────────────────────────────────────
header "VERIFICACION FINAL — Captura esta salida para el Anexo F"
echo ""
echo -e "${BOLD}gcloud container clusters list:${NC}"
gcloud container clusters list 2>/dev/null || echo "(sin clusters)"

echo ""
echo -e "${BOLD}gcloud compute instances list:${NC}"
gcloud compute instances list 2>/dev/null || echo "(sin instancias)"

echo ""
echo -e "${BOLD}gcloud compute addresses list:${NC}"
gcloud compute addresses list 2>/dev/null || echo "(sin IPs externas)"

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║    LIMPIEZA COMPLETADA — Recursos eliminados             ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Toma una captura de pantalla de esta pantalla completa"
echo -e "  y pegala en el ${BOLD}Anexo F${NC} del documento de examen."
echo ""
