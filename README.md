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

**问题**：Paseo 原版对 `pi` provider 未适配 `todo` — `pi` 的 `todo` 工具返回结构化 `details`，但 Paseo 只会把它当普通工具卡，不显示成待办列表。

**修复**（`Paseo 0.4.0 + pi 0.84.2` 验证，`Windows/Linux` 通用）：
- `packages/server/src/server/agent/providers/pi/tool-call-mapper.ts`：`PiToolResultDetails` 新增 `todos`，新增 `mapTodoItemsFromToolResult()` 兼容两套结构
  - `pi 内置`：`details.tasks` / `subject` / `status==="completed"`
  - `pi-deck-todo 扩展`：`details.todos` / `text` / `done===true`
  → 统一为 `AgentTaskItem[]`
- `packages/server/src/server/agent/providers/pi/agent.ts`：`emitToolCallEvent` 在 `status==="completed"` 时若有 `todoItems` 则额外 `emit({type:"timeline", item:{type:"todo", items}})`，前端 `session-stream-reducers` 已支持 `todo` → `todo_list` 渲染

## 一键打补丁

脚本自动检测 Paseo 常规安装位置或接受自填路径，**从本仓库 Release 拉取与你当前 Paseo 版本对应的预编译补丁**（`patched-v<version>`），不存在则报错（不本地构建）。

**Windows（管理员 PowerShell）：**
```powershell
powershell -ExecutionPolicy Bypass -File patch-paseo.ps1
powershell -ExecutionPolicy Bypass -File patch-paseo.ps1 -PaseoResources "C:\Custom\Paseo\resources"
```
自动检测：`%ProgramFiles%\Paseo\resources` → `%LOCALAPPDATA%\Programs\Paseo` → 注册表 `Uninstall` 的 `InstallLocation`

**Linux / macOS：**
```bash
bash patch-paseo.sh
bash patch-paseo.sh --paseo-resources /opt/Paseo/resources
sudo bash patch-paseo.sh  # 写 /opt 需提权
```
自动检测：`/opt/Paseo` → `/opt/paseo` → `/usr/lib/paseo` → `/Applications/Paseo.app` → `which paseo` 旁

**选项**：`-PaseoResources`/`--paseo-resources` 自填，`-RepoRoot`/`--repo-root` 指定仓库根，`-Force`/`--force` 跳过运行检查，`-RedoBackup`/`--redo-backup` 重做备份

**版本对齐**：脚本先 `node -e "asar.extractFile(app.asar,'package.json').version"` 取你本机 `app.asar` 的 `version`，再 `gh release download patched-v<version>` 或 `curl https://github.com/SinXXD/paseo-pi-todo-patched/releases/download/patched-v<version>/agent.js`，无对应 Release 则报错。

**备份与回滚**：备份到 `paseo-asar-backup/`（系统回收站：Win `Microsoft.VisualBasic.FileIO` / Linux `gio trash`），`restore.ps1` / `patch-paseo.sh --help` 可回滚。

## 工作流与 Release

- **钉 Release Tag**：`schedule: 0 2 * * *` 每日 `gh api repos/getpaseo/paseo/releases/latest` 取官方最新 `v*`，`patches/pi-todo.patch` 在该 Tag 上 `git apply` 后构建，发布 `patched-v<version>`（与用户按发布版更新对齐，不追 `main`）
- **不随 `push` 自动构建**：`push` 到 `main` 不触发构建，仅 `schedule` 和 `workflow_dispatch` 触发
- **预编译产物**：`agent.js` / `tool-call-mapper.js`（`packages/server/dist/.../pi/`）

---



<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  <a href="https://github.com/getpaseo/paseo/stargazers">
    <img src="https://img.shields.io/github/stars/getpaseo/paseo?style=flat&logo=github" alt="GitHub stars">
  </a>
  <a href="https://github.com/getpaseo/paseo/releases">
    <img src="https://img.shields.io/github/v/release/getpaseo/paseo?style=flat&logo=github" alt="GitHub release">
  </a>
  <a href="https://x.com/moboudra">
    <img src="https://img.shields.io/badge/%40moboudra-555?logo=x" alt="X">
  </a>
  <a href="https://discord.gg/jz8T2uahpH">
    <img src="https://img.shields.io/badge/Discord-555?logo=discord" alt="Discord">
  </a>
  <a href="https://www.reddit.com/r/PaseoAI/">
    <img src="https://img.shields.io/badge/Reddit-555?logo=reddit" alt="Reddit">
  </a>
</p>

<p align="center">One interface for Claude Code, Codex, Copilot, OpenCode, and Pi agents.</p>

<p align="center">
  <img src="https://paseo.sh/hero-mockup.png" alt="Paseo app screenshot" width="100%">
</p>

<p align="center">
  <img src="https://paseo.sh/mobile-mockup.png" alt="Paseo mobile app" width="100%">
</p>

Run agents in parallel on your own machines. Ship from your phone or your desk.

