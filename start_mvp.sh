#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$APP_DIR/.venv/bin/python"
REQUIREMENTS_FILE="$APP_DIR/requirements.txt"
BOOTSTRAP_SCRIPT="$APP_DIR/bootstrap_models.py"
BOOTSTRAP_READY_FILE="$APP_DIR/.bootstrap/models-ready.json"
HOST_ADDRESS="127.0.0.1"
PREFERRED_PORT=8000

stop_with_message() {
  echo
  echo "$1" >&2
  echo
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

test_port_free() {
  local port="$1"
  "$VENV_PYTHON" - "$HOST_ADDRESS" "$port" <<'PY'
import socket, sys
host = sys.argv[1]
port = int(sys.argv[2])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((host, port))
    except OSError:
        raise SystemExit(1)
raise SystemExit(0)
PY
}

test_tribe_url() {
  local port="$1"
  "$VENV_PYTHON" - "$HOST_ADDRESS" "$port" <<'PY'
from urllib.request import urlopen
import sys
host = sys.argv[1]
port = int(sys.argv[2])
url = f"http://{host}:{port}"
try:
    with urlopen(url, timeout=2) as res:
        body = res.read().decode("utf-8", errors="ignore")
        ok = "TRIBE Review MVP" in body or "Predict virality with Meta TRIBE v2" in body
        raise SystemExit(0 if ok else 1)
except Exception:
    raise SystemExit(1)
PY
}

get_launch_port() {
  if test_tribe_url "$PREFERRED_PORT"; then
    echo "$PREFERRED_PORT"
    return
  fi

  if test_port_free "$PREFERRED_PORT"; then
    echo "$PREFERRED_PORT"
    return
  fi

  for port in $(seq 8001 8010); do
    if test_port_free "$port"; then
      echo "$port"
      return
    fi
  done

  echo ""
}

open_browser() {
  local url="$1"
  if command_exists open; then
    (
      for _ in $(seq 1 240); do
        if "$VENV_PYTHON" - "$url" <<'PY'
from urllib.request import urlopen
import sys
try:
    with urlopen(sys.argv[1], timeout=2) as _:
        pass
    raise SystemExit(0)
except Exception:
    raise SystemExit(1)
PY
        then
          open "$url" >/dev/null 2>&1 || true
          exit 0
        fi
        sleep 0.75
      done
    ) &
  fi
}

cd "$APP_DIR"

if [[ ! -x "$VENV_PYTHON" ]]; then
  echo
  echo "Creating local Python environment: .venv"
  if command_exists python3.11; then
    python3.11 -m venv .venv
  elif command_exists python3; then
    python3 -m venv .venv
  elif command_exists python; then
    python -m venv .venv
  else
    stop_with_message "Could not create .venv. Install Python 3.11, then run ./start_mvp.sh again."
  fi
fi

if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
  stop_with_message "requirements.txt not found. Download the full repository archive again."
fi

if ! "$VENV_PYTHON" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
  echo
  echo "Installing Python dependencies. First run can take several minutes."
  "$VENV_PYTHON" -m pip install --upgrade pip
  "$VENV_PYTHON" -m pip install -r "$REQUIREMENTS_FILE"
fi

if [[ ! -f "$BOOTSTRAP_READY_FILE" ]]; then
  if [[ ! -f "$BOOTSTRAP_SCRIPT" ]]; then
    stop_with_message "bootstrap_models.py not found. Download the full repository archive again."
  fi

  "$VENV_PYTHON" "$BOOTSTRAP_SCRIPT"

  echo
  echo "Initial setup finished successfully."
  echo "Run ./start_mvp.sh one more time to start the app."
  echo
  exit 0
fi

PORT="$(get_launch_port)"
if [[ -z "$PORT" ]]; then
  stop_with_message "Could not find a free port from 8000 to 8010."
fi

URL="http://$HOST_ADDRESS:$PORT"

if test_tribe_url "$PORT"; then
  echo
  echo "TRIBE Review already running on $URL"
  open "$URL" >/dev/null 2>&1 || true
  exit 0
fi

echo
echo "Starting TRIBE Review on $URL"
open_browser "$URL"
exec "$VENV_PYTHON" -m uvicorn app:app --host "$HOST_ADDRESS" --port "$PORT"
