#!/usr/bin/env bash
# ui_select 纯逻辑测试（plain 模式，不需要 TTY）
set -euo pipefail
cd "$(dirname "$0")"
. lib/core.sh
. lib/ui.sh
load_config
UI_TOOL=plain
init=$(sel_defaults)

pass=0 fail=0
check() { # $1=描述 $2=实际 $3=期望
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); echo "  ✔ $1 → $2 件"
  else
    fail=$((fail + 1)); echo "  ✘ $1 → 实际 $2，期望 $3"
  fi
}

echo "【1】直接回车 = 保持默认勾选"
sel=$(printf '\n' | ui_select "$init")
check "默认" "$(sel_count "$sel")" 26

echo "【2】all = 全选 30 件"
sel=$(printf 'all\n' | ui_select "$init")
check "全选" "$(sel_count "$sel")" 30

echo "【3】none = 全清"
sel=$(printf 'none\n' | ui_select "$init")
check "全清" "$(sel_count "$sel")" 0

echo "【4】none 31（全清后勾 Docker 全选行）→ 4 件"
sel=$(printf 'none 31\n' | ui_select "$init")
check "Docker 组全选" "$(sel_count "$sel")" 4

echo "【5】默认基础上 -3（取消基础软件全选行）→ 整组清空"
sel=$(printf -- '-3\n' | ui_select "$init")
check "基础软件组清空" "$(sel_count "$sel")" 14

echo "【6】q = 放弃（应返回非0）"
if printf 'q\n' | ui_select "$init" >/dev/null 2>&1; then
  fail=$((fail + 1)); echo "  ✘ q 未取消"
else
  pass=$((pass + 1)); echo "  ✔ q 取消成功"
fi

echo "【7】回车后按组统计抽查"
sel=$(printf '\n' | ui_select "$init")
in_base=$(sel_count "$sel")
echo "  （选中: $sel）"

echo
echo "结果：通过 $pass，失败 $fail"
[ "$fail" = 0 ]