- **Self-hosted:** Agents run on your machine with your full dev environment. Use your tools, your configs, and your skills.
- **Multi-provider:** Claude Code, Codex, Copilot, OpenCode, and Pi through the same interface. Pick the right model for each job.
- **Voice control:** Dictate tasks or talk through problems in voice mode. Hands-free when you need it.
- **Cross-device:** iOS, Android, desktop, web, and CLI. Start work at your desk, check in from your phone, script it from the terminal.
- **Privacy-first:** Paseo doesn't have any telemetry, tracking, or forced log-ins.

## Getting Started

Paseo runs a local server called the daemon that manages your coding agents. Clients like the desktop app, mobile app, web app, and CLI connect to it.

### Prerequisites

You need at least one agent CLI installed and configured with your credentials:

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Codex](https://github.com/openai/codex)
- [GitHub Copilot](https://github.com/features/copilot/cli/)
- [OpenCode](https://github.com/anomalyco/opencode)
- [Pi](https://pi.dev)

### Desktop app (recommended)

Download it from [paseo.sh/download](https://paseo.sh/download) or the [GitHub releases page](https://github.com/getpaseo/paseo/releases). Open the app and the daemon starts automatically. Nothing else to install.

To connect from your phone, open **Settings → your host → Pair Device**.

### CLI / headless

Install the CLI and start Paseo:

```bash
npm install -g @getpaseo/cli
paseo
```

Paseo starts locally, then asks whether to enable the end-to-end encrypted relay for device pairing. If you decline, connect directly over TCP, Tailscale, or another VPN. This path is useful for servers and remote machines.

For full setup and configuration, see:

- [Docs](https://paseo.sh/docs)
- [Connectivity guide](https://paseo.sh/docs/connectivity)
- [Configuration reference](https://paseo.sh/docs/configuration)

### Docker

Run the Paseo daemon and self-hosted web UI in Docker:

```bash
docker run -d --name paseo \
  -p 6767:6767 \
  -e PASEO_PASSWORD=change-me \
  -v "$PWD/paseo-home:/home/paseo" \
  -v "$PWD:/workspace" \
  ghcr.io/getpaseo/paseo:latest
```

Open `http://localhost:6767` after it starts. Extend the base image with the agent CLIs you use, then provide credentials through environment variables or the persistent `/home/paseo` volume. See the [Docker documentation](docs/docker.md) for full setup details.

## CLI

Everything you can do in the app, you can do from the terminal.

```bash
paseo run --provider claude/opus-4.6 "implement user authentication"
paseo run --provider codex/gpt-5.5 --worktree feature-x "implement feature X"

paseo ls                           # list running agents
paseo attach abc123                # stream live output
paseo send abc123 "also add tests" # follow-up task

# run on a remote daemon
paseo --host workstation.local:6767 run "run the full test suite"
```

See the [full CLI reference](https://paseo.sh/docs/cli) for more.

## TypeScript SDK

Build issue integrations, dashboards, and orchestration services with `@getpaseo/client`:

```ts
import { createPaseoClient } from "@getpaseo/client";

const client = createPaseoClient({ url: "ws://127.0.0.1:6767/ws" });
await client.connect();

const agent = await client.agents.create({
  config: { provider: "codex/gpt-5.5" },
  cwd: "/Users/me/dev/storefront",
  prompt: "Review the current diff and name the riskiest change.",
});

const result = await agent.waitForFinish();
console.log(result.lastMessage);

await client.close();
```

See the [SDK quickstart](https://paseo.sh/docs/sdk/quickstart), [recipes](https://paseo.sh/docs/sdk/recipes), and [API reference](https://paseo.sh/docs/sdk/reference).

## Skills

Skills teach your agent to use Paseo to orchestrate other agents.

```bash
npx skills add getpaseo/paseo
```

Then use them in any agent conversation:

- `/paseo-handoff` — hand off work between agents. I use this to plan with Claude and then handoff to Codex to implement.
- `/paseo-advisor` — spin up a single agent as an advisor for a second opinion, without delegating the work itself.
- `/paseo-committee` — form a committee of two contrasting agents to step back, do root cause analysis, and produce a plan.

## Development

Quick monorepo package map:

- `packages/server`: Paseo daemon (agent process orchestration, WebSocket API, MCP server)
- `packages/app`: Expo client (iOS, Android, web)
- `packages/cli`: `paseo` CLI for daemon and agent workflows
- `packages/desktop`: Electron desktop app
- `packages/relay`: Relay transport and encryption used by the daemon and clients
- `packages/website`: Marketing site and documentation (`paseo.sh`)

Common commands:

```bash
# run all local dev services
npm run dev

# run individual surfaces
npm run dev:server
npm run dev:app
npm run dev:desktop
npm run dev:website

# build the server stack
npm run build:server

# repo-wide checks
npm run typecheck
```

## Related projects

- [getpaseo/paseo-relay](https://github.com/getpaseo/paseo-relay) — official distributed relay, written in Elixir
- [paseo-skins](https://github.com/huangguang1999/paseo-skins) — community themes and a zero-patch desktop theme loader with an Agent Skill
- [paseo-vscode](https://marketplace.visualstudio.com/items?itemName=hinnes.paseo-vscode) — VS Code extension

## License

AGPL-3.0
