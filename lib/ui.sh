#!/usr/bin/env bash
# ============================================================
# ui.sh — 界面层：只负责显示和取输入，不知道任何安装细节
# 优先 gum；没有 gum 时尝试自动下载；都不行则纯 read 降级
# 对外接口：
#   ui_init / ui_menu / ui_select / ui_summary / ui_confirm
#   ui_input / ui_step / ui_step_interactive / ui_status / ui_pause
# ============================================================

UI_TOOL=plain
DRY=${DRY:-0}
FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

ui_try_install_gum() {
  local ver=2.0.2 arch url tmp
  case "$(uname -m)" in x86_64|amd64) arch=amd64;; aarch64|arm64) arch=arm64;; *) return 1;; esac
  url="https://github.com/charmbracelet/gum/releases/download/v$ver/gum_${ver}_linux_${arch}.tar.gz"
  tmp=$(mktemp -d) || return 1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp/gum.tgz" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp/gum.tgz" "$url" || return 1
  else
    return 1
  fi
  tar -xzf "$tmp/gum.tgz" -C "$tmp" || return 1
  mkdir -p "$HOME/.local/bin"
  find "$tmp" -type f -name gum -exec cp {} "$HOME/.local/bin/gum" \; || return 1
  chmod +x "$HOME/.local/bin/gum"
  rm -rf "$tmp"
}

ui_init() {
  export PATH="$HOME/.local/bin:$PATH"
  if command -v gum >/dev/null 2>&1; then UI_TOOL=gum; return 0; fi
  if [ "$(uname -s)" = "Linux" ]; then
    echo "未检测到 gum，尝试自动安装…"
    if ui_try_install_gum && command -v gum >/dev/null 2>&1; then
      UI_TOOL=gum; echo "gum 已就绪"; return 0
    fi
  fi
  UI_TOOL=plain
  echo "gum 不可用，进入简易模式（编号选择）。"
}

# ---- 主菜单：输出 1/2/3/4 ----
ui_menu() {
  local c
  if [ "$UI_TOOL" = gum ]; then
    c=$(gum choose --height 5 \
        --header "devos-init · 选择交互方式" \
        --cursor "> " \
        "1  一键装（最小集合）" \
        "2  自己挑" \
        "3  看进度" \
        "4  退出") || return 1
    echo "${c%% *}"
  else
    printf '\n  devos-init\n\n'
    printf '   1  一键装（最小集合）\n'
    printf '   2  自己挑\n'
    printf '   3  看进度\n'
    printf '   4  退出\n\n'
    read -r -p "  选择 [1-4]: " c
    case "$c" in 1|2|3|4) echo "$c";; *) return 1;; esac
  fi
}

