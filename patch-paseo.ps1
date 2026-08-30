# Paseo todo patch - auto-detect & apply (Windows, PowerShell)
# - Auto-detects conventional Paseo install locations or uses custom path
# - Uses latest compiled server dist (builds if needed) and repacks app.asar
#
# Usage (elevated PowerShell):
#   powershell -ExecutionPolicy Bypass -File patch-paseo.ps1
#   powershell -ExecutionPolicy Bypass -File patch-paseo.ps1 -PaseoResources "C:\Custom\Paseo\resources"
#   powershell -ExecutionPolicy Bypass -File patch-paseo.ps1 -RepoRoot "D:\path\to\paseo"
#
# Options:
#   -PaseoResources <path>  custom resources dir containing app.asar (auto-detect if omitted)
#   -RepoRoot <path>        paseo repo root (default: auto-detect from script location)
#   -SkipBuild              use existing dist, don't build
#   -Force                  skip Paseo running check
#   -RedoBackup             recreate backup even if exists

param(
  [string]$PaseoResources,
  [string]$RepoRoot,
  [switch]$SkipBuild,
  [switch]$Force,
  [switch]$RedoBackup
)
$ErrorActionPreference = 'Stop'

# --- System recycle bin helper (no Node dependency) ---
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
function Move-ToRecycleBin {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return }
  try {
    if (Test-Path $Path -PathType Container) {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
    return
  } catch {}
  # Fallback: Shell.Application verb
  try {
    $shell = New-Object -ComObject Shell.Application -ErrorAction Stop
    $parent = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    $folder = $shell.Namespace($parent)
    $item = $folder.ParseName($leaf)
    if ($item) { $item.InvokeVerb("delete") }
  } catch {}
}

function Find-RepoRoot {
  $candidates = @($PSScriptRoot, (Split-Path $PSScriptRoot -Parent))
  foreach ($c in $candidates) {
    if (Test-Path (Join-Path $c "packages/server/src/server/agent/providers/pi/agent.ts")) { return $c }
  }
  if ($RepoRoot -and (Test-Path $RepoRoot)) { return $RepoRoot }
  throw "Cannot locate paseo repo root (tried $candidates). Use -RepoRoot."
}
function Find-PaseoResources {
  param([string]$Custom)
  if ($Custom -and (Test-Path (Join-Path $Custom "app.asar"))) { return $Custom }
  if ($Custom) { throw "Custom PaseoResources not found: $Custom/app.asar" }
  $candidates = @(
    "$env:ProgramFiles\Paseo\resources",
    "${env:ProgramFiles(x86)}\Paseo\resources",
    "$env:LOCALAPPDATA\Programs\Paseo\resources",
    "$env:APPDATA\Paseo\resources",
    "C:\Program Files\Paseo\resources"
  )
  # registry uninstall
  try {
    $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($rp in $regPaths) {
      Get-ItemProperty $rp -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Paseo*" } | ForEach-Object {
        if ($_.InstallLocation) { $candidates += Join-Path $_.InstallLocation "resources" }
      }
    }
  } catch {}
  foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c "app.asar"))) { Write-Host "Detected Paseo resources: $c" -ForegroundColor Cyan; return $c }
  }
  throw "Paseo not found in conventional locations. Use -PaseoResources <path-to-resources>."
}

$RepoRoot = Find-RepoRoot
if (-not $RepoRoot) { $RepoRoot = $PSScriptRoot }
Write-Host "RepoRoot: $RepoRoot" -ForegroundColor DarkGray
$Resources = Find-PaseoResources -Custom $PaseoResources
Write-Host "Resources: $Resources" -ForegroundColor DarkGray
$AppAsar = Join-Path $Resources "app.asar"
$AppUnpacked = Join-Path $Resources "app.asar.unpacked"
$BackupDir = Join-Path $RepoRoot "paseo-asar-backup"

# --- ensure @electron/asar available ---
$AsarBin = Join-Path $RepoRoot "node_modules/@electron/asar/bin/asar.js"
if (-not (Test-Path $AsarBin)) {
  Write-Host "Installing @electron/asar..." -ForegroundColor Yellow
  Push-Location $RepoRoot; npm install --no-save @electron/asar 2>&1 | Out-Null; Pop-Location
}

