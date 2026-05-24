#!/usr/bin/env bash
#
# audit-agents.sh -- Enhanced quality audit for agent .md files
#
# Rules:
#   L001  ERROR  frontmatter must exist (--- at line 1)
#   L002  ERROR  frontmatter must have name, description, color, emoji
#   L003  WARN   recommended section headers present (Identity, Core Mission, Critical Rules)
#   L004  WARN   file has meaningful body content (>= 100 words)
#   L005  ERROR  no broken relative links to other agent files
#   L006  WARN   color field is valid (named color or #hex)
#   L007  WARN   description is non-empty and not a placeholder
#   L008  WARN   file path matches name in frontmatter (slug form)
#
# Usage: ./scripts/audit-agents.sh [--json] [--strict] [--phase DIR]

set -euo pipefail

AGENT_DIRS=(
  academic design engineering finance game-development hr legal
  marketing paid-media product project-management sales spatial-computing
  specialized supply-chain support testing
)

# Parse args
json_output=false
strict_mode=false
phase_filter=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)   json_output=true; shift ;;
    --strict) strict_mode=true; shift ;;
    --phase)  phase_filter="$2"; shift 2 ;;
    *)        echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

err_count=0
warn_count=0

err() { err_count=$((err_count + 1)); echo "ERROR $2: L$1"; }
warn() { warn_count=$((warn_count + 1)); echo "WARN  $2: L$1"; }

# Collect files
file_list=()
if [[ -n "$phase_filter" ]] && [[ -d "$phase_filter" ]]; then
  while IFS= read -r f; do
    file_list+=("$f")
  done < <(find "$phase_filter" -name "*.md" -type f | sort)
else
  for dir in "${AGENT_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r f; do
      file_list+=("$f")
    done < <(find "$dir" -name "*.md" -type f | sort)
  done
fi

total=${#file_list[@]}
[[ $total -gt 0 ]] || { echo "No agent files found." >&2; exit 1; }

[[ "$json_output" == "true" ]] || echo "Auditing $total agent files..."

for file in "${file_list[@]}"; do

  first_line=$(head -1 "$file")
  [[ "$first_line" == "---" ]] || { err "L001" "$file"; continue; }

  fm=$(awk 'NR==1{next} /^---$/{exit} {print}' "$file")
  [[ -n "$fm" ]] || { err "L001" "$file: empty frontmatter"; continue; }

  for field in name description color emoji; do
    echo "$fm" | grep -qE "^${field}:" || err "L002" "$file: missing '$field'"
  done

  body=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$file")

  echo "$body" | grep -qiE "(Identity|身份|记忆|你的身份)" || warn "L003" "$file: missing Identity"
  echo "$body" | grep -qiE "(Core Mission|核心使命)"              || warn "L003" "$file: missing Core Mission"
  echo "$body" | grep -qiE "(Critical Rules|关键规则)"           || warn "L003" "$file: missing Critical Rules"

  words=$(echo "$body" | wc -w)
  [[ $words -ge 100 ]] || warn "L004" "$file: only $words words (min 100)"

  while IFS= read -r link; do
    [[ "$link" =~ ^https ]] && continue
    link_dir=$(dirname "$link")
    [[ "$link_dir" == "." ]] && target="${file%/*}/$link" || target="$link"
    [[ -f "$target" ]] || { err "L005" "$file: broken link $link"; break; }
  done < <(grep -oP '(?<=\]\()(?!https|\.\.)[^)]+\.md' "$file" 2>/dev/null || true)

  color=$(echo "$fm" | grep -E "^color:" | head -1 | cut -d: -f2- | tr -d ' "')
  [[ -n "$color" ]] || continue
  color=$(echo "$color" | tr -d \'\")
  if [[ ! "$color" =~ ^[a-z]+(-[a-z]+)*$ ]] && [[ ! "$color" =~ ^#[0-9a-fA-F]{3,8}$ ]]; then
    [[ "$color" =~ ^(red|blue|green|purple|orange|pink|yellow|gray|grey|brown|black|white|cyan|magenta|lime|navy|teal|olive|maroon|violet|indigo|gold|silver|aqua)$ ]] || \
      warn "L006" "$file: unusual color '$color'"
  fi

  desc=$(echo "$fm" | grep -E "^description:" | head -1 | cut -d: -f2- | tr -d ' ')
  if [[ -z "$desc" ]]; then
    warn "L007" "$file: empty description"
  elif [[ "$desc" == "一句话描述这个智能体干什么" ]]; then
    warn "L007" "$file: description is placeholder"
  fi

  fm_name=$(echo "$fm" | grep -E "^name:" | head -1 | cut -d: -f2- | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  [[ -n "$fm_name" ]] || continue
  expected="${fm_name}.md"
  actual=$(basename "$file")
  [[ "$actual" == "$expected" ]] || warn "L008" "$file: expected '$expected'"

done

echo ""
if [[ "$json_output" == "true" ]]; then
  printf '{"errors":%d,"warnings":%d,"files":%d}\n' "$err_count" "$warn_count" "$total"
else
  result_msg="Result: $err_count errors, $warn_count warnings ($total files)"
  echo "$result_msg"
  [[ $err_count -gt 0 ]] && { echo "FAILED -- fix errors above."; exit 1; }
  [[ "$strict_mode" == "true" && $warn_count -gt 0 ]] && { echo "FAILED -- strict mode."; exit 1; }
  echo "PASSED"
fi
