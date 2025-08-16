#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-kubeconfig}"
NAMESPACE="${NAMESPACE:-sfc}"

BACKEND_DIR="${BACKEND_DIR:-backend}"
FRONTEND_DIR="${FRONTEND_DIR:-frontend}"

FILE_PATTERNS="${FILE_PATTERNS:-*Deployment*.y*ml *Service*.y*ml}"

# --- Sanity checks ---
if ! command -v kubectl >/dev/null 2>&1; then
  echo "[ERR] kubectl is not installed on the runner."
  exit 1
fi

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "[ERR] Kubeconfig file is missing: $KUBECONFIG_PATH"
  exit 1
fi

if [ ! -d "$BACKEND_DIR" ] || [ ! -d "$FRONTEND_DIR" ]; then
  echo "[ERR] Can't find backend/frontend directories:"
  echo "      BACKEND_DIR=$BACKEND_DIR (exists: $([ -d "$BACKEND_DIR" ] && echo yes || echo no))"
  echo "      FRONTEND_DIR=$FRONTEND_DIR (exists: $([ -d "$FRONTEND_DIR" ] && echo yes || echo no))"
  exit 1
fi

echo "[INFO] Using kubeconfig: $KUBECONFIG_PATH"
echo "[INFO] Namespace: $NAMESPACE"
echo "[INFO] Searching manifests in: $BACKEND_DIR and $FRONTEND_DIR"
echo "[INFO] File patterns: $FILE_PATTERNS"

collect_files() {
  local dir="$1"; shift
  local patterns=("$@")
  local found=()

  for p in "${patterns[@]}"; do
    while IFS= read -r -d '' f; do
      found+=("$f")
    done < <(find "$dir" -maxdepth 2 -type f -name "$p" -print0 2>/dev/null || true)
  done

  printf "%s\n" "${found[@]}"
}

PATTERNS_ARR=($FILE_PATTERNS)

BACKEND_FILES=$(collect_files "$BACKEND_DIR" "${PATTERNS_ARR[@]}")
FRONTEND_FILES=$(collect_files "$FRONTEND_DIR" "${PATTERNS_ARR[@]}")

ALL_FILES="$(printf "%s\n%s\n" "$BACKEND_FILES" "$FRONTEND_FILES" | awk 'NF' | sort -u)"

if [ -z "$ALL_FILES" ]; then
  echo "[ERR] Did not find any manifest files in $BACKEND_DIR/ and $FRONTEND_DIR/ matching: $FILE_PATTERNS"
  echo "      Check that your files are named e.g. 'backendDeployment.yaml', 'backendService.yaml', 'frontendDeployment.yaml', 'frontendService.yaml'."
  exit 1
fi

echo "[INFO] Found the following manifest files:"
printf ' - %s\n' $ALL_FILES

if ! kubectl --kubeconfig "$KUBECONFIG_PATH" get ns "$NAMESPACE" >/dev/null 2>&1; then
  echo "[INFO] Creating namespace $NAMESPACE"
  kubectl --kubeconfig "$KUBECONFIG_PATH" create namespace "$NAMESPACE"
fi

echo "[INFO] Applying manifests..."
echo "$ALL_FILES" | while IFS= read -r mf; do
  [ -n "$mf" ] || continue
  echo "[APPLY] $mf"
  kubectl --kubeconfig "$KUBECONFIG_PATH" apply -n "$NAMESPACE" -f "$mf"
done

echo "[INFO] Waiting for rollout of Deployments in $NAMESPACE"
set +e
DEPLOYS=$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NAMESPACE" get deploy -o name 2>/dev/null)
set -e
if [ -n "${DEPLOYS:-}" ]; then
  for d in $DEPLOYS; do
    kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NAMESPACE" rollout status "$d" --timeout=120s || {
      echo "[WARN] Rollout timeout for $d"
    }
  done
else
  echo "[INFO] No Deployments found (ok if you only have Services/Jobs/etc.)"
fi

echo "[OK] Deploy finished."