# --- build latest patched server if needed ---
$AgentSrc = Join-Path $RepoRoot "packages/server/src/server/agent/providers/pi/agent.ts"
$AgentDist = Join-Path $RepoRoot "packages/server/dist/server/server/agent/providers/pi/agent.js"
$MapperDist = Join-Path $RepoRoot "packages/server/dist/server/server/agent/providers/pi/tool-call-mapper.js"
$needsBuild = $false
if (-not $SkipBuild) {
  if (-not (Test-Path $AgentDist)) { $needsBuild = $true }
  elseif (-not (Select-String -Path $AgentDist -Pattern "mapTodoItemsFromToolResult" -Quiet)) { $needsBuild = $true }
  elseif (-not (Select-String -Path $MapperDist -Pattern "details\.tasks" -Quiet)) { $needsBuild = $true }
}
if ($needsBuild) {
  Write-Host "Building patched server (latest)..." -ForegroundColor Yellow
  Push-Location $RepoRoot
  # generate validators first
  node packages/protocol/scripts/generate-validation-aot.mjs
  # try npm workspaces, fallback to direct tsc for Windows PATH bug
  $buildOk = $false
  try { npm run build --workspace=@getpaseo/server 2>&1 | Out-Null; if (Test-Path $AgentDist) { $buildOk = $true } } catch {}
  if (-not $buildOk) {
    Write-Host "npm build failed, falling back to direct tsc..." -ForegroundColor Yellow
    node node_modules/typescript/bin/tsc -p packages/protocol/tsconfig.json --incremental false
    node node_modules/typescript/bin/tsc -p packages/highlight/tsconfig.json --incremental false
    node node_modules/typescript/bin/tsc -p packages/relay/tsconfig.json --incremental false
    node node_modules/typescript/bin/tsc -p packages/client/tsconfig.json --incremental false
    node node_modules/typescript/bin/tsc -p packages/plugin/tsconfig.json --incremental false
    node node_modules/typescript/bin/tsc -p packages/server/tsconfig.server.json --incremental false
  }
  Pop-Location
  if (-not (Test-Path $AgentDist)) { throw "Build failed: $AgentDist not found" }
  Write-Host "Build OK" -ForegroundColor Green
} else {
  Write-Host "Using existing dist (skip build)" -ForegroundColor DarkGray
}

