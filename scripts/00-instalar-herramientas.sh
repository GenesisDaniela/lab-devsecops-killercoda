#!/usr/bin/env bash
# Paso 0 — Instala kind, kubectl y Trivy (macOS o Linux) y prepara el entorno.
set -euo pipefail

KIND_VERSION="v0.24.0"
KUBECTL_VERSION="v1.31.2"

SO="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Arquitectura no soportada: $ARCH"; exit 1 ;;
esac

echo "==> Sistema detectado: ${SO}/${ARCH}"

echo "==> Verificando Docker"
docker version --format 'Docker {{.Server.Version}}'

# Directorio de instalación: en macOS se evita escribir en /usr/local/bin sin sudo.
if [ -w /usr/local/bin ]; then
  BIN_DIR="/usr/local/bin"
else
  BIN_DIR="${HOME}/.local/bin"
  mkdir -p "$BIN_DIR"
  export PATH="${BIN_DIR}:${PATH}"
fi

instalar_binario() { # nombre url
  echo "==> Instalando $1 en ${BIN_DIR}"
  curl -fsSL -o "${BIN_DIR}/$1" "$2"
  chmod +x "${BIN_DIR}/$1"
}

if [ "$SO" = "Darwin" ] && command -v brew >/dev/null; then
  # macOS con Homebrew: la vía soportada para las tres herramientas.
  for paquete in kind kubectl trivy; do
    binario="$paquete"; [ "$paquete" = "kubectl" ] && binario="kubectl"
    if ! command -v "$binario" >/dev/null; then
      echo "==> brew install ${paquete}"
      brew install "$paquete"
    fi
  done
else
  SO_DL="$(echo "$SO" | tr '[:upper:]' '[:lower:]')"   # linux | darwin
  command -v kind >/dev/null || \
    instalar_binario kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${SO_DL}-${ARCH}"
  command -v kubectl >/dev/null || \
    instalar_binario kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${SO_DL}/${ARCH}/kubectl"
  command -v trivy >/dev/null || \
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b "$BIN_DIR"
fi

if [ "$SO" = "Linux" ]; then
  echo "==> Ajustando vm.max_map_count para SonarQube (Elasticsearch embebido)"
  sysctl -w vm.max_map_count=524288 >/dev/null || true
  sysctl -w fs.file-max=131072 >/dev/null || true
else
  echo "==> macOS: vm.max_map_count lo gestiona la VM de Docker; el contenedor"
  echo "    de SonarQube arranca con SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true."
fi

echo
echo "Versiones instaladas:"
kind version
kubectl version --client | head -1
trivy --version | head -1
if [ "$SO" = "Darwin" ]; then
  echo "Memoria del equipo: $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB"
else
  free -h | awk 'NR<=2'
fi

if [ "$BIN_DIR" != "/usr/local/bin" ] && [ -n "$(ls -A "$BIN_DIR" 2>/dev/null)" ] && \
   ! command -v kind | grep -q '^/opt/homebrew'; then
  echo
  echo "Añade ${BIN_DIR} al PATH:  export PATH=\"${BIN_DIR}:\$PATH\""
fi