# ---- 单屏平铺选配：$1=初始选择集 → 输出最终选择集（失败/取消=退出码1）----
ui_select() {
  local init="$1"
  local KEY=() LINE=() PRE=()
  local gid idx cnt all line desc name

  for gid in "${GROUP_IDS[@]}"; do
    name=$(group_name "$gid")
    cnt=0; all=1
    KEY+=("h:$gid"); LINE+=("── $name ──"); PRE+=(0)
    while IFS= read -r idx; do
      cnt=$((cnt+1))
      sel_has "$init" "${IT_ID[$idx]}" || all=0
    done < <(group_items "$gid")
    KEY+=("a:$gid"); LINE+=("   ⊕ 全选本组 ·$name"); PRE+=("$all")
    while IFS= read -r idx; do
      desc=${IT_DESC[$idx]//,/·}   # gum --selected 用逗号拼接，描述里不能有逗号
      [ -z "$desc" ] || desc="  $desc"
      line=$(printf '   %-24s%s' "${IT_NAME[$idx]}" "$desc")
      KEY+=("i:$idx"); LINE+=("$line")
      sel_has "$init" "${IT_ID[$idx]}" && PRE+=(1) || PRE+=(0)
    done < <(group_items "$gid")
  done

  # 预勾选行列表（gum --selected 是逗号分隔的完整行匹配）
  local csv="" k
  for k in "${!LINE[@]}"; do
    [ "${PRE[$k]}" = 1 ] || continue
    [ -n "$csv" ] && csv+=","
    csv+="${LINE[$k]}"
  done

  local out="" line_no key
  if [ "$UI_TOOL" = gum ]; then
    # 注意：不能加 --ordered，gum 会因此把选项按字母序重排、打乱分组结构
    # 注意：gum 2.0.2 实测 toggle 键是 x（底部 help 明写 "x toggle"），空格无效！
    # 勾选状态要一眼可辨：[x]/[ ] 符号 + 颜色三态
    #   已选 = 亮绿 [x]（按 x 整行由灰变绿）
    #   未选 = 暗灰 [ ]
    #   光标 = 亮青 >  压在状态符号前
    out=$(printf '%s\n' "${LINE[@]}" | gum choose --no-limit \
          --height 22 \
          --header "x 勾选 · 回车确认 · ESC 取消 · 共 $(n_items) 件" \
          --selected "$csv" \
          --cursor "> " \
          --selected-prefix "[x] " \
          --unselected-prefix "[ ] " \
          --cursor-prefix "[ ] " \
          --selected.foreground "42" \
          --item.foreground "244" \
          --cursor.foreground "81") || return 1
  else
    out=$(ui_select_plain "${LINE[@]}" "${PRE[@]}") || return 1
  fi

  # 反查：输出行 → key
  local -a out_keys=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    for k in "${!LINE[@]}"; do
      if [ "${LINE[$k]}" = "$line" ]; then out_keys+=("${KEY[$k]}"); break; fi
    done
  done <<< "$out"

  key_in_out() { # $1=key
    local x
    for x in ${out_keys[@]+"${out_keys[@]}"}; do [ "$x" = "$1" ] && return 0; done
    return 1
  }

  # 组规则：
  #   全选行勾上 且 初始非全选      → 整组全选
  #   全选行取消 且 初始全选        → 逐件结果若仍全选 → 整组清空，否则按逐件结果
  #   其余                          → 逐件勾选结果
  local sel="" n_g total pick
  for gid in "${GROUP_IDS[@]}"; do
    local init_all=1 n_init=0
    while IFS= read -r idx; do
      n_init=$((n_init+1))
      sel_has "$init" "${IT_ID[$idx]}" || init_all=0
    done < <(group_items "$gid")
    [ "$n_init" -gt 0 ] || init_all=0

    local picked=0 n_pick=0
    key_in_out "a:$gid" && picked=1
    while IFS= read -r idx; do
      key_in_out "i:$idx" && n_pick=$((n_pick+1))
    done < <(group_items "$gid")

    if [ "$picked" = 1 ] && [ "$init_all" = 0 ]; then
      pick=all
    elif [ "$picked" = 0 ] && [ "$init_all" = 1 ]; then
      if [ "$n_pick" = "$n_init" ]; then pick=none; else pick=indiv; fi
    else
      pick=indiv
    fi

    case "$pick" in
      all)
        while IFS= read -r idx; do
          sel_has "$sel" "${IT_ID[$idx]}" || sel+="${IT_ID[$idx]} "
        done < <(group_items "$gid") ;;
      none) : ;;
      indiv)
        while IFS= read -r idx; do
          key_in_out "i:$idx" && sel+="${IT_ID[$idx]} "
        done < <(group_items "$gid") ;;
    esac
  done

  printf '%s\n' "$sel"
}

# 纯 read 降级版选配（动态作用域直接读 ui_select 的 KEY/LINE/PRE）
# 输出：反选后的行列表（供 ui_select 统一解析）
ui_select_plain() {
  local n=${#LINE[@]} i c tok m
  local -a state=() idxmap=()
  for ((i = 0; i < n; i++)); do state[$i]=${PRE[$i]}; done
  # 清单/提示走 stderr（stdout 留给结果，调用方用 $() 捕获结果）
  printf '\n' >&2
  for ((i = 0; i < n; i++)); do
    case "${KEY[$i]}" in
      h:*) printf '%s\n' "${LINE[$i]}" >&2; continue ;;
    esac
    idxmap+=("$i")
    [ "${state[$i]}" = 1 ] && m="[x]" || m="[ ]"
    printf '%3d %s %s\n' "${#idxmap[@]}" "$m" "${LINE[$i]}" >&2
  done
  printf '\n输入编号（空格分隔）；-编号=取消；all=全选；none=全清；q=放弃\n' >&2
  printf '可组合，如 none 31、all -31；直接回车 = 保持当前：' >&2
  read -r c || return 1
  case "$c" in
    q|Q) return 1 ;;
    "") : ;;
    *)
      # 一条命令行可组合：如 "none 31"、"all -31"、"4 5 6"
      for tok in $c; do
        case "$tok" in
          all)
            for ((i = 0; i < n; i++)); do
              case "${KEY[$i]}" in h:*) ;; *) state[$i]=1 ;; esac
            done ;;
          none)
            for ((i = 0; i < n; i++)); do state[$i]=0; done ;;
          -[0-9]*)
            tok=${tok#-}
            case "$tok" in ''|*[!0-9]*) continue ;; esac
            [ "$tok" -ge 1 ] && [ "$tok" -le "${#idxmap[@]}" ] \
              && state[${idxmap[$((tok - 1))]}]=0 ;;
          [0-9]*)
            case "$tok" in ''|*[!0-9]*) continue ;; esac
            [ "$tok" -ge 1 ] && [ "$tok" -le "${#idxmap[@]}" ] \
              && state[${idxmap[$((tok - 1))]}]=1 ;;
          *) continue ;;
        esac
      done ;;
  esac
  for ((i = 0; i < n; i++)); do
    case "${KEY[$i]}" in h:*) ;; *) [ "${state[$i]}" = 1 ] && printf '%s\n' "${LINE[$i]}" ;; esac
  done
  return 0   # 注意：末尾循环里有"未勾选就不 printf"的短路，必须显式归 0
}

