#!/usr/bin/env bash
# ============================================================
# devos-init — Ubuntu 开发环境初始化（TUI）
#
#   ./install.sh              交互菜单
#   ./install.sh --yes        一键装最小集合（不询问）
#   ./install.sh --only id    只装指定条目（逗号分隔）
#   ./install.sh --list       列出全部条目
#   ./install.sh --status     查看完成进度
#   ./install.sh --dry-run    试运行（只显示会做什么，不真装）
#
# 三层结构：config/ 数据  ·  lib/ui.sh 界面  ·  lib/actions.sh 动作
# 加新软件 = config/items.conf 加一行，本文件不用改
# ============================================================
set -euo pipefail

BASE=$(cd "$(dirname "$0")" && pwd)
. "$BASE/lib/core.sh"
. "$BASE/lib/ui.sh"
. "$BASE/lib/actions.sh"

YES=0 DRY=${DRY:-0} ONLY=""
ACTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)     YES=1 ;;
    --dry-run)    DRY=1 ;;
    --list)       ACTION=list ;;
    --status)     ACTION=status ;;
    --only)       shift; ONLY="${1:-}"; ACTION=only ;;
    --help|-h)    ACTION=help ;;
    *) echo "未知参数: $1（--help 查看用法）"; exit 1 ;;
  esac
  shift
done

load_config

# 非 Ubuntu/Debian（比如开发用的 macOS）没有 apt-get → 自动降为试运行
# （--help/--list/--status 不涉及执行，不提示）
case "$ACTION" in help|list|status) ;; *)
  if [ "$DRY" = 0 ] && ! command -v apt-get >/dev/null 2>&1; then
    DRY=1
    echo "⚠ 未检测到 apt-get，自动进入试运行模式（只演练不安装）"
    echo
  fi ;;
esac

show_help() {
  cat <<'EOF'
用法： ./install.sh [选项]

  （无参数）      交互菜单：一键装 / 自己挑 / 看进度
  --yes, -y       一键装最小集合，不询问
  --only id,..    只装指定条目（逗号分隔，--list 看 id）
  --list          列出全部条目及状态
  --status        查看完成进度
  --dry-run       试运行：只显示会做什么，不真正安装
  --help, -h      显示本帮助
EOF
  exit 0
}

show_list() {
  local gid i df dn
  printf '  %s  %-18s %s  %s %s\n' "$(wpad 分组 10)" 条目 "$(wpad 名称 26)" 默认 状态
  for gid in "${GROUP_IDS[@]}"; do
    while IFS= read -r i; do
      df="-"; dn="○"
      [ "${IT_DEF[$i]}" = "1" ] && df="●"
      is_done "${IT_ID[$i]}" && dn="✔"
      printf '  %s  %-18s %s  %s %s\n' \
        "$(wpad "$(group_name "$gid")" 10)" "${IT_ID[$i]}" \
        "$(wpad "${IT_NAME[$i]}" 26)" "$df" "$dn"
    done < <(group_items "$gid")
  done
  echo "（●=默认勾选  ○=默认不勾  ✔=已完成）"
}