# --- try to fetch prebuilt patched files for this Paseo version (from patch repo release) ---
$PaseoVersion = $null
try {
  $escAppAsar = $AppAsar -replace "'", "''"
  $verJson = node -e "try{const a=require('@electron/asar'); const d=a.extractFile('$escAppAsar','package.json'); console.log(JSON.parse(d.toString()).version)}catch(e){}" 2>$null
  $verJson = "$verJson".Trim()
  if ($verJson) { $PaseoVersion = $verJson }
} catch {}
if (-not $PaseoVersion) {
  try {
    $exe = Join-Path (Split-Path $Resources -Parent) "Paseo.exe"
    if (Test-Path $exe) { $v = (Get-Item $exe).VersionInfo.FileVersion; if ($v) { $PaseoVersion = $v.Trim() } }
  } catch {}
}
if ($PaseoVersion) {
  # normalize: keep e.g. 0.6.1, strip leading v
  $normVer = $PaseoVersion -replace '^v',''
  Write-Host "Detected Paseo version: $normVer" -ForegroundColor Cyan
  $releaseTag = "patched-v$normVer"
  $baseUrl = "https://github.com/SinXXD/paseo-pi-todo-patched/releases/download/$releaseTag"
  $tmpAgent = Join-Path $env:TEMP "paseo-patched-agent-$normVer.js"
  $tmpMapper = Join-Path $env:TEMP "paseo-patched-mapper-$normVer.js"
  $fetched = $false
  try {
    Write-Host "Trying to fetch prebuilt patch $releaseTag from GitHub..." -ForegroundColor DarkGray
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh) {
      & gh release download $releaseTag --repo SinXXD/paseo-pi-todo-patched --pattern "agent.js" --dir $env:TEMP --clobber 2>&1 | Out-Null
      & gh release download $releaseTag --repo SinXXD/paseo-pi-todo-patched --pattern "tool-call-mapper.js" --dir $env:TEMP --clobber 2>&1 | Out-Null
      if (Test-Path "$env:TEMP/agent.js") { Move-Item "$env:TEMP/agent.js" $tmpAgent -Force }
      if (Test-Path "$env:TEMP/tool-call-mapper.js") { Move-Item "$env:TEMP/tool-call-mapper.js" $tmpMapper -Force }
    }
    if (-not (Test-Path $tmpAgent)) {
      Invoke-WebRequest -Uri "$baseUrl/agent.js" -OutFile $tmpAgent -UseBasicParsing -ErrorAction Stop
      Invoke-WebRequest -Uri "$baseUrl/tool-call-mapper.js" -OutFile $tmpMapper -UseBasicParsing -ErrorAction Stop
    }
    if ((Test-Path $tmpAgent) -and (Test-Path $tmpMapper)) {
      Write-Host "Fetched prebuilt patch for v$normVer ($releaseTag)" -ForegroundColor Green
      $AgentDist = $tmpAgent
      $MapperDist = $tmpMapper
    } else { throw "download incomplete" }
    $fetched = $true
  } catch {
    Write-Host "No prebuilt release for v$normVer ($releaseTag), will use local build. ($($_.Exception.Message))" -ForegroundColor Yellow
  }
} else {
  Write-Host "Could not detect Paseo version, using local build" -ForegroundColor Yellow
}

# --- Paseo running check ---
$procs = @(Get-Process -Name 'Paseo' -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0 -and -not $Force) {
  Write-Host "Paseo is running ($($procs.Count) processes). Quit it completely then re-run." -ForegroundColor Yellow
  exit 1
}

# --- write permission check ---
try { $probe = Join-Path $Resources "__write_probe.tmp"; Set-Content -Path $probe -Value ok -ErrorAction Stop; Move-ToRecycleBin -Path $probe; if (Test-Path $probe) { Remove-Item $probe -Force -ErrorAction SilentlyContinue }; Write-Host "resources writable" -ForegroundColor DarkGray } catch {
  Write-Host "No write permission for $Resources - run as administrator." -ForegroundColor Red; exit 1
}

# --- prepare temp tree ---
$TmpTree = Join-Path $env:TEMP "paseo-asar-tree-$(Get-Random)"
$TmpOut = Join-Path $RepoRoot "out-patched.asar"
if (Test-Path $TmpTree) { Move-ToRecycleBin -Path $TmpTree; if (Test-Path $TmpTree) { Remove-Item $TmpTree -Recurse -Force -ErrorAction SilentlyContinue } }
New-Item -ItemType Directory -Path $TmpTree | Out-Null

Write-Host "Extracting app.asar..." -ForegroundColor DarkGray
node $AsarBin extract $AppAsar $TmpTree 2>&1 | Out-Null
# copy unpacked content back
if (Test-Path $AppUnpacked) {
  Write-Host "Merging app.asar.unpacked..." -ForegroundColor DarkGray
  # use tar if available (Git Bash), else Copy-Item
  $tar = Get-Command tar -ErrorAction SilentlyContinue
  if ($tar) { & tar -cf - -C $AppUnpacked . | & tar -xf - -C $TmpTree 2>&1 | Out-Null }
  else { Copy-Item (Join-Path $AppUnpacked "*") -Destination $TmpTree -Recurse -Force }
}
# overwrite patched files
$TargetDir = Join-Path $TmpTree "node_modules/@getpaseo/server/dist/server/server/agent/providers/pi"
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
Copy-Item $AgentDist  -Destination $TargetDir -Force
Copy-Item $MapperDist -Destination $TargetDir -Force
Write-Host "Patched files injected"

