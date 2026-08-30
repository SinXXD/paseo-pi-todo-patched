<p align="center">
  <img src="packages/website/public/logo.svg" width="64" height="64" alt="Paseo logo">
</p>

<h1 align="center">Paseo — Pi Todo Patched</h1>

<p align="center">
  <a href="https://github.com/SinXXD/paseo-pi-todo-patched"><img src="https://img.shields.io/github/stars/SinXXD/paseo-pi-todo-patched?style=flat&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/SinXXD/paseo-pi-todo-patched/releases"><img src="https://img.shields.io/github/v/release/SinXXD/paseo-pi-todo-patched?label=patched%20release" alt="Patched release"></a>
  <a href="https://github.com/getpaseo/paseo"><img src="https://img.shields.io/badge/upstream-getpaseo%2Fpaseo-555?logo=github" alt="Upstream"></a>
</p>

<p align="center">Fork of <a href="https://github.com/getpaseo/paseo">getpaseo/paseo</a> with Pi provider todo rendering.<br>让 Pi 的 <code>todo</code> 在 Paseo 界面里显示为待办卡片。</p>

---

## Patch 说明

**问题**：Paseo 原版对 `pi` 未适配 `todo` — `pi` 的 `todo` 工具返回结构化 `details`，但 Paseo 只当普通工具卡。

**修复**（`Paseo 0.4.0 + pi 0.84.2` 验证，`Windows/Linux` 通用）：
- `packages/server/src/server/agent/providers/pi/tool-call-mapper.ts`：新增 `mapTodoItemsFromToolResult()` 兼容 `details.tasks`（`pi 内置`）与 `details.todos`（`pi-deck-todo 扩展`）
- `packages/server/src/server/agent/providers/pi/agent.ts`：`emitToolCallEvent` 在 `completed` 时发射 `{type:"todo"}`

## 一键打补丁

脚本自动检测常规安装位置或接受自填路径，**从本仓库 Release 拉取与你当前 Paseo 版本对应的预编译补丁**，无对应 Release 则报错。

**Windows（管理员 PowerShell）：**
```powershell
powershell -ExecutionPolicy Bypass -File patch-paseo.ps1
powershell -ExecutionPolicy Bypass -File patch-paseo.ps1 -PaseoResources "C:\Custom\Paseo\resources"
```

**Linux / macOS：**
```bash
bash patch-paseo.sh
bash patch-paseo.sh --paseo-resources /opt/Paseo/resources
sudo bash patch-paseo.sh
```

**上游**：`https://github.com/getpaseo/paseo` · **本仓库 Release**：`https://github.com/SinXXD/paseo-pi-todo-patched/releases`

## 工作流

- 每日 `02:00 UTC` 取官方最新 `v*` Release Tag，`patches/pi-todo.patch` 在该 Tag 上重放后构建，发布 `patched-v<version>`（与用户按发布版更新对齐，不追 `main`）
- 备份到 `paseo-asar-backup/`（系统回收站），回滚见脚本 `--help`

## License

AGPL-3.0（同上游）
