#!/usr/bin/env bash
#
# audit-agents.sh — Enhanced quality audit for agent .md files
#
# Rules (L001–L008):
#   L001  ERROR  frontmatter must exist (--- at line 1)
#   L002  ERROR  frontmatter must have name, description, color
#   L003  WARN   recommended section headers present (Identity, Core Mission, Critical Rules)
#   L004  WARN   file has meaningful body content (>= 100 words)
#   L005  ERROR  no broken relative links to other agent files
#   L006  WARN   color field is valid (named color or #hex)
#   L007  WARN   description is non-empty and not a placeholder
#   L008  WARN   file path matches name in frontmatter (lowercase-with-dashes)
#
# Exit code: non-zero when any ERROR rule fails.
#
# Usage: ./scripts/audit-agents.sh [--json] [--strict] [--phase DIR]
#   --json    CI-friendly output
#   --strict  Exit 1 on any warning (not just error)
#   --phase   Audit single directory only (e.g. --phase engineering)

set -euo pipefail

AGENT_DIRS=(
  academic design engineering finance game-development hr legal
  marketing paid-media product project-management sales spatial-computing
  specialized supply-chain support testing
)

# Parse args
JSON_OUTPUT=false
STRICT=false
PHASE_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)    JSON_OUTPUT=true; shift ;;
    --strict)  STRICT=true; shift ;;
    --phase)   PHASE_FILTER="$2"; shift 2 ;;
    *)         echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

errors=0
warnings=0
declare -A results_json

# Log to stdout or capture
log() {
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    return
  fi
  echo "$@"
}

err() {
  errors=$((errors + 1))
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    results_json["E:$1"]+="  $2\n"
  else
    echo "ERROR $2: L$1"
  fi
}

warn() {
  warnings=$((warnings + 1))
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    results_json["W:$1"]+="  $2\n"
  else
    echo "WARN  $2: L$1"
  fi
}

# Collect files
files=()
if [[ -n "$PHASE_FILTER" ]]; then
  if [[ -d "$PHASE_FILTER" ]]; then
    while IFS= read -r f; do
      files+=("$f")
    done < <(find "$PHASE_FILTER" -name "*.md" -type f | sort)
  else
    echo "Directory not found: $PHASE_FILTER" >&2
    exit 1
  fi
else
  for dir in "${AGENT_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      while IFS= read -r f; do
        files+=("$f")
      done < <(find "$dir" -name "*.md" -type f | sort)
    fi
  done
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No agent files found." >&2
  exit 1
fi

log "Auditing ${#files[@]} agent files..."

for file in "${files[@]}"; do

  # L001: frontmatter at line 1
  first_line=$(head -1 "$file")
  if [[ "$first_line" != "---" ]]; then
    err "L001" "$file"
    continue
  fi

  # Extract frontmatter block
  frontmatter=$(awk 'NR==1{next} /^---$/{exit} {print}' "$file")
  if [[ -z "$frontmatter" ]]; then
    err "L001" "$file: empty or missing frontmatter"
    continue
  fi

  # L002: required fields
  for field in name description color; do
    if ! echo "$frontmatter" | grep -qE "^${field}:"; then
      err "L002" "$file: missing frontmatter field '$field'"
    fi
  done

  # Get body (after second ---)
  body=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$file")

  # L003: recommended sections
  has_identity=false; has_core=false; has_rules=false
  if echo "$body" | grep -qiE "(Identity|身份|记忆|你的身份)"; then has_identity=true; fi
  if echo "$body" | grep -qiE "(Core Mission|核心使命)"; then has_core=true; fi
  if echo "$body" | grep -qiE "(Critical Rules|关键规则)"; then has_rules=true; fi
  if ! $has_identity; then warn "L003" "$file: missing Identity section"; fi
  if ! $has_core;   then warn "L003" "$file: missing Core Mission section"; fi
  if ! $has_rules;  then warn "L003" "$file: missing Critical Rules section"; fi

  # L004: content length
  word_count=$(echo "$body" | wc -w)
  if [[ $word_count -lt 100 ]]; then
    warn "L004" "$file: body content too short ($word_count words, expected >= 100)"
  fi

  # L005: broken relative links
  while IFS= read -r link; do
    # link is like ./engineering/xxx.md or ../xxx.md
    link_dir=$(dirname "$link")
    if [[ "$link_dir" == "." ]]; then
      # same-dir link, resolve from file's dir
      target="${file%/*}/$link"
    else
      target="$link"
    fi
    if [[ ! -f "$target" ]]; then
      err "L005" "$file: broken link to $link"
    fi
  done < <(grep -oP '(?<=\]\()(?!\.\.|http)[^)]+\.md' "$file" 2>/dev/null || true)

  # L006: valid color
  color_val=$(echo "$frontmatter" | grep -E "^color:" | head -1 | cut -d: -f2- | tr -d ' "')
  if [[ -n "$color_val" ]]; then
    # Strip any remaining quotes
    color_val=$(echo "$color_val" | tr -d '"'"' )
    if ! [[ "$color_val" =~ ^[a-z]+(-[a-z]+)*$ ]] && ! [[ "$color_val" =~ ^#[0-9a-fA-F]{3,8}$ ]]; then
      if ! [[ "$color_val" =~ ^(red|blue|green|purple|orange|pink|yellow|gray|grey|brown|black|white|cyan|magenta|lime|navy|teal|olive|maroon|violet|indigo|gold|silver|aqua)$ ]]; then
        warn "L006" "$file: unusual color value '$color_val'"
      fi
    fi
  fi

  # L007: description not placeholder
  desc_val=$(echo "$frontmatter" | grep -E "^description:" | head -1 | cut -d: -f2- | tr -d ' ')
  if [[ -z "$desc_val" ]]; then
    warn "L007" "$file: description is empty"
  elif [[ "$desc_val" == "一句话描述这个智能体干什么" ]]; then
    warn "L007" "$file: description is still a placeholder"
  fi

  # L008: filename matches frontmatter name (slug form)
  fm_name_raw=$(echo "$frontmatter" | grep -E "^name:" | head -1 | cut -d: -f2-)
  fm_name=$(echo "$fm_name_raw" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  if [[ -n "$fm_name" ]]; then
    expected_filename="${fm_name}.md"
    actual_filename=$(basename "$file")
    if [[ "$actual_filename" != "$expected_filename" ]]; then
      warn "L008" "$file: filename '$actual_filename' != expected slug '$expected_filename'"
    fi
  fi

done

echo ""
if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "{\"errors\": $errors, \"warnings\": $warnings, \"files\": ${#files[@]}}"
else
  echo "Result: $errors errors, $warnings warnings (${#files[@]} files)"
  if [[ $errors -gt 0 ]]; then
    echo "FAILED — fix errors above."
    exit 1
  elif [[ $STRICT == "true" && $warnings -gt 0 ]]; then
    echo "FAILED — strict mode: warnings treated as errors."
    exit 1
  else
    echo "PASSED"
    exit 0
  fi
fi