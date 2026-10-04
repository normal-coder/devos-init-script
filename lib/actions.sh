#!/usr/bin/env bash
# ============================================================
# actions.sh — 安装动作实现（不含界面）
# 每种动作一个函数：run_action 按 config items.conf 的动作字段分发
#   upgrade | apt[:包名] | zshrc:<行内容> | gitcfg
#   docker_engine | docker_plugin | docker_group | chsh
# 依赖：core.sh 提供 log/is_done；ui.sh 提供 ui_input（gitcfg 用）
# ============================================================

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

apt_install() { log "apt install $*"; $SUDO apt-get install -y "$@"; }

run_action() { # $1=item_id
  local i act pkg
  i=$(item_index "$1") || { log "未知条目 $1"; return 1; }
  act="${IT_ACT[$i]}"
  case "$act" in
    upgrade)
      log "apt update && upgrade"
      $SUDO apt-get update
      $SUDO apt-get upgrade -y ;;
    apt)
      apt_install "${IT_ID[$i]}" ;;
    apt:*)
      apt_install "${act#apt:}" ;;
    zshrc:*)
      : # 受管块在全部条目装完后统一生成（见 finalize_zshrc）
      ;;
    gitcfg)     action_gitcfg ;;
    chsh)       action_chsh ;;
    docker_engine)  action_docker_engine ;;
    docker_plugin)  action_docker_plugin "$1" ;;
    docker_group)   action_docker_group ;;
    *)
      log "未实现的动作: $act (条目 $1)"; return 1 ;;
  esac
}

# ---- 自定义动作 ----

action_gitcfg() {
  local name email branch
  name=$(ui_input "git 用户名" "$(git config --global user.name 2>/dev/null || echo "$USER")")
  email=$(ui_input "git 邮箱" "$(git config --global user.email 2>/dev/null || echo "$USER@users.noreply.github.com")")
  branch=$(ui_input "默认分支" "main")
  git config --global user.name "$name"
  git config --global user.email "$email"
  git config --global init.defaultBranch "$branch"
  git config --global pull.rebase true
  log "git 全局配置完成: $name <$email> $branch"
}

action_chsh() {
  local zsh_path; zsh_path=$(command -v zsh) || { log "zsh 不存在，跳过 chsh"; return 1; }
  if [ "$SHELL" = "$zsh_path" ]; then log "默认 shell 已是 zsh"; return 0; fi
  log "chsh -> $zsh_path"
  # 用 sudo 避免交互式输密码（步骤在后台执行，stdin 已重定向）
  $SUDO chsh -s "$zsh_path" "$USER"
}

ensure_docker_repo() {
  [ -f /etc/apt/keyrings/docker.gpg ] && return 0
  log "配置 Docker 官方 apt 源"
  $SUDO apt-get install -y ca-certificates curl gnupg
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
  $SUDO apt-get update
}

action_docker_engine() {
  ensure_docker_repo
  apt_install docker-ce docker-ce-cli containerd.io
}

action_docker_plugin() { # $1=item_id
  ensure_docker_repo
  case "$1" in
    docker-compose) apt_install docker-compose-plugin ;;
    docker-buildx)  apt_install docker-buildx-plugin ;;
    *) log "未知 docker 插件条目: $1"; return 1 ;;
  esac
}

action_docker_group() {
  local u="${SUDO_USER:-$USER}"
  log "usermod -aG docker $u"
  $SUDO usermod -aG docker "$u"
}

# ---- Zsh 受管块：全部条目处理完后按"当前选择"统一重写 ----
# 规则：选择集里至少有 1 个 zshrc: 条目才重写；一个都没有则不动旧块
ZSHRC_BEGIN="# >>> devos-init managed >>>"
ZSHRC_END="# <<< devos-init managed <<<"

finalize_zshrc() { # $1=选择集（空格分隔 id）
  local sel="$1" i line has_any=0 block
  for i in "${!IT_ID[@]}"; do
    case "${IT_ACT[$i]}" in zshrc:*) sel_has "$sel" "${IT_ID[$i]}" && has_any=1;; esac
  done
  if [ "$has_any" = 0 ]; then
    log "选择集中无 zshrc 条目，保留 ~/.zshrc 现状"
    return 0
  fi

  block="$ZSHRC_BEGIN
source /usr/share/zsh-antigen/antigen.zsh"
  for i in "${!IT_ID[@]}"; do
    case "${IT_ACT[$i]}" in
      zshrc:*)
        if sel_has "$sel" "${IT_ID[$i]}"; then
          block+=$'\n'"${IT_ACT[$i]#zshrc:}"
        fi ;;
    esac
  done
  block+=$'\n'"antigen apply
$ZSHRC_END"

  # 先删旧受管块，再追加（绝不碰块外内容）
  local zshrc="$HOME/.zshrc"
  touch "$zshrc"
  local tmp; tmp=$(mktemp)
  awk -v b="$ZSHRC_BEGIN" -v e="$ZSHRC_END" '
    $0 == b { skip=1; next }
    $0 == e { skip=0; next }
    !skip { print }
  ' "$zshrc" > "$tmp"
  # 去掉旧块留下的尾部空行，再追加
  sed -i -e :a -e '/^\n*$/{$d;N;};/\n$/ba' "$tmp" 2>/dev/null || true
  printf '\n%s\n' "$block" >> "$tmp"
  mv "$tmp" "$zshrc"
  log "已更新 ~/.zshrc 受管块"
}
