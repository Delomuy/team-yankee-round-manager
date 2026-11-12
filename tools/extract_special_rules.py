#!/usr/bin/env python3
"""
Extracts every special rule from the "World War III: Team Yankee - Complete Special Rules" PDF into
data/rules/special_rules.json, which the Godot project reads to show a rule's text when you click it.

Usage (needs:  pip install pdfplumber):
    python tools/extract_special_rules.py "World-War-III-Complete-Special-rules.pdf"
    python tools/extract_special_rules.py my.pdf -o data/rules/special_rules.json --report

How the PDF is read:
  * pages 2-5 = the general rules: weapon rules (2-3), equipment (4) and abilities (5).
    A heading is Lato-Bold 11pt, the italic lines are flavour text, the regular lines are the rule.
  * pages 6+ = one section per nation. A heading is Lato-Heavy 14pt; flavour text starts at the left edge of the
    column and the rule (in its box) is indented. The nation comes from the intro sentence of the section
    ("The British Army has a number of ...").
"""
import argparse
import difflib
import json
import os
import re
import sys
import unicodedata

try:
    import pdfplumber
except ImportError:
    sys.exit("This script needs pdfplumber:  pip install pdfplumber")

COL_SPLIT = 297.6      # half of the A4 page width in points
GENERAL_PAGES = {2: "Weapon", 3: "Weapon", 4: "Equipment", 5: "Ability"}

# intro sentence of a national section -> nation name used in the unit data
NATION_INTROS = [
    (r"US Army and Marine Corps", "American"), (r"American Militia", "American"),
    (r"The British Army", "British"), (r"Bundeswehr", "WestGerman"),
    (r"East German Volksarmee", "EastGerman"), (r"The Soviet Army", "Soviet"),
    (r"Czechoslovak Forces", "Czechoslovak"), (r"The Polish Forces", "Polish"), (r"The Cuban Forces", "Cuban"),
    (r"The Finnish Army", "Finnish"), (r"The Swedish Army", "Swedish"), (r"Norwegian Army", "Norwegian"),
    (r"The Danish Army", "Danish"), (r"The Canadian Army", "Canadian"), (r"The French Army", "French"),
    (r"Royal Netherlands Army", "Dutch"), (r"Australia and New Zealand", "ANZAC"), (r"The Belgian Army", "Belgian"),
    (r"Israel Defence Forces", "Israeli"), (r"The Iraqi Army", "Iraqi"), (r"Islamic Republic of Iran", "Iranian"),
]
# Book names are only filled in where the PDF itself states them (the American militia rules on page 6 say
# "Red Dawn"). Add entries here as {page: "Book"} if you want to label more pages.
BOOK_BY_PAGE = {}
ACRONYMS = {"AA", "MG", "HEAT", "ERA", "BDD", "HQ", "NLOS", "MLRS", "ROF", "HOT", "IR"}
SMALL_WORDS = {"or", "of", "and", "the"}


# --------------------------------------------------------------------------- lines

def page_lines(page):
    """Words -> visual lines [{col, x0, x1, top, bottom, text, font, size}] (two-column aware)."""
    words = page.extract_words(extra_attrs=["fontname", "size"], x_tolerance=1.5, y_tolerance=2)
    words = [w for w in words if w["x0"] > 40 and w["top"] < 800]        # drop the edge tab and the page number
    words.sort(key=lambda w: (0 if w["x0"] < COL_SPLIT else 1, w["top"], w["x0"]))
    lines = []
    for w in words:
        col = 0 if w["x0"] < COL_SPLIT else 1
        target = None
        for ln in reversed(lines):
            if ln["col"] != col:
                continue
            if abs(ln["top"] - w["top"]) < 3.5:
                target = ln
            break
        if target is None:
            target = {"col": col, "words": [], "top": w["top"]}
            lines.append(target)
        target["words"].append(w)
    out = []
    for ln in lines:
        ws = sorted(ln["words"], key=lambda w: w["x0"])
        fonts = {}
        for w in ws:
            f = w["fontname"].split("+")[-1]
            fonts[f] = fonts.get(f, 0) + len(w["text"])
        text = " ".join(w["text"] for w in ws)
        text = re.sub(r"\s+([,.;:!?)])", r"\1", text)
        text = re.sub(r"([(])\s+", r"\1", text)
        text = re.sub(r"(\d)\s+(st|nd|rd|th)\b", r"\1\2", text)       # superscript ordinals: "104 th" -> "104th"
        out.append({"col": ln["col"], "x0": ws[0]["x0"], "x1": max(w["x1"] for w in ws), "top": min(w["top"] for w in ws),
                    "bottom": max(w["bottom"] for w in ws), "text": text.strip(),
                    "font": max(fonts, key=fonts.get), "size": round(ws[0]["size"], 1)})
    return sorted(out, key=lambda l: (l["col"], l["top"]))


