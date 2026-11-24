#!/usr/bin/env python3
"""Validate repository-local Markdown links and heading fragments in changed docs."""

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
LINK_RE = re.compile(r"!?\\[[^\\]]*\\]\\(\\s*(<[^>]+>|[^\\s)]+)")
REFERENCE_RE = re.compile(r"^\\s{0,3}\\[[^\\]]+\\]:\\s*(<[^>]+>|\\S+)", re.MULTILINE)
HTML_HREF_RE = re.compile(r"""\\b(?:href|src)\\s*=\\s*["']([^"']+)["']""", re.IGNORECASE)
INLINE_CODE_RE = re.compile("(" + chr(96) + r"+)(.*?)\\1", re.DOTALL)
HEADING_RE = re.compile(r"^#{1,6}\\s+(.+?)\\s*#*\\s*$", re.MULTILINE)
HTML_ID_RE = re.compile(r"""\\b(?:id|name)\\s*=\\s*["']([^"']+)["']""", re.IGNORECASE)


def changed_markdown(base: str, head: str) -> list[Path]:
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{base}...{head}", "--", "*.md", "*.mdx"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return [ROOT / line for line in result.stdout.splitlines() if line.strip()]


def strip_code(text: str) -> str:
    lines = text.splitlines()
    kept: list[str] = []
    fence_char: str | None = None
    fence_size = 0
    for line in lines:
        match = re.match(r"^\\s{0,3}(" + chr(96) + r"{3,}|~{3,})", line)
        if match:
            token = match.group(1)
            if fence_char is None:
                fence_char, fence_size = token[0], len(token)
            elif token[0] == fence_char and len(token) >= fence_size:
                fence_char, fence_size = None, 0
            continue
        if fence_char is None:
            kept.append(line)
    return INLINE_CODE_RE.sub("", "\\n".join(kept))


def heading_anchors(text: str) -> set[str]:
    anchors: set[str] = set(HTML_ID_RE.findall(text))
    counts: dict[str, int] = {}
    for match in HEADING_RE.finditer(text):
        heading = re.sub(r"!?(?:\\[([^\\]]*)\\])\\([^)]*\\)", r"\\1", match.group(1))
        heading = re.sub(r"<[^>]+>", "", heading)
        heading = heading.replace(chr(96), "").replace("*", "").replace("_", "").replace("~", "")
        heading = html.unescape(heading).strip().lower()
        heading = unicodedata.normalize("NFKD", heading)
        heading = "".join(ch for ch in heading if not unicodedata.combining(ch))
        slug = re.sub(r"[^\\w -]", "", heading, flags=re.UNICODE)
        slug = re.sub(r"\\s", "-", slug.strip())
        slug = re.sub(r"-+", "-", slug)
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        anchors.add(slug if count == 0 else f"{slug}-{count}")
    return anchors


def extract_targets(text: str) -> list[str]:
    clean = strip_code(text)
    targets = [m.group(1) for m in LINK_RE.finditer(clean)]
    targets.extend(m.group(1) for m in REFERENCE_RE.finditer(clean))
    targets.extend(HTML_HREF_RE.findall(clean))
    return [target[1:-1] if target.startswith("<") and target.endswith(">") else target for target in targets]


def validate_file(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return [f"{path.relative_to(ROOT)}: cannot read Markdown file: {exc}"]

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
                errors.append(f"{path.relative_to(ROOT)}: broken local link '{target}' (target not found)")
                continue
        else:
            candidate = path

        fragment = unquote(parsed.fragment)
        if fragment and candidate.suffix.lower() in {".md", ".mdx"} and candidate.is_file():
            try:
                target_text = candidate.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                errors.append(f"{path.relative_to(ROOT)}: cannot read link target '{target}'")
                continue
            if fragment not in heading_anchors(target_text):
                errors.append(
                    f"{path.relative_to(ROOT)}: broken anchor '{fragment}' in local link '{target}'"
                )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref", required=True, help="Base commit/ref for the documentation diff")
    parser.add_argument("--head-ref", required=True, help="Head commit/ref for the documentation diff")
    args = parser.parse_args()

    try:
        files = changed_markdown(args.base_ref, args.head_ref)
    except subprocess.CalledProcessError as exc:
        print(exc.stderr or "Unable to calculate changed Markdown files.", file=sys.stderr)
        return 2

    if not files:
        print("No changed Markdown files; local-link validation is not applicable.")
        return 0

    errors: list[str] = []
    for path in files:
        if path.is_file():
            errors.extend(validate_file(path))

    if errors:
        print("\\n".join(errors), file=sys.stderr)
        print(f"Found {len(errors)} broken local Markdown link(s)/anchor(s).", file=sys.stderr)
        return 1

    print(f"Validated local links and heading anchors in {len(files)} changed Markdown file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
