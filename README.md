# Candy Grove

[在线游玩](https://ppmark0712.github.io/CandyGrove/) · [GitHub 仓库](https://github.com/PPMark0712/CandyGrove)

Candy Grove 是一款以糖果树为棋盘的单人组合策略游戏。玩家与森林 AI 轮流剪下糖果及其下方的整段树枝，拿走最后一颗糖果的一方获胜。规则简单，但每次剪枝都会改变整片森林的胜负结构。

项目使用 **Godot 4.7.2** 与 GDScript 开发，可直接在浏览器中运行。画面、动画、输入、随机树生成、树形 DP 和 AI 均在 Godot 内实现，Web 版本通过官方模板导出为 WASM/PCK，不依赖外部图片或字体资源。

## 在线游玩

1. 打开 [Candy Grove 在线版](https://ppmark0712.github.io/CandyGrove/)。
2. 等待 Godot Web 游戏加载完成；首次打开需要下载游戏文件。
3. 点击任意糖果开始游戏。被点击的糖果及其全部后代会一起掉落，随后森林 AI 自动行动。

建议使用支持 WebGL 2 的最新版 Chrome、Edge、Firefox 或 Safari。游戏无需安装，也不需要登录；桌面端可使用鼠标和快捷键，触屏设备可直接点击糖果及界面按钮。

如果在线链接显示 404，说明 GitHub Pages 尚未完成首次部署。仓库维护者需要按下方 [GitHub Pages](#github-pages) 一节启用部署；普通玩家无需下载或运行源码。

## 项目特色

- **树上 Nim 玩法**：每次选择一个节点并删除整棵子树，初始局面保证玩家存在必胜策略。
- **基于 SG 的 AI**：实时计算 Sprague-Grundy 值，在必胜局面寻找制胜剪法，在必败局面尽量延长对局。
- **随机棋盘**：可配置 1–7 棵树、最大深度和每层宽度，随时生成新森林。
- **完整回合控制**：支持整轮撤回、重玩同一局、剪枝范围预览、胜负动画和 SG 调试视图。
- **浏览器即开即玩**：单线程 Godot Web 导出，不依赖 `SharedArrayBuffer` 或特殊响应头，可直接部署到 GitHub Pages。

## 本地运行

使用 Godot 4.7.2 打开 `project.godot`，按 F6/F5 运行主场景。

本地网页预览需要 Python 3.9+（仅负责构建和静态 HTTP 服务）：

```sh
python3 tools/web.py play
# 打开 http://127.0.0.1:8077
```

脚本自动寻找 `godot`、`godot4` 或 macOS 的 `/Applications/Godot.app`。其他安装路径可以指定：

```sh
GODOT_BIN=/path/to/godot python3 tools/web.py play
```

首次构建会从 Godot 官方 GitHub Release 获取约 20 MB 的**单线程 Web 模板**，存入 `.tools/templates/`。通过 HTTP Range 仅下载所需 ZIP 成员，并验证 ZIP CRC；不必下载完整的多平台模板包。构建日志在 `.tools/logs/`。

```sh
python3 tools/web.py test             # 算法及回合交互测试
python3 tools/web.py build            # 导出到 build/web/
python3 tools/web.py serve            # 预览已有构建
python3 tools/web.py serve --port 8080 # 端口被占用时
```

需要支持 WebGL 2 的现代浏览器，通过 HTTP/HTTPS 打开，不能双击 `index.html`。单线程导出不依赖 `SharedArrayBuffer` 或 COOP/COEP 响应头，适用于 GitHub Pages。

## 玩法与操作

1–7 棵树并排排列，根节点对齐在上方。玩家先手，与 AI 轮流选择糖果；被选糖果及其全部后代一起删除。**拿走最后一颗糖果的人获胜**，无合法操作的一方失败。根节点也可以删除。每个新局都会保证初始森林 SG 非零，因此玩家存在必胜策略。

| 操作 | 效果 |
| --- | --- |
| 左键点击糖果 | 删除对应子树；悬停提前高亮范围和数量 |
| Z / Undo round | 回到上一次玩家操作前，同时撤销 AI 回复 |
| R / Restart | 重玩同一组初始树 |
| D / Show SG | 显示节点 SG；悬停时以 `旧值>新值` 显示切除后向根更新的 SG |
| N / New grove | 打开新局配置：树数 1–7、最大深度 1–6、每层总宽度 1–20 |

层宽包含同一深度的全部树，且不会小于树的数量；根节点深度为 0。新局配置打开时暂停当前回合，`Esc` 或 Cancel 返回。撤回、重玩、换局在 AI 思考、选中预览、双方删除动画和终局时均可使用。双方使用相同的 0.62 秒剪断下落动画；AI 另有 0.70 秒思考和 0.45 秒选中预览。回合进行中不会接受第二次落子。按钮也支持 Tab 聚焦和键盘激活。

## AI 与 SG

对于可删除根节点的子树：

```text
SG(v) = 1 + XOR(SG(child))
SG(forest) = XOR(SG(root))
```

死亡节点的 SG 为 0，叶节点为 1。数据使用父节点先于子节点的拓扑顺序存储，每次删除/恢复后逆序树形 DP，更新 SG 和子树大小，耗时 O(n)。

AI 严格按以下优先级选择：

1. 森林 SG 非零：只考虑使对手森林 SG 变为零的操作，选择其中删除节点最多者；并列随机。
2. 森林 SG 为零：选择删除节点最少的操作，并列随机。

评估一刀只需沿祖先路径替换 SG，不复制棋盘，所有候选的评估复杂度为 O(nh)。生成器给每棵树分配固定层宽预算，任意深度的总节点数不超过配置值；默认 4 棵树、最大深度 3、每层最多 12 个节点。

## 验证

`tests/test_forest.gd` 使用独立的位掩码状态枚举与 mex 求解器作为基准，不复用生产 SG 公式：

- 枚举节点数 1–6 的全部父序拓扑，另测试 120 组固定种子的 9 节点森林。
- 共 993 种拓扑、37,944 个有效状态，核对森林/节点 SG、切除后 SG、全部最优候选和 AI 实际选择。
- 验证删除、恢复、悬停 SG 投影、必败态并列招法的随机性，以及所有生成配置的层宽、深度和必胜初态约束。

`tests/test_game.gd` 实例化真实主场景，验证配置面板、双方动画状态、重复输入拦截、各阶段整轮撤回、重玩、快捷键、双方获胜与终局撤回，以及默认/最大规模各 100 组布局的边界、根对齐、同层节点间距和点击命中。

测试失败或 GDScript 错误会使构建脚本返回非零，超时会明确报错。受限环境可能禁止编辑器可选的 ObjectDB profiler 创建 `user://` 快照目录；构建脚本保留这一提示，但仅忽略这条与游戏无关的编辑器诊断。

## GitHub Pages

仓库包含 `.github/workflows/pages.yml`：

1. 将仓库推送到 GitHub，默认分支为 `main`。
2. 在仓库 **Settings → Pages → Build and deployment** 中将 Source 设为 **GitHub Actions**。
3. 推送 `main` 或手动运行 **Test and deploy Godot Web**。

工作流安装匹配版本的 Godot，运行测试、导出 Web、上传 Pages artifact 并部署。PR 运行测试和导出，不部署。站点支持 `https://<用户名>.github.io/<仓库名>/` 子路径。也可以把 `build/web/` 整体托管到其他静态服务器。

本项目的预期在线地址为 <https://ppmark0712.github.io/CandyGrove/>。首次部署完成后，可以在仓库右侧 **Deployments** 或 **Actions** 页面查看部署状态和最终地址。

## 文件

```text
project.godot              Godot 工程入口
scenes/main.tscn           主场景
scripts/forest.gd          森林状态、树形 DP、AI
scripts/game.gd            棋盘绘制、动画、输入与回合状态机
tests/                    GDScript 验证脚本
tools/                    导出、模板下载、本地预览工具
export_presets.cfg         单线程 Web 导出配置
.github/workflows/         测试及 Pages 发布
```

糖果和界面均由 Godot 的 2D 绘图 API 绘制，无外部图片或字体依赖。`build/`、`.godot/`、`.tools/` 和需求文件 `plan.md` 均不进入 Git。
