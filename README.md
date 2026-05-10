# Examen Final — Cloud Computing | GKE Lab Práctico
### Universidad Da Vinci de Guatemala

> **Duración:** 120 minutos  
> **Modalidad:** Laboratorio práctico individual en Google Cloud Platform  
> **Plataforma:** Google Kubernetes Engine (GKE) Standard

---

## Inicio rápido — 3 comandos

```bash
# 1. Clonar este repositorio en Cloud Shell
git clone https://github.com/[DOCENTE]/examen-gke-repo.git
cd examen-gke-repo

# 2. Configurar tu zona asignada (ver tabla en el documento de examen)
gcloud config set compute/zone [TU_ZONA_ASIGNADA]

# 3. Ejecutar el setup completo con tu apellido
bash scripts/setup.sh [tu-apellido]
```

El script `setup.sh` hace todo lo demás automáticamente.  
Al terminar el examen ejecuta el script de limpieza:

```bash
bash scripts/cleanup.sh
```

---

## Estructura del repositorio

```
examen-gke-repo/
│
├── backend/                   # Código fuente del Backend API
│   ├── app.py                 # Servidor Flask con endpoints /api/health y /api/items
│   ├── requirements.txt       # Dependencias Python (flask, gunicorn)
│   └── Dockerfile             # Imagen python:3.11-slim
│
├── frontend/                  # Código fuente del Frontend
│   ├── index.html             # Interfaz web que consume el Backend API
│   ├── nginx.conf             # Configuración Nginx con proxy interno al backend
│   └── Dockerfile             # Imagen nginx:1.25-alpine
│
├── k8s/                       # Manifests de Kubernetes (YAMLs)
│   ├── backend/
│   │   ├── deployment.yaml    # Deployment backend-api  (2 réplicas, e2-small)
│   │   └── service.yaml       # Service ClusterIP → puerto 8080
│   ├── frontend/
│   │   ├── deployment.yaml    # Deployment frontend-app (2 réplicas)
│   │   └── service.yaml       # Service ClusterIP → puerto 80
│   └── config/
│       ├── configmap.yaml     # ConfigMap: APP_NAME, APP_VERSION
│       └── secret.yaml        # Secret:    API_KEY (Base64, generado por setup.sh)
│
└── scripts/
    ├── setup.sh               # ★ Script principal — ejecutar al inicio
    ├── port-forward.sh        # Abre los dos port-forwards para acceder a la app
    └── cleanup.sh             # ★ Script de limpieza — ejecutar al finalizar
```

---

## Lo que hace `setup.sh` paso a paso

| Paso | Acción |
|------|--------|
| 1 | Valida que la zona GCP y el PROJECT_ID estén configurados |
| 2 | Crea copias de trabajo de los YAMLs en `.work-[apellido]/` |
| 3 | Reemplaza `NAMESPACE_PLACEHOLDER` → `examen-[apellido]` en todos los archivos |
| 4 | Reemplaza `PROJECT_ID_PLACEHOLDER` → tu PROJECT_ID real |
| 5 | Crea el namespace `examen-[apellido]` en Kubernetes |
| 6 | Aplica ConfigMap y Secret (genera API key única por estudiante) |
| 7 | Construye imagen Docker del Backend con Cloud Build |
| 8 | Construye imagen Docker del Frontend con Cloud Build |
| 9 | Aplica todos los Deployments y Services en GKE |
| 10 | Espera a que los pods estén `Running` y muestra el estado final |

---

## Tabla de asignación de zonas

| Estudiante | Región        | Zona              |
|------------|--------------|-------------------|
| 1          | us-central1  | us-central1-a     |
| 2          | us-east1     | us-east1-b        |
| 3          | us-west1     | us-west1-a        |
| 4          | europe-west1 | europe-west1-b    |
| 5          | asia-east1   | asia-east1-a      |
| 6          | us-west2     | us-west2-a        |

---

## Restricciones de recursos — por qué existen