# --- repack with Windows-compatible wrapper ---
# auto-detect sherpa variant from unpacked
$sherpa = Get-ChildItem (Join-Path $AppUnpacked "node_modules") -Filter "sherpa-onnx-*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$sherpaPat = if ($sherpa) { $sherpa.Name } else { "sherpa-onnx-win-x64" }
$Pat = "{**/node-pty,**/$sherpaPat,**/dist/daemon,**/terminal/shell-integration}/**"
Write-Host "Repacking (unpack: $Pat)..." -ForegroundColor DarkGray

# swap.mjs wrapper handles Windows backslash + dot-dir
$SwapMjs = Join-Path $RepoRoot "swap.mjs"
if (-not (Test-Path $SwapMjs)) {
  # create minimal wrapper inline if missing
  $SwapMjs = Join-Path $env:TEMP "paseo-swap-$(Get-Random).mjs"
  @'
import {createRequire} from "node:module"; import {dirname,resolve} from "node:path";
const require=createRequire(import.meta.url);
const asarPkgDir=dirname(require.resolve("@electron/asar/package.json"));
const mmPath=resolve(require.resolve("minimatch",{paths:[asarPkgDir]}));
const rawMM=require(mmPath); const wrapped=(f,p,o)=>rawMM(String(f).replace(/\\/g,"/"),p,o);
for(const k of Object.keys(rawMM)) wrapped[k]=rawMM[k]; require.cache[mmPath].exports=wrapped;
const asar=require("@electron/asar"); const T=process.argv[2],O=process.argv[3];
const PAT=process.argv[4]||"{**/node-pty,**/sherpa-onnx-win-x64,**/dist/daemon,**/terminal/shell-integration}/**";
asar.createPackageWithOptions(T,O,{unpack:PAT}).then(()=>console.log("repack done")).catch(e=>{console.error(e);process.exit(1)});
'@ | Set-Content -Path $SwapMjs -Encoding UTF8
}
node $SwapMjs $TmpTree $TmpOut $Pat
if (-not (Test-Path $TmpOut)) { throw "Repack failed: $TmpOut not created" }
if (-not (Test-Path "$TmpOut.unpacked")) { Write-Host "Note: unpacked dir not created (check PAT)" -ForegroundColor Yellow }

# --- backup & deploy ---
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$bakAsar = Join-Path $BackupDir "app.asar"
if ((Test-Path $bakAsar) -and -not $RedoBackup) {
  Write-Host "Backup exists, skipping (use -RedoBackup to redo)" -ForegroundColor Yellow
} else {
  if (Test-Path $BackupDir) { Move-ToRecycleBin -Path $BackupDir; if (Test-Path $BackupDir) { Remove-Item $BackupDir -Recurse -Force -ErrorAction SilentlyContinue }; New-Item -ItemType Directory -Path $BackupDir | Out-Null }
  Copy-Item $AppAsar -Destination $BackupDir
  Copy-Item $AppUnpacked -Destination $BackupDir -Recurse
  Write-Host "Backup -> $BackupDir"
}
Copy-Item $TmpOut -Destination $AppAsar -Force
if (Test-Path $AppUnpacked) { Move-ToRecycleBin -Path $AppUnpacked; if (Test-Path $AppUnpacked) { Remove-Item $AppUnpacked -Recurse -Force -ErrorAction SilentlyContinue } }
Copy-Item "$TmpOut.unpacked" -Destination $AppUnpacked -Recurse
Write-Host "Deployed -> $Resources" -ForegroundColor Green

# verify
$h1=(Get-FileHash $AppAsar -Algorithm SHA256).Hash; $h2=(Get-FileHash $TmpOut -Algorithm SHA256).Hash
if ($h1 -eq $h2) { Write-Host "Verified (hash match)" -ForegroundColor Green } else { Write-Host "Warning: hash mismatch" -ForegroundColor Red }

Move-ToRecycleBin -Path $TmpTree; if (Test-Path $TmpTree) { Remove-Item $TmpTree -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "Done. Restart Paseo and test pi todo." -ForegroundColor Green
Write-Host "Rollback: powershell -ExecutionPolicy Bypass -File $RepoRoot/restore.ps1" -ForegroundColor DarkGray