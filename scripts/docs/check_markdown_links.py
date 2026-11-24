#!/usr/bin/env python3
"""Check changed Markdown files for broken repository-local links and anchors."""

from __future__ import annotations

import argparse
import html
import re
import subprocess
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
BS = chr(92)
LINK_RE = re.compile("!?"+BS+"[([^"+BS+"]*)"+BS+"]"+BS+"("+BS+"s*(<[^>]+>|[^"+BS+"s)]+)")
REFERENCE_RE = re.compile("^"+BS+"s{0,3}"+BS+"[[^"+BS+"]+\u005d:"+BS+"s*(<[^>]+>|"+BS+"S+)", re.MULTILINE)
HTML_HREF_RE = re.compile(r"""\b(?:href|src)\s*=\s*["']([^"']+)["']""", re.IGNORECASE)
INLINE_CODE_RE = re.compile("(" + chr(96) + "+)(.*?)" + BS + "1", re.DOTALL)
HEADING_RE = re.compile("^#{1,6}"+BS+"s+(.+?)"+BS+"s*#*"+BS+"s*$", re.MULTILINE)
HTML_ID_RE = re.compile(r"""\b(?:id|name)\s*=\s*["']([^"']+)["']""", re.IGNORECASE)


def changed_markdown(base: str, head: str) -> list[Path]:
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{base}...{head}", "--", "*.md", "*.mdx"],
        cwd=ROOT, check=True, capture_output=True, text=True,
    )
    return [ROOT / name for name in result.stdout.splitlines() if name.strip()]


def strip_code(text: str) -> str:
    kept = []
    fence_char = None
    fence_size = 0
    for line in text.splitlines():
        match = re.match("^"+BS+"s{0,3}("+chr(96)+"{3,}|~{3,})", line)
        if match:
            token = match.group(1)
            if fence_char is None:
                fence_char, fence_size = token[0], len(token)
            elif token[0] == fence_char and len(token) >= fence_size:
                fence_char, fence_size = None, 0
            continue
        if fence_char is None:
            kept.append(line)
    return INLINE_CODE_RE.sub("", chr(10).join(kept))


def heading_anchors(text: str) -> set[str]:
    anchors = set(HTML_ID_RE.findall(text))
    counts = {}
    image_or_link = re.compile("!?"+BS+"[([^"+BS+"]*)"+BS+"]"+BS+"([^)]*)")
    for match in HEADING_RE.finditer(text):
        heading = image_or_link.sub(lambda item: item.group(1), match.group(1))
        heading = re.sub("<[^>]+>", "", heading)
        heading = heading.replace(chr(96), "").replace("*", "").replace("_", "").replace("~", "")
        heading = unicodedata.normalize("NFKD", html.unescape(heading).strip().lower())
        heading = "".join(ch for ch in heading if not unicodedata.combining(ch))
        slug = re.sub("[^\\w -]", "", heading)
        slug = re.sub(BS+"s", "-", slug.strip())
        slug = re.sub("-+", "-", slug)
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        anchors.add(slug if count == 0 else f"{slug}-{count}")
    return anchors


def extract_targets(text: str) -> list[str]:
    clean = strip_code(text)
    targets = [match.group(2) for match in LINK_RE.finditer(clean)]
    targets.extend(match.group(1) for match in REFERENCE_RE.finditer(clean))
    targets.extend(HTML_HREF_RE.findall(clean))
    return [value[1:-1] if value.startswith("<") and value.endswith(">") else value for value in targets]


def validate_file(path: Path) -> list[str]:
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return [f"{path.relative_to(ROOT)}: cannot read file: {exc}"]

    errors = []
    for target in extract_targets(source):
        target = html.unescape(target.strip())
        if not target or target == "#":
            continue
        parsed = urlsplit(target)
        if parsed.scheme or parsed.netloc or target.startswith("//"):
            continue
        raw_path = unquote(parsed.path)
        candidate = (ROOT / raw_path.lstrip("/")) if raw_path.startswith("/") else (path.parent / raw_path)
        candidate = candidate.resolve()
        if raw_path:
            if candidate.is_dir():
                options = [candidate / "README.md", candidate / "readme.md", candidate / "index.md"]
                candidate = next((item for item in options if item.is_file()), candidate)
            if not candidate.is_file():
                errors.append(f"{path.relative_to(ROOT)}: broken local link '{target}'")
                continue
        else:
            candidate = path
        fragment = unquote(parsed.fragment)
        if fragment and candidate.suffix.lower() in {".md", ".mdx"} and candidate.is_file():
            if fragment not in heading_anchors(candidate.read_text(encoding="utf-8")):
                errors.append(f"{path.relative_to(ROOT)}: broken anchor '{fragment}' in '{target}'")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref", required=True)
    parser.add_argument("--head-ref", required=True)
    args = parser.parse_args()
    try:
        files = changed_markdown(args.base_ref, args.head_ref)
    except subprocess.CalledProcessError as exc:
        print(exc.stderr or "Unable to calculate changed Markdown files.", file=sys.stderr)
        return 2
    if not files:
        print("No changed Markdown files; local-link validation is not applicable.")
        return 0
    errors = [error for path in files if path.is_file() for error in validate_file(path)]
    if errors:
        print(chr(10).join(errors), file=sys.stderr)
        print(f"Found {len(errors)} broken local link(s)/anchor(s).", file=sys.stderr)
        return 1
    print(f"Validated local links and heading anchors in {len(files)} changed Markdown file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