Este examen corre 6 estudiantes simultáneamente en **un solo proyecto GCP de pago**.  
Las restricciones de recursos no son opcionales — están calculadas para no exceder las quotas:

| Recurso | Valor | Cálculo total (×6) | Límite GCP |
|---------|-------|--------------------|------------|
| Tipo de nodo | `e2-small` | 12 vCPUs efectivas | < 24 por región |
| Nodos por cluster | 2 | 12 nodos | OK |
| Disco por nodo | 30 GB pd-standard | 360 GB | < quota disco |
| Services tipo | `ClusterIP` | **0 IPs externas** | vs. límite 23 |
| CPU request por pod | 100m | 500m por namespace | < capacidad nodo |
| Memory request | 128Mi | 640 MiB por namespace | < capacidad nodo |

> ⚠ **NO cambies** `type: ClusterIP` a `type: LoadBalancer` en ningún Service.  
> Hacerlo consume una IP externa del pool compartido y puede bloquear a otro estudiante.

---

## Acceso a la aplicación (después del setup)

```bash
# Opción A — Script automático
bash scripts/port-forward.sh [tu-apellido]

# Opción B — Manual (dos terminales)
kubectl port-forward svc/backend-api-svc 8080:80 -n examen-[apellido] &
kubectl port-forward svc/frontend-svc    8081:80 -n examen-[apellido] &

# Verificar el backend
curl -s http://localhost:8080/api/health | python3 -m json.tool
curl -s http://localhost:8080/api/items  | python3 -m json.tool

# Verificar el frontend
curl -s http://localhost:8081 | grep '<title>'
```

---

## Tareas del examen y puntos

| # | Tarea | Puntos | Checkpoint |
|---|-------|--------|------------|
| T1 | Cluster GKE + namespace personal | 15 | `kubectl get nodes` |
| T2 | Backend API desplegado con ClusterIP | 20 | `kubectl get svc backend-api-svc` |
| T3 | Frontend desplegado con ClusterIP | 20 | `kubectl get deployments` |
| T4 | ConfigMap + Secret + curl exitoso | 20 | `curl /api/health` → `key_ok: true` |
| T5 | Escalar a 3 réplicas + preguntas | 15 | `kubectl get pods -o wide` (5 pods) |
| T6 | Limpieza de recursos | 10 | `gcloud container clusters list` → 0 items |
| | **TOTAL** | **100** | |

---

## Comandos de verificación rápida

```bash
# Ver todos tus recursos
kubectl get all -n examen-[apellido]

# Ver distribución de pods en nodos
kubectl get pods -n examen-[apellido] -o wide

# Ver variables de entorno inyectadas
kubectl exec -it deployment/backend-api -n examen-[apellido] -- env | grep -E 'APP_|API_'

# Ver eventos recientes (útil para diagnosticar errores)
kubectl get events -n examen-[apellido] --sort-by='.lastTimestamp' | tail -15

# Ver consumo de recursos del cluster
kubectl describe nodes | grep -A8 'Allocated resources'
```

---

## Solución de problemas frecuentes

| Error | Causa probable | Solución |
|-------|---------------|----------|
| `QUOTA_EXCEEDED` | Zona incorrecta o tipo de VM cambiado | Avisa al docente inmediatamente |
| Pod en `Pending` | ConfigMap/Secret no aplicado aún | Ejecuta el paso 3 del setup manualmente |
| Pod en `CrashLoopBackOff` | Error en app.py o variables faltantes | `kubectl logs deployment/backend-api -n [ns]` |
| `port-forward` cuelga | El pod no está en `Running` | Espera a que el pod esté listo primero |
| `ImagePullBackOff` | Imagen no subida a gcr.io | Repite el `gcloud builds submit` del paso 4 |
| `Connection refused` en curl | Port-forward no activo | Ejecuta `bash scripts/port-forward.sh [apellido]` |

---

*Universidad Da Vinci de Guatemala · Ingeniería en Sistemas · Cloud Computing*  
*Repositorio de uso exclusivo para el examen final — no compartir*