ui_summary() { # $1=选择集
  local sel="$1" gid idx c t total=0
  printf '\n执行清单：\n'
  for gid in "${GROUP_IDS[@]}"; do
    c=0; t=0
    while IFS= read -r idx; do
      t=$((t+1))
      sel_has "$sel" "${IT_ID[$idx]}" && c=$((c+1))
    done < <(group_items "$gid")
    total=$((total+c))
    printf '  %s %2d / %-2d 件\n' "$(wpad "$(group_name "$gid")" 12)" "$c" "$t"
  done
  printf '  %s\n' "──────────────"
  printf '  共 %d 件，预计 3~5 分钟\n\n' "$total"
}

ui_confirm() { # $1=描述
  if [ "$UI_TOOL" = gum ]; then
    gum confirm --default --affirmative "执行" --negative "返回" "$1"
  else
    local a
    read -r -p "$1 [Y/n] " a
    case "$a" in n|N|no|NO) return 1;; *) return 0;; esac
  fi
}

ui_input() { # $1=提示 $2=默认值 → 输出用户输入
  if [ "$UI_TOOL" = gum ]; then
    gum input --prompt "$1 > " --value "$2"
  else
    local v
    read -r -p "$1 [$2]: " v
    echo "${v:-$2}"
  fi
}

# 逐件执行：$1=标题，其余=命令/函数；转圈 + 计时，失败打印日志尾部
ui_step() {
  local title="$1"; shift
  if [ "$DRY" = 1 ]; then
    printf '▶ %s [试运行]\n' "$(wpad "$title" 40)"
    return 0
  fi
  if [ "$UI_TOOL" = gum ]; then
    "$@" </dev/null >>"$LOG_FILE" 2>&1 &
    local pid=$! i=0 st=0 t0=$SECONDS dur
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r\033[K▶ %s %s' "$(wpad "$title" 40)" "${FRAMES[$((i % 10))]}"
      i=$((i + 1))
      sleep 0.12
    done
    wait "$pid" || st=$?
    dur=$((SECONDS - t0))
    if [ "$st" = 0 ]; then
      printf '\r\033[K✔ %s （%ds）\n' "$(wpad "$title" 40)" "$dur"
    else
      printf '\r\033[K✘ %s （失败 %ds）\n' "$(wpad "$title" 40)" "$dur"
      printf '   ↳ %s\n' "$(tail -n 3 "$LOG_FILE" | tr '\n' ' ')"
    fi
    return "$st"
  else
    printf '▶ %s ... ' "$title"
    if "$@" </dev/null >>"$LOG_FILE" 2>&1; then
      printf '完成\n'; return 0
    else
      printf '失败（详见 %s）\n' "$LOG_FILE"; return 1
    fi
  fi
}

# 需要交互的步骤（如 gitcfg 要问话）：不转圈，直接执行
ui_step_interactive() { # $1=标题，其余=命令
  local title="$1"; shift
  if [ "$DRY" = 1 ]; then
    printf '▶ %s [试运行]\n' "$(wpad "$title" 40)"
    return 0
  fi
  printf '▶ %s\n' "$title"
  "$@"
}

ui_status() {
  local gid c t pct bar
  printf '\n进度：\n'
  for gid in "${GROUP_IDS[@]}"; do
    c=$(done_count "$gid"); t=0
    while IFS= read -r _; do t=$((t+1)); done < <(group_items "$gid")
    [ "$t" -gt 0 ] && pct=$((c * 100 / t)) || pct=0
    bar=$(printf '%*s' $((pct / 5)) '' | tr ' ' '#')
    printf '  %s %2d/%-2d %3d%%  %s\n' "$(wpad "$(group_name "$gid")" 12)" "$c" "$t" "$pct" "$bar"
  done
  printf '  日志：%s\n\n' "$LOG_FILE"
}

ui_pause() { [ "$UI_TOOL" = gum ] && gum style --padding "0 1" "$*" >/dev/null; read -r -p "回车继续… " _; }
