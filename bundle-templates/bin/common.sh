#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
WHEEL_DIR="$ROOT_DIR/wheels"
VENV_DIR="$ROOT_DIR/venv"

# Load env if present
if [[ -f "$ROOT_DIR/redash.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/redash.env"
  set +a
fi

need() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: missing required env var: $var"
    exit 1
  fi
}

ensure_venv() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "Creating venv in $VENV_DIR (offline from wheelhouse)..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/python" -m pip install --upgrade pip --quiet
    "$VENV_DIR/bin/pip" install --no-index --find-links "$WHEEL_DIR" -r "$APP_DIR/requirements.txt" --quiet
    echo "Venv created successfully."
  fi
}