# --------------------------------------------------------------------------- text helpers

def title_case(heading):
    inner, paren = heading, ""
    m = re.match(r"^(.*?)\s*\((.*)\)$", heading)
    if m:
        inner, paren = m.group(1), m.group(2)

    def conv(h):
        out = []
        for i, w in enumerate(h.split(" ")):
            if w in ACRONYMS or re.fullmatch(r"[A-Z]+-?\d[A-Z0-9]*", w) or re.fullmatch(r"[#\d+]+", w):
                out.append(w)
            elif w.lower() in SMALL_WORDS and i > 0:
                out.append(w.lower())
            else:
                out.append("-".join(p.capitalize() for p in w.split("-")))
        return " ".join(out)

    s = conv(inner)
    if paren:
        s += " (" + conv(paren) + ")"
    return s


def make_key(name):
    s = re.sub(r"\(.*?\)", "", name)
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", s).strip().lower()


def join_lines(lines, vocab):
    """Joins wrapped lines of one paragraph, repairing line-end hyphenation."""
    text = ""
    for ln in lines:
        t = ln.strip()
        if not text:
            text = t
        elif text.endswith("-") and t and t[0].isalnum():
            last = text.split(" ")[-1]
            first = t.split(" ")[0]
            if (last + first).lower() in vocab or first[0].isupper() or first[0].isdigit():
                text += t                      # a real hyphen ("anti-tank", "RPG-7VR")
            else:
                text = text[:-1] + t           # typographic hyphenation ("unpro-tected")
        else:
            text += " " + t
    return text


def paragraphs(lines, vocab):
    """Groups lines into paragraphs by vertical gap; bullet lines stay on their own line."""
    paras, cur, prev = [], [], None
    for ln in lines:
        new_para = prev is not None and (ln["top"] - prev["top"] > 13.5)
        bullet = ln["text"].startswith("•")
        if cur and (new_para or bullet):
            paras.append(join_lines([l["text"] for l in cur], vocab))
            cur = []
        cur.append(ln)
        prev = ln
    if cur:
        paras.append(join_lines([l["text"] for l in cur], vocab))
    return paras


# --------------------------------------------------------------------------- main extraction

