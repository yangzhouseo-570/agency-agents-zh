#!/usr/bin/env python3
"""
build_catalog.py — Generate catalog.json and CATALOG.md from agent .md files.

Schema (catalog.json):
{
  "version": "1",
  "generated_at": "<ISO timestamp>",
  "total_agents": int,
  "categories": [
    {
      "name": "<category dir name>",
      "label": "<human label>",
      "count": int,
      "agents": [
        {
          "file": "<relative path>",
          "name": "<frontmatter name>",
          "description": "<frontmatter description>",
          "color": "<frontmatter color>"
        }
      ]
    }
  ]
}

Usage:
  python3 scripts/build_catalog.py               # writes catalog.json + CATALOG.md
  python3 scripts/build_catalog.py --stdout      # print to stdout, no file write
  python3 scripts/build_catalog.py --json path/  # write catalog.json only
  python3 scripts/build_catalog.py --md path/    # write CATALOG.md only
  python3 scripts/build_catalog.py --dry-run    # preview only
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

AGENT_DIRS = [
    "academic",
    "design",
    "engineering",
    "finance",
    "game-development",
    "hr",
    "legal",
    "marketing",
    "paid-media",
    "product",
    "project-management",
    "sales",
    "spatial-computing",
    "specialized",
    "supply-chain",
    "support",
    "testing",
]

CATEGORY_LABELS = {
    "academic": "学术部",
    "design": "设计部",
    "engineering": "工程部",
    "finance": "财务部",
    "game-development": "游戏开发部",
    "hr": "人力资源部",
    "legal": "法务部",
    "marketing": "市场部",
    "paid-media": "付费媒体部",
    "product": "产品部",
    "project-management": "项目管理部",
    "sales": "销售部",
    "spatial-computing": "空间计算部",
    "specialized": "专业部",
    "supply-chain": "供应链部",
    "support": "支持部",
    "testing": "测试部",
}

REPO_ROOT = Path(__file__).resolve().parent.parent


def extract_frontmatter(path: Path) -> dict:
    """Parse frontmatter from a markdown agent file."""
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return {}

    fm = {}
    # Match frontmatter block between first --- and second ---
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return fm

    for line in m.group(1).splitlines():
        if ":" in line:
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip()

    return fm


def scan_agents() -> list:
    """Walk agent directories and return structured catalog data."""
    categories = []
    total = 0

    for dirname in AGENT_DIRS:
        dir_path = REPO_ROOT / dirname
        if not dir_path.is_dir():
            continue

        agents = []
        for md_file in sorted(dir_path.glob("*.md")):
            fm = extract_frontmatter(md_file)
            agents.append({
                "file": f"{dirname}/{md_file.name}",
                "name": fm.get("name", md_file.stem.replace("-", " ")),
                "description": fm.get("description", ""),
                "color": fm.get("color", ""),
            })

        if agents:
            total += len(agents)
            categories.append({
                "name": dirname,
                "label": CATEGORY_LABELS.get(dirname, dirname),
                "count": len(agents),
                "agents": agents,
            })

    return {
        "version": "1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_agents": total,
        "categories": categories,
    }


def generate_markdown(catalog: dict) -> str:
    """Generate CATALOG.md from catalog data."""
    lines = [
        "# 智能体速查表\n",
        "> Ctrl+F / Cmd+F 搜索中文名，找到对应文件路径，直接告诉 AI 工具加载。",
        "> 用法示例：`请使用 engineering/engineering-software-architect.md 这个角色来评审我的架构`",
        "",
        "---",
        "",
    ]

    for cat in catalog["categories"]:
        count = cat["count"]
        label = cat["label"]
        emoji_map = {
            "学术部": "📖", "设计部": "🎨", "工程部": "🛠️", "财务部": "💰",
            "游戏开发部": "🎮", "人力资源部": "👥", "法务部": "⚖️", "市场部": "📣",
            "付费媒体部": "📺", "产品部": "🏗️", "项目管理部": "📋", "销售部": "🤝",
            "空间计算部": "🗺️", "专业部": "🎯", "供应链部": "🚚", "支持部": "💬",
            "测试部": "🧪",
        }
        emoji = emoji_map.get(label, "📦")
        lines.append(f"## {emoji} {label} ({count})")
        lines.append("")
        lines.append("| 中文名 | 文件路径 |")
        lines.append("|--------|----------|")
        for agent in cat["agents"]:
            name = agent["name"]
            file = agent["file"]
            lines.append(f"| {name} | `{file}` |")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Build catalog for agency-agents-zh")
    parser.add_argument("--stdout", action="store_true", help="Print to stdout")
    parser.add_argument("--json", metavar="PATH", help="Write catalog.json to PATH")
    parser.add_argument("--md", metavar="PATH", help="Write CATALOG.md to PATH")
    parser.add_argument("--dry-run", action="store_true", help="Preview only")
    args = parser.parse_args()

    catalog = scan_agents()

    json_out = json.dumps(catalog, ensure_ascii=False, indent=2)
    md_out = generate_markdown(catalog)

    if args.stdout:
        print(f"=== catalog.json ({len(json_out)} bytes) ===")
        print(json_out)
        print(f"\n=== CATALOG.md ({len(md_out)} bytes) ===")
        print(md_out)
        return

    if args.dry_run:
        print(f"[dry-run] Would write catalog.json ({len(json_out)} bytes)")
        print(f"[dry-run] Would write CATALOG.md ({len(md_out)} bytes)")
        print(f"[dry-run] Total agents: {catalog['total_agents']}")
        for cat in catalog["categories"]:
            print(f"  {cat['label']}: {cat['count']} agents")
        return

    # Default: write both files relative to repo root
    json_path = REPO_ROOT / "catalog.json"
    md_path = REPO_ROOT / "CATALOG.md"

    if args.json:
        json_path = Path(args.json) / "catalog.json"
    if args.md:
        md_path = Path(args.md) / "CATALOG.md"

    # Write catalog.json
    json_path.write_text(json_out, encoding="utf-8")
    print(f"Wrote {json_path}")

    # Write CATALOG.md
    md_path.write_text(md_out, encoding="utf-8")
    print(f"Wrote {md_path}")

    print(f"\nTotal: {catalog['total_agents']} agents across {len(catalog['categories'])} categories")


if __name__ == "__main__":
    main()