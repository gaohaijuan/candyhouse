"""Lists every Chinese string the game can show: string literals in scripts
(comments skipped) and string values in data/*.json. With --missing, prints
only those absent from data/i18n/en.json (exit 1 if any)."""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CJK = re.compile(r'[一-鿿]')
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SKIP_DATA = set()
# Shown only in Chinese (the mainland health notice) or the same in every
# language (language names, the placeholder glyph of the language icon).
EXEMPT = ("健康游戏忠告", "简体中文", "A文")


def from_scripts():
    out = []
    for d, _, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in files:
            if not f.endswith(".gd"):
                continue
            path = os.path.join(d, f)
            for n, line in enumerate(open(path, encoding="utf-8"), 1):
                code = line.split("#", 1)[0] if not '"#' in line else line
                if line.lstrip().startswith("#") or "i18n: parts" in line:
                    continue
                for m in LIT.finditer(code):
                    s = m.group(1).encode().decode("unicode_escape").encode("latin1").decode("utf-8") if "\\" in m.group(1) else m.group(1)
                    if CJK.search(s) and not s.startswith(EXEMPT):
                        out.append((s, "%s:%d" % (os.path.relpath(path, ROOT), n)))
    return out


def walk(v, where, out):
    if isinstance(v, str):
        if CJK.search(v):
            out.append((v, where))
    elif isinstance(v, dict):
        for k, x in v.items():
            walk(x, where + "." + k, out)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            walk(x, where + "[%d]" % i, out)


def from_data():
    out = []
    data = os.path.join(ROOT, "data")
    for f in sorted(os.listdir(data)):
        if f.endswith(".json") and f not in SKIP_DATA:
            walk(json.load(open(os.path.join(data, f), encoding="utf-8")), f, out)
    return out


def main():
    found = from_scripts() + from_data()
    if "--missing" in sys.argv:
        table = json.load(open(os.path.join(ROOT, "data/i18n/en.json"), encoding="utf-8"))
        miss = [(s, w) for s, w in found if s not in table]
        for s, w in miss:
            print("%s\t%s" % (w, s))
        sys.exit(1 if miss else 0)
    seen = set()
    for s, w in found:
        if s not in seen:
            seen.add(s)
            print(json.dumps(s, ensure_ascii=False) + "\t" + w)


main()
