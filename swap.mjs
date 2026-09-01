// Paseo todo 补丁重打包脚本（Windows）
// 用法: node swap.mjs <inTree> <outAsar>
// Windows 兼容：asar 库用 minimatch(filename绝对路径) 匹配 unpack，
// 反斜杠路径不匹配正斜杠 glob → 在进程内包装 minimatch，把文件名正斜杠化。
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
const require = createRequire(import.meta.url);

// 1) 包装 @electron/asar 实际解析到的 minimatch（嵌套副本）
const asarPkgDir = dirname(require.resolve("@electron/asar/package.json"));
const mmPath = resolve(
  require.resolve("minimatch", { paths: [asarPkgDir] })
);
const rawMM = require(mmPath);
const wrappedMM = (filename, pattern, opts) =>
  rawMM(String(filename).replace(/\\/g, "/"), pattern, opts);
// 保留原函数上的属性（如 .Minimatch 构造器，glob 依赖）
for (const k of Object.keys(rawMM)) wrappedMM[k] = rawMM[k];
require.cache[mmPath].exports = wrappedMM;

// 2) 打包
const asar = require("@electron/asar");
const TREE = process.argv[2];
const OUT_ASAR = process.argv[3];

// 与发布版 app.asar.unpacked 分离结构一致（Windows 版）
const PAT =
  "{**/node-pty,**/sherpa-onnx-win-x64,**/terminal/shell-integration}/**";

asar
  .createPackageWithOptions(TREE, OUT_ASAR, { unpack: PAT })
  .then(() => console.log("done:", OUT_ASAR))
  .catch((err) => {
    console.error("repack failed:", err);
    process.exit(1);
  });