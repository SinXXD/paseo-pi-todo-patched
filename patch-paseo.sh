#!/usr/bin/env bash
# Paseo todo patch - auto-detect & apply (Linux/macOS, bash)
# - Auto-detects conventional Paseo install locations or uses custom path
# - Fetches prebuilt patch for detected Paseo version from GitHub Release; errors if not found (no local build)
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

# --- try to fetch prebuilt patched files for this Paseo version (from patch repo release) ---
PASEO_VERSION=""
if command -v node >/dev/null 2>&1 && [[ -f "$APP_ASAR" ]]; then
  # ASAR_BIN may not yet be defined, use npx fallback
  PASEO_VERSION=$(node -e "try{const a=require('$REPO_ROOT/node_modules/@electron/asar'); const d=a.extractFile('$APP_ASAR','package.json'); console.log(JSON.parse(d.toString()).version)}catch(e){try{const a=require('@electron/asar'); const d=a.extractFile('$APP_ASAR','package.json'); console.log(JSON.parse(d.toString()).version)}catch(e2){}}" 2>/dev/null | tr -d '\r\n' | xargs)
fi
if [[ -z "$PASEO_VERSION" ]]; then
  # try Paseo binary --version (Linux)
  PASEO_BIN="$(dirname "$RESOURCES")/Paseo"
  [[ -x "$PASEO_BIN" ]] && PASEO_VERSION=$("$PASEO_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi
if [[ -n "$PASEO_VERSION" ]]; then
  NORM_VER=${PASEO_VERSION#v}
  echo "Detected Paseo version: $NORM_VER"
  RELEASE_TAG="patched-v$NORM_VER"
  BASE_URL="https://github.com/SinXXD/paseo-pi-todo-patched/releases/download/$RELEASE_TAG"
  TMP_AGENT="/tmp/paseo-patched-agent-$NORM_VER.js"
  TMP_MAPPER="/tmp/paseo-patched-mapper-$NORM_VER.js"
  FETCHED=0
  if command -v gh >/dev/null 2>&1; then
    if gh release download "$RELEASE_TAG" --repo SinXXD/paseo-pi-todo-patched --pattern "agent.js" --dir /tmp --clobber 2>/dev/null && \
       gh release download "$RELEASE_TAG" --repo SinXXD/paseo-pi-todo-patched --pattern "tool-call-mapper.js" --dir /tmp --clobber 2>/dev/null; then
      [[ -f /tmp/agent.js ]] && mv -f /tmp/agent.js "$TMP_AGENT" 2>/dev/null
      [[ -f /tmp/tool-call-mapper.js ]] && mv -f /tmp/tool-call-mapper.js "$TMP_MAPPER" 2>/dev/null
      if [[ -f "$TMP_AGENT" && -f "$TMP_MAPPER" ]]; then
        echo "Fetched prebuilt patch for v$NORM_VER ($RELEASE_TAG) via gh"
        FETCHED=1
      fi
    fi
  fi
  if [[ "$FETCHED" -eq 0 ]] && command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$BASE_URL/agent.js" -o "$TMP_AGENT" 2>/dev/null && curl -fsSL "$BASE_URL/tool-call-mapper.js" -o "$TMP_MAPPER" 2>/dev/null; then
      echo "Fetched prebuilt patch for v$NORM_VER ($RELEASE_TAG) via curl"
      FETCHED=1
    fi
  fi
  if [[ "$FETCHED" -eq 1 && -f "$TMP_AGENT" && -f "$TMP_MAPPER" ]]; then
    # override dist paths to use fetched files, skip local build
    AGENT_DIST_FETCHED="$TMP_AGENT"
    MAPPER_DIST_FETCHED="$TMP_MAPPER"
    # will be used below; mark to skip build
    SKIP_BUILD=1
    # defer assignment until after build check
    FETCHED_AGENT="$TMP_AGENT"
    FETCHED_MAPPER="$TMP_MAPPER"
  else
    echo "No prebuilt release for v$NORM_VER ($RELEASE_TAG)" >&2
  fi
fi

# --- ensure @electron/asar ---
ASAR_BIN="$REPO_ROOT/node_modules/@electron/asar/bin/asar.js"
if [[ ! -f "$ASAR_BIN" ]]; then
  echo "Installing @electron/asar..."
  (cd "$REPO_ROOT" && npm install --no-save @electron/asar >/dev/null 2>&1)
fi

# --- use fetched prebuilt (release must exist, no local build fallback) ---
if [[ -z "${FETCHED_AGENT:-}" || ! -f "${FETCHED_AGENT:-}" || -z "${FETCHED_MAPPER:-}" || ! -f "${FETCHED_MAPPER:-}" ]]; then
  echo "No prebuilt release for v${NORM_VER:-unknown} ($RELEASE_TAG). Please wait for the patch repo to publish patched-${NORM_VER:-unknown}." >&2
  exit 1
fi
AGENT_DIST="$FETCHED_AGENT"
MAPPER_DIST="$FETCHED_MAPPER"
echo "Using prebuilt patch for v$NORM_VER: $AGENT_DIST"

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