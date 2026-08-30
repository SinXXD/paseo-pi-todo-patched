#!/usr/bin/env bash
# Paseo todo patch - auto-detect & apply (Linux/macOS, bash)
# - Auto-detects conventional Paseo install locations or uses custom path
# - Uses latest compiled server dist (builds if needed) and repacks app.asar
#
# Usage:
#   bash patch-paseo.sh
#   bash patch-paseo.sh --paseo-resources /opt/Paseo/resources
#   bash patch-paseo.sh --repo-root /path/to/paseo --skip-build --force
#
# Options:
#   --paseo-resources <path>  custom resources dir containing app.asar
#   --repo-root <path>        paseo repo root (default: auto-detect)
#   --skip-build              use existing dist, don't build
#   --force                   skip Paseo running check
#   --redo-backup             recreate backup even if exists

set -euo pipefail

PASEO_RESOURCES=""
REPO_ROOT=""
SKIP_BUILD=0
FORCE=0
REDO_BACKUP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paseo-resources) PASEO_RESOURCES="$2"; shift 2;;
    --repo-root) REPO_ROOT="$2"; shift 2;;
    --skip-build) SKIP_BUILD=1; shift;;
    --force) FORCE=1; shift;;
    --redo-backup) REDO_BACKUP=1; shift;;
    -h|--help) echo "Usage: $0 [--paseo-resources <path>] [--repo-root <path>] [--skip-build] [--force] [--redo-backup]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

find_repo_root() {
  local cands=()
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cands+=("$script_dir" "$(dirname "$script_dir")")
  [[ -n "$REPO_ROOT" ]] && cands+=("$REPO_ROOT")
  for c in "${cands[@]}"; do
    if [[ -f "$c/packages/server/src/server/agent/providers/pi/agent.ts" ]]; then echo "$c"; return 0; fi
  done
  echo "Cannot locate repo root (tried ${cands[*]}). Use --repo-root." >&2; return 1
}
trash_system() {
  local target="$1"
  [[ -e "$target" ]] || return 0
  if command -v gio >/dev/null 2>&1; then gio trash "$target" 2>/dev/null && return 0; fi
  if command -v trash-put >/dev/null 2>&1; then trash-put "$target" 2>/dev/null && return 0; fi
  if command -v kioclient5 >/dev/null 2>&1; then kioclient5 move "$target" trash:/ 2>/dev/null && return 0; fi
  local trash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files"
  mkdir -p "$trash_dir" 2>/dev/null
  mv -f "$target" "$trash_dir/" 2>/dev/null && return 0
  return 1
}

find_paseo_resources() {
  if [[ -n "$PASEO_RESOURCES" ]]; then
    if [[ -f "$PASEO_RESOURCES/app.asar" ]]; then echo "$PASEO_RESOURCES"; return 0; fi
    echo "Custom PaseoResources not found: $PASEO_RESOURCES/app.asar" >&2; return 1
  fi
  local candidates=(
    "/opt/Paseo/resources"
    "/opt/paseo/resources"
    "/usr/lib/paseo/resources"
    "/usr/share/paseo/resources"
    "/Applications/Paseo.app/Contents/Resources"
    "$HOME/.local/share/paseo/resources"
    "$HOME/Applications/Paseo.app/Contents/Resources"
  )
  # try which paseo
  if command -v paseo >/dev/null 2>&1; then
    local bin
    bin="$(command -v paseo)"
    local real
    real="$(readlink -f "$bin" 2>/dev/null || echo "$bin")"
    candidates+=("$(dirname "$(dirname "$real")")/resources")
  fi
  for c in "${candidates[@]}"; do
    if [[ -f "$c/app.asar" ]]; then echo "$c"; return 0; fi
  done
  echo "Paseo not found in conventional locations. Use --paseo-resources <path>." >&2; return 1
}

REPO_ROOT="$(find_repo_root)"
RESOURCES="$(find_paseo_resources)"
echo "RepoRoot: $REPO_ROOT"
echo "Resources: $RESOURCES"

APP_ASAR="$RESOURCES/app.asar"
APP_UNPACKED="$RESOURCES/app.asar.unpacked"
BACKUP_DIR="$REPO_ROOT/paseo-asar-backup"

# --- ensure @electron/asar ---
ASAR_BIN="$REPO_ROOT/node_modules/@electron/asar/bin/asar.js"
if [[ ! -f "$ASAR_BIN" ]]; then
  echo "Installing @electron/asar..."
  (cd "$REPO_ROOT" && npm install --no-save @electron/asar >/dev/null 2>&1)
fi

# --- build latest patched server if needed ---
AGENT_DIST="$REPO_ROOT/packages/server/dist/server/server/agent/providers/pi/agent.js"
MAPPER_DIST="$REPO_ROOT/packages/server/dist/server/server/agent/providers/pi/tool-call-mapper.js"
needs_build=0
if [[ "$SKIP_BUILD" -eq 0 ]]; then
  if [[ ! -f "$AGENT_DIST" ]]; then needs_build=1
  elif ! grep -q "mapTodoItemsFromToolResult" "$AGENT_DIST" 2>/dev/null; then needs_build=1
  elif ! grep -q "details.tasks" "$MAPPER_DIST" 2>/dev/null; then needs_build=1
  fi
