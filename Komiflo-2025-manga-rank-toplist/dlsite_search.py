#!/usr/bin/env python3
"""Search DLsite for manga covers via CDN proxy."""
import json
import os
import re
import sys
import time
import urllib.request
import urllib.parse

CDN = "https://c.map987.dpdns.org"
HTML_DIR = "/workspace/Komiflo-2025-manga-rank-toplist"


def extract_titles(html_dir):
    """Extract manga titles from Komiflo HTML pages."""
    titles = []
    for page in ["index.html", "page2.html", "page3.html"]:
        path = os.path.join(html_dir, page)
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            html = f.read()
        page_titles = re.findall(
            r'<p><a href="https://komiflo\.com/#!/comics/\d+">([^<]+)</a></p>', html
        )
        titles.extend(page_titles)

    # Strip episode suffixes and clean up
    cleaned = []
    for t in titles:
        t = re.sub(r"\s*(最終話|前編|後編|完結編|第\d+話|\d+)$", "", t).strip()
        cleaned.append(t)

    # Skip first entry (ranking header), return unique manga titles
    manga = cleaned[1:]
    # Deduplicate while preserving order
    seen = set()
    result = []
    for t in manga:
        if t not in seen:
            seen.add(t)
            result.append(t)
    return result


def _normalize(s):
    """Normalize title for comparison."""
    return s.replace("！", "!").replace("？", "?").replace("．", ".").replace("　", " ").strip()


def search_dlsite(keyword):
    """Search DLsite via CDN JSON API and return the best-matching workno."""
    encoded = urllib.parse.quote(keyword, safe="")
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    }

    nk = _normalize(keyword)
    best = None  # (workno, matched_name, section, score)

    for section in ["maniax", "book"]:
        url = f"{CDN}/https://www.dlsite.com/{section}/api/=/product.json?keyword={encoded}"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except Exception:
            continue

        if not data or not isinstance(data, list):
            continue

        for item in data[:10]:
            workno = item.get("workno") or item.get("product_id")
            if not workno:
                continue
            name = item.get("work_name", "")
            nn = _normalize(name)
            if nn == nk:
                print(f"  Matched: {name} ({section}, exact)", file=sys.stderr)
                return workno, name
            if nn.startswith(nk) and (best is None or best[3] != "startswith"):
                best = (workno, name, section, "startswith")
            elif nk in nn and best is None:
                best = (workno, name, section, "partial")

    if best:
        workno, name, section, score = best
        print(f"  Matched: {name} ({section}, {score})", file=sys.stderr)
        return workno, name

    return None, None


def get_cover(workno):
    """Get cover image URL for a work via AJAX API."""
    url = f"{CDN}/https://www.dlsite.com/maniax/product/info/ajax?product_id={workno}"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"  INFO FAILED: {e}", file=sys.stderr)
        return None

    if not data:
        return None

    if isinstance(data, dict):
        info = list(data.values())[0] if data else {}
    elif isinstance(data, list):
        info = data[0] if data else {}
    else:
        return None

    img = info.get("work_image") or info.get("image_main") or info.get("image_url") or ""
    if img and not img.startswith("http"):
        img = "https:" + img
    return img if img else None


TITLES = extract_titles(HTML_DIR)
print(f"Extracted {len(TITLES)} titles from HTML", file=sys.stderr)

results = []
for i, title in enumerate(TITLES):
    print(f"[{i+1}/{len(TITLES)}] Searching: {title}", file=sys.stderr)
    workno, matched_name = search_dlsite(title)
    if workno:
        print(f"  Found: {workno}", file=sys.stderr)
        cover = get_cover(workno)
        print(f"  Cover: {cover}", file=sys.stderr)
        results.append({"rank": i+1, "title": title, "matched_name": matched_name, "workno": workno, "cover": cover})
    else:
        print(f"  NOT FOUND", file=sys.stderr)
        results.append({"rank": i+1, "title": title, "matched_name": None, "workno": None, "cover": None})
    time.sleep(0.5)

print(json.dumps(results, ensure_ascii=False, indent=2))
