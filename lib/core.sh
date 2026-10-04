#!/usr/bin/env bash
# ============================================================
# core.sh — 配置加载 + 状态管理（不含任何界面、不含安装细节）
# 数据来源：config/groups.conf、config/items.conf
# 状态存放：~/.local/state/devos-init/
# ============================================================

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devos-init"
DONE_DIR="$STATE_DIR/items"
LOG_FILE="$STATE_DIR/install.log"
mkdir -p "$DONE_DIR"

GROUP_IDS=()   # 分组 id 列表（顺序=配置顺序）
GROUP_NAMES=() # 分组显示名
IT_ID=()       # 条目并行数组
IT_GRP=()
IT_NAME=()
IT_DESC=()
IT_DEF=()      # 默认勾选 1/0
IT_ACT=()      # 动作

cfg_die() { printf '配置错误: %s\n' "$*" >&2; exit 1; }

load_config() {
  local conf gname
  conf="$(dirname "${BASH_SOURCE[0]}")/../config/groups.conf"
  [ -f "$conf" ] || cfg_die "找不到 $conf"
  while IFS='|' read -r gid gname _ || [ -n "$gid" ]; do
    case "$gid" in ''|\#*) continue;; esac
    GROUP_IDS+=("$gid"); GROUP_NAMES+=("$gname")
  done < "$conf"

  conf="$(dirname "${BASH_SOURCE[0]}")/../config/items.conf"
  [ -f "$conf" ] || cfg_die "找不到 $conf"
  local id g name desc def act ok
  while IFS='|' read -r id g name desc def act || [ -n "$id" ]; do
    case "$id" in ''|\#*) continue;; esac
    [ -n "$name" ] && [ -n "$act" ] || cfg_die "条目字段不全: $id"
    ok=0
    for gid in "${GROUP_IDS[@]}"; do [ "$gid" = "$g" ] && ok=1; done
    [ $ok -eq 1 ] || cfg_die "条目 $id 的分组 '$g' 不存在于 groups.conf"
    IT_ID+=("$id"); IT_GRP+=("$g"); IT_NAME+=("$name")
    IT_DESC+=("$desc"); IT_DEF+=("$def"); IT_ACT+=("$act")
  done < "$conf"
}

# ---- 查询辅助 ----
n_items() { echo ${#IT_ID[@]}; }

group_items() { # $1=group_id → 输出条目下标（每行一个）
  local i
  for i in "${!IT_ID[@]}"; do
    [ "${IT_GRP[$i]}" = "$1" ] && echo "$i"
  done
}

group_name() {
  local i
  for i in "${!GROUP_IDS[@]}"; do
    [ "${GROUP_IDS[$i]}" = "$1" ] && { echo "${GROUP_NAMES[$i]}"; return; }
  done
  echo "$1"
}

item_index() { # $1=item_id → 下标，找不到返回 1
  local i
  for i in "${!IT_ID[@]}"; do
    [ "${IT_ID[$i]}" = "$1" ] && { echo "$i"; return 0; }
  done
  return 1
}

# ---- 选择集操作（空格分隔的 id 串）----
sel_has() { case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

sel_defaults() { # 输出默认（最小集合）
  local i
  for i in "${!IT_ID[@]}"; do
    [ "${IT_DEF[$i]}" = "1" ] && printf '%s ' "${IT_ID[$i]}"
  done
  echo
}

sel_count() { # $1=选择集 → 件数
  local id c=0
  for id in $1; do c=$((c + 1)); done
  echo "$c"
}

# 按"显示宽度"补空格到 $2 列（中日韩字符算 2 列，保证表格对齐）
wpad() { # $1=字符串 $2=目标显示宽度
  local s="$1" w="$2" cur=0 i c code
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    code=$(printf '%d' "'$c" 2>/dev/null || echo 63)
    if [ "$code" -ge 128 ] 2>/dev/null; then cur=$((cur + 2)); else cur=$((cur + 1)); fi
  done
  if [ "$w" -gt "$cur" ]; then
    printf '%s%*s' "$s" $((w - cur)) ''
  else
    printf '%s' "$s"
  fi
}

# ---- 状态（幂等核心）----
is_done() { # $1=item_id
  [ -f "$DONE_DIR/$1.done" ] && return 0
  # 启发式探测：apt 装的标准命令，装过也算完成
  local i; i=$(item_index "$1") || return 1
  case "${IT_ACT[$i]}" in
    apt|apt:*) local pkg="${IT_ACT[$i]#apt:}"; [ "$pkg" = "${IT_ACT[$i]}" ] && pkg="${IT_ID[$i]}"
      # 只对"包名=命令名"的简单情形探测，避免误判
      case "${IT_ID[$i]}" in *-plugin|*config|*upgrade) return 1;; esac
      command -v "${IT_ID[$i]}" >/dev/null 2>&1 && return 0
      return 1;;
  esac
  return 1
}

mark_done()   { : > "$DONE_DIR/$1.done"; }
mark_undone() { rm -f "$DONE_DIR/$1.done"; }

done_count() { # $1=group_id → 已完成数
  local i c=0
  while IFS= read -r i; do
    is_done "${IT_ID[$i]}" && c=$((c+1))
  done < <(group_items "$1")
  echo "$c"
}

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"; }