fi
if [[ "$needs_build" -eq 1 ]]; then
  echo "Building patched server (latest)..."
  (cd "$REPO_ROOT" && node packages/protocol/scripts/generate-validation-aot.mjs)
  (cd "$REPO_ROOT" && npm ci 2>&1 | tail -5)
  (cd "$REPO_ROOT" && npm run build --workspace=@getpaseo/protocol 2>&1 | tail -3)
  (cd "$REPO_ROOT" && npm run build --workspace=@getpaseo/highlight 2>&1 | tail -3)
  (cd "$REPO_ROOT" && npm run build --workspace=@getpaseo/relay 2>&1 | tail -3)
  (cd "$REPO_ROOT" && npm run build --workspace=@getpaseo/client 2>&1 | tail -3)
  (cd "$REPO_ROOT" && npm run build --workspace=@getpaseo/plugin 2>&1 | tail -3 || npx tsc -p packages/plugin/tsconfig.json --incremental false)
  (cd "$REPO_ROOT" && npm run build --workspace=@getpaseo/server 2>&1 | tail -3)
  if [[ ! -f "$AGENT_DIST" ]]; then echo "Build failed: $AGENT_DIST not found" >&2; exit 1; fi
  echo "Build OK"
else
  echo "Using existing dist (skip build)"
fi

# --- Paseo running check ---
if pgrep -x "Paseo" >/dev/null 2>&1 || pgrep -f "Paseo" >/dev/null 2>&1; then
  if [[ "$FORCE" -eq 1 ]]; then echo "WARNING: Paseo is running, continuing due to --force"
  else echo "Paseo is running. Quit it completely then re-run."; exit 1; fi
fi

# --- write permission check ---
probe="$RESOURCES/__write_probe.tmp"
if ! (echo ok > "$probe" 2>/dev/null && (trash_system "$probe" 2>/dev/null || rm -f "$probe")); then
  echo "No write permission for $RESOURCES - run with sudo: sudo $0 $*" >&2; exit 1
fi

# --- prepare temp tree ---
TMP_TREE="$(mktemp -d /tmp/paseo-asar-tree.XXXXXX)"
TMP_OUT="$REPO_ROOT/out-patched.asar"
echo "Extracting app.asar..."
node "$ASAR_BIN" extract "$APP_ASAR" "$TMP_TREE" 2>&1 | head -3 || true
echo "Merging app.asar.unpacked..."
if [[ -d "$APP_UNPACKED" ]]; then
  (cd "$APP_UNPACKED" && tar cf - .) | (cd "$TMP_TREE" && tar xf -)
fi
TARGET_DIR="$TMP_TREE/node_modules/@getpaseo/server/dist/server/server/agent/providers/pi"
mkdir -p "$TARGET_DIR"
cp -f "$AGENT_DIST" "$MAPPER_DIST" "$TARGET_DIR/"
echo "Patched files injected"

# --- repack with platform-appropriate unpack ---
SHERPA="$(ls -d "$APP_UNPACKED"/node_modules/sherpa-onnx-* 2>/dev/null | head -1 | xargs -I{} basename {} 2>/dev/null || echo "sherpa-onnx-linux-x64")"
PAT="{**/node-pty,**/$SHERPA,**/dist/daemon,**/terminal/shell-integration}/**"
echo "Repacking (unpack: $PAT)..."

# use createPackageWithOptions (handles unpack correctly on Linux)
node -e "
const asar=require('@electron/asar');
const T=process.argv[1], O=process.argv[2], PAT=process.argv[3];
asar.createPackageWithOptions(T,O,{unpack:PAT}).then(()=>console.log('repack done')).catch(e=>{console.error(e);process.exit(1)});
" "$TMP_TREE" "$TMP_OUT" "$PAT"

if [[ ! -f "$TMP_OUT" ]]; then echo "Repack failed" >&2; exit 1; fi

# --- backup & deploy ---
mkdir -p "$BACKUP_DIR"
if [[ -f "$BACKUP_DIR/app.asar" && "$REDO_BACKUP" -eq 0 ]]; then
  echo "Backup exists, skipping (use --redo-backup to redo)"
else
  if [[ -d "$BACKUP_DIR" ]]; then trash_system "$BACKUP_DIR" 2>/dev/null || rm -rf "$BACKUP_DIR"; fi
  mkdir -p "$BACKUP_DIR"
  cp -a "$APP_ASAR" "$BACKUP_DIR/"
  cp -a "$APP_UNPACKED" "$BACKUP_DIR/"
  echo "Backup -> $BACKUP_DIR"
fi
cp -f "$TMP_OUT" "$APP_ASAR"
if [[ -d "$APP_UNPACKED" ]]; then trash_system "$APP_UNPACKED" 2>/dev/null || rm -rf "$APP_UNPACKED"; fi
cp -a "$TMP_OUT.unpacked" "$APP_UNPACKED"
echo "Deployed -> $RESOURCES"

# verify
if cmp -s "$APP_ASAR" "$TMP_OUT"; then echo "Verified (identical)"; else echo "Warning: hash mismatch"; fi
trash_system "$TMP_TREE" 2>/dev/null || rm -rf "$TMP_TREE"
echo "Done. Restart Paseo and test pi todo."
echo "Rollback: bash $REPO_ROOT/patch-paseo.sh --help  # or restore manually from $BACKUP_DIR"