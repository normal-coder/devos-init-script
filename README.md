# devos-init

带 TUI 的 Ubuntu 开发环境初始化脚本：勾选安装常用工具与 Zsh/Docker 配置，
幂等可重跑，**加软件 = 配置文件里加一行**，不改代码。

## 在目标主机上一行拉起

```bash
mkdir -p devos-init && curl -fsSL https://github.com/normal-coder/devos-init-script/archive/refs/heads/main.tar.gz | tar xz -C devos-init --strip-components=1 && ./devos-init/install.sh
```

- 不依赖 `git`（全新 Ubuntu 即可用；没有 `curl` 时改用 `wget -qO- … | tar xz …`）
- 安装完 `rm -rf devos-init` 即可清理；重复运行会自动跳过已完成项

## 使用

```bash
./install.sh              # 交互 TUI（菜单 → 选配 → 汇总 → 执行）
./install.sh --yes        # 一键最小集合（26 件）
./install.sh --dry-run    # 试运行：只打印不执行
./install.sh --only git,curl,docker-ce   # 只装指定条目
./install.sh --list       # 列出全部条目
./install.sh --status     # 查看完成进度
```

无 apt 的机器（如 macOS）自动进入试运行模式，界面全流程照常可跑。

选配屏：`↑↓` 移动，`x` 勾选/取消，`回车` 确认，每组顶部 `⊕ 全选本组`。

## 文件（6 个，就这些）

```
install.sh            入口编排：菜单 → 选配 → 汇总 → 逐件执行 → 结果
config/groups.conf    分组表：id|名称|描述
config/items.conf     条目表：id|分组|名称|描述|默认勾选|动作
lib/core.sh           读配置、完成状态、选择集运算
lib/ui.sh             界面：菜单/选配/汇总/确认/转圈（不碰安装）
lib/actions.sh        动作：apt、zshrc 受管块、gitcfg、docker、chsh（不碰界面）
```

以后加新软件 = `config/items.conf` 加一行；`lib/` 与 `install.sh` 零改动。

## 测试

```bash
bash test_select.sh   # 选配解析逻辑（6 用例，无需 TTY）
python3 test_pty.py   # 一键装全流程（伪终端）
python3 test_pty2.py  # 自选全流程（伪终端）
```