# ---- 执行流：逐件跑，按分组顺序 ----
run_flow() {
  local sel="$1" gid i id act title st
  local ok=0 fail=0 skip=0 n=0
  local t0=$SECONDS
  local -a RS_ID=() RS_ST=()

  # 真实安装前先把 sudo 密码问好（后台步骤不再交互）
  if [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then
    if ! sudo -v; then
      echo "获取 sudo 权限失败，中止。"
      return 1
    fi
    echo "sudo 已解锁（长任务若超过 5 分钟可能需要再输一次密码）"
    echo
  fi

  echo "开始执行 …"
  for gid in "${GROUP_IDS[@]}"; do
    while IFS= read -r i; do
      id="${IT_ID[$i]}"
      sel_has "$sel" "$id" || continue
      n=$((n + 1))
      title="${IT_NAME[$i]}"
      act="${IT_ACT[$i]}"

      if [ "$DRY" = 0 ] && is_done "$id"; then
        skip=$((skip + 1))
        RS_ID+=("$id"); RS_ST+=("skip")
        printf '  %-42s 已完成·跳过\n' "$title"
        continue
      fi

      st=0
      case "$act" in
        gitcfg) ui_step_interactive "$title" action_gitcfg || st=$? ;;
        *)      ui_step "$title" run_action "$id" || st=$? ;;
      esac

      if [ "$st" = 0 ]; then
        ok=$((ok + 1)); RS_ID+=("$id"); RS_ST+=("ok")
        [ "$DRY" = 1 ] || mark_done "$id"
      else
        fail=$((fail + 1)); RS_ID+=("$id"); RS_ST+=("fail")
      fi
    done < <(group_items "$gid")
  done

  # zshrc 受管块：选择集里有 zshrc 条目就按选择统一重写（试运行时只提示不写）
  ui_step "更新 ~/.zshrc 受管块" finalize_zshrc "$sel" || true

  # 结果表
  local dur=$((SECONDS - t0)) mark name j
  echo
  if [ "$fail" = 0 ]; then
    echo "✔ 执行完成 · 共 $ok 件成功 · $skip 件跳过 · 用时 $((dur / 60)) 分 $((dur % 60)) 秒"
  else
    echo "⚠ 执行结束 · 成功 $ok · 失败 $fail · 跳过 $skip · 用时 $((dur / 60)) 分 $((dur % 60)) 秒"
  fi
  echo
  if [ "${#RS_ID[@]}" -gt 0 ]; then
    for j in "${!RS_ID[@]}"; do
      i=$(item_index "${RS_ID[$j]}") || continue
      case "${RS_ST[$j]}" in
        ok)   mark="✔" ;;
        skip) mark="•" ;;
        *)    mark="✘" ;;
      esac
      printf '  %s %s\n' "$mark" "${IT_NAME[$i]}"
    done
    echo
  fi
  if [ "$DRY" = 1 ]; then
    echo "（以上为试运行，未真正安装）"
  else
    echo "下一步：exec zsh 生效；日志见 $LOG_FILE"
    echo "再次运行 ./install.sh，已完成的会自动跳过。"
  fi
}

# ---- 非交互命令 ----
case "$ACTION" in
  help)   show_help ;;
  list)   show_list; exit 0 ;;
  status) ui_status; exit 0 ;;
  only)
    [ -n "$ONLY" ] || { echo "--only 需要指定条目 id（逗号分隔）"; exit 1; }
    SEL=""
    IFS=',' read -ra only_ids <<< "$ONLY"
    for id in "${only_ids[@]}"; do
      item_index "$id" >/dev/null || { echo "未知条目: $id（--list 查看全部）"; exit 1; }
      SEL+="$id "
    done
    ui_init
    run_flow "$SEL"
    exit 0 ;;
esac

if [ "$YES" = 1 ]; then
  SEL=$(sel_defaults)
  ui_init >/dev/null 2>&1 || true
  n=$(sel_count "$SEL")
  echo "一键装（最小集合）：$n 件"
  run_flow "$SEL"
  exit 0
fi

# ---- 交互主循环 ----
ui_init
echo
SEL_CUSTOM=$(sel_defaults)   # 自选屏的初始勾选（随选择记忆）

while true; do
  CH=$(ui_menu) || exit 0
  case "$CH" in
    1)
      SEL=$(sel_defaults)
      echo; ui_summary "$SEL"
      N=$(sel_count "$SEL")
      if ui_confirm "确认执行这 $N 件？"; then echo; run_flow "$SEL"; echo; fi
      ui_pause "继续"
      ;;
    2)
      if ! SEL=$(ui_select "$SEL_CUSTOM"); then continue; fi
      SEL_CUSTOM="$SEL"
      N=$(sel_count "$SEL")
      if [ "$N" = 0 ]; then ui_pause "没有选中任何条目"; continue; fi
      echo; ui_summary "$SEL"
      if ui_confirm "确认执行这 $N 件？"; then echo; run_flow "$SEL"; echo; fi
      ui_pause "继续"
      ;;
    3)
      ui_status
      ui_pause "继续"
      ;;
    4|*)
      exit 0 ;;
  esac
done