def extract(pdf_path):
    pdf = pdfplumber.open(pdf_path)
    pages = {}
    for i, page in enumerate(pdf.pages, start=1):
        if i == 1:
            continue                                                   # cover
        pages[i] = page_lines(page)
    vocab = set()
    for lines in pages.values():
        for ln in lines:
            vocab.update(w.lower() for w in re.findall(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)+", ln["text"]))

    rules = []
    for pno, lines in pages.items():
        general = pno in GENERAL_PAGES
        head_font, head_size = ("Lato-Bold", 11.0) if general else ("Lato-Heavy", 14.0)
        intros = []                                                    # (top, nation, text)
        for ln in lines:
            for pat, nation in NATION_INTROS:
                if re.search(pat, ln["text"]) and ln["font"].startswith("AGaramond") and not ln["font"].endswith("Italic"):
                    intros.append((ln["top"], nation, ln["text"]))
                    break

        def nation_at(top, intros=intros):
            best = None
            for itop, nation, _ in sorted(intros):
                if itop <= top + 15:
                    best = nation
            return best

        def is_intro(ln, intros=intros):
            return any(ln["top"] == t and ln["text"] == tx for t, _, tx in intros)

        for col in (0, 1):
            cl = [l for l in lines if l["col"] == col]
            i = 0
            while i < len(cl):
                ln = cl[i]
                if not (ln["font"].startswith(head_font) and abs(ln["size"] - head_size) < 0.6):
                    i += 1
                    continue
                heading = ln["text"]
                hx, htop = ln["x0"], ln["top"]
                body, prev, j = [], ln, i + 1
                while j < len(cl):
                    nxt = cl[j]
                    if nxt["font"].startswith(head_font) and abs(nxt["size"] - head_size) < 0.6:
                        if nxt["top"] - prev["bottom"] < 6 and not body:   # heading wrapped onto two lines
                            heading += " " + nxt["text"]
                            prev = nxt
                            j += 1
                            continue
                        break
                    if is_intro(nxt) or nxt["font"].startswith(("Istok", "Myriad")):
                        break
                    if nxt["top"] - prev["top"] > 40:
                        break
                    body.append(nxt)
                    prev = nxt
                    j += 1
                if general:
                    flavor = [l for l in body if l["font"].endswith("Italic")]
                    rule = [l for l in body if not l["font"].endswith("Italic")]
                else:
                    flavor = [l for l in body if l["x0"] < hx + 4]
                    rule = [l for l in body if l["x0"] >= hx + 4]
                    if not rule:                                       # no box: all of it is rule text
                        flavor, rule = [], flavor
                name = title_case(heading)
                entry = {
                    "name": name, "key": make_key(name),
                    "scope": "general" if general else "nation",
                    "category": GENERAL_PAGES.get(pno, "Nation"),
                    "nation": "" if general else (nation_at(htop) or ""),
                    "book": "", "page": pno,
                    "flavor": " ".join(paragraphs(flavor, vocab)),
                    "text": "\n".join(paragraphs(rule, vocab)),
                }
                if not general:
                    entry["book"] = BOOK_BY_PAGE.get(pno, "")
                    if pno == 6 and htop > 540:
                        entry["book"] = "Red Dawn"                      # the American militia rules
                rules.append(entry)
                i = j
    rules.sort(key=lambda r: (r["page"], r["nation"], r["name"]))
    return merge_repeats(rules)


def merge_repeats(rules):
    """The PDF prints some national rules twice (the Soviet Army section appears on two pages). Entries of the same
    nation and name whose text is (nearly) identical are merged; "pages" lists every page they appear on."""
    letters = lambda t: re.sub(r"[^a-z0-9]", "", t.lower())
    merged = []
    for r in rules:
        r["pages"] = [r["page"]]
        for m in merged:
            if (m["nation"], m["key"], m["scope"]) == (r["nation"], r["key"], r["scope"]) and \
                    difflib.SequenceMatcher(None, letters(m["text"]), letters(r["text"])).ratio() >= 0.95:
                m["pages"].append(r["page"])
                break
        else:
            merged.append(r)
    return merged


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pdf")
    ap.add_argument("-o", "--output", default="data/rules/special_rules.json")
    ap.add_argument("--report", action="store_true", help="print every extracted rule")
    args = ap.parse_args()

    rules = extract(args.pdf)
    problems = []
    for r in rules:
        if not r["text"]:
            problems.append(f"p{r['page']} {r['nation'] or 'general'}: '{r['name']}' has no rule text")
        if r["scope"] == "nation" and not r["nation"]:
            problems.append(f"p{r['page']}: '{r['name']}' has no nation")
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump({"source": "World War III: Team Yankee - Complete Special Rules (PDF)", "rules": rules}, f,
                  indent=1, ensure_ascii=False)
        f.write("\n")
    general = sum(1 for r in rules if r["scope"] == "general")
    print(f"{len(rules)} rules ({general} general, {len(rules) - general} national) -> {args.output}")
    if args.report:
        for r in rules:
            print(f"  p{r['page']:<2} {r['nation'] or '(general ' + r['category'] + ')':<22} {r['name']}")
    for p in problems:
        print("WARNING:", p, file=sys.stderr)


if __name__ == "__main__":
    main()
