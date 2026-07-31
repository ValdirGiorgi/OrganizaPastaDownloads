#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$APP_DIR/build/organiza_downloads_linux"
LOG_DIR="$HOME/.local/share/organiza_downloads/logs"
CSV_DIR="$HOME/.local/share/organiza_downloads/relatorios"
mkdir -p "$LOG_DIR" "$CSV_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/${TS}.log"

PAUSE=0
EXTRA_ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--pause" ]]; then
    PAUSE=1
  else
    EXTRA_ARGS+=("$arg")
  fi
done

if [[ ! -x "$BIN" ]]; then
  echo "Binario nao encontrado em $BIN" | tee -a "$LOG_FILE"
  echo "Rode scripts/build_linux.sh para gerar o binario." | tee -a "$LOG_FILE"
  exit 1
fi

run_scan() {
  local target="$1"
  if [[ -d "$target" ]]; then
    echo "=== Organizando: $target ===" | tee -a "$LOG_FILE"
    "$BIN" scan "$target" --mode real --hash-duplicates --csv "$CSV_DIR" "${EXTRA_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
  else
    echo "Pasta nao encontrada, pulando: $target" | tee -a "$LOG_FILE"
  fi
}

resolve_dir() {
  local xdg_key="$1"
  local fallback="$2"
  if command -v xdg-user-dir >/dev/null 2>&1; then
    local resolved
    resolved="$(xdg-user-dir "$xdg_key" 2>/dev/null || true)"
    if [[ -n "$resolved" && "$resolved" != "$HOME" ]]; then
      echo "$resolved"
      return
    fi
  fi
  echo "$fallback"
}

DOWNLOADS_DIR="$(resolve_dir DOWNLOAD "$HOME/Downloads")"
DESKTOP_DIR="$(resolve_dir DESKTOP "$HOME/Desktop")"

run_scan "$DOWNLOADS_DIR"
run_scan "$DESKTOP_DIR"

echo "Log completo em: $LOG_FILE"

if command -v notify-send >/dev/null 2>&1; then
  notify-send "Organizar arquivos" "Concluido. Log em $LOG_FILE"
fi

if [[ "$PAUSE" == "1" ]]; then
  read -r -p "Pressione Enter para fechar..."
fi
