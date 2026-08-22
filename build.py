#!/usr/bin/env python3
"""Assemble the figure page from src/ and build/*.json.

Two outputs:
  --standalone  one self-contained HTML with every JSON inlined; opens from disk
  (default)     figures/embed/index.html plus sibling detail JSONs fetched on
                demand, which is what the blog post embeds
"""
import argparse, base64, json, pathlib, shutil

HERE = pathlib.Path(__file__).parent
ENZYMES = ["CYP1A2", "CYP2C9", "CYP2D6", "CYP3A4"]


def read(p):
    return (HERE / p).read_text(encoding="utf-8")


def assemble(index_json, detail_json_or_none, wasm_b64_or_none):
    html = read("src/index.template.html")
    payload = [
        ("/*__CSS__*/", read("src/styles.css")),
        ("/*__D3__*/", read("src/d3.v7.min.js")),
        ("/*__RDKIT__*/", read("src/RDKit_minimal.js")),
        # embed: null -> app.js locateFile()s the sibling .wasm copied below.
        # standalone: a base64 string -> app.js decodes it and passes the
        # bytes as wasmBinary, since there's no sibling file to fetch.
        ("/*__RDKIT_WASM_B64__*/", json.dumps(wasm_b64_or_none)),
        ("/*__APP__*/", read("src/app.js")),
        ("/*__INDEX__*/", index_json),
        ("/*__DETAIL__*/", detail_json_or_none or "null"),
    ]
    for token, text in payload:
        # </script> inside JSON would close the inline script tag early.
        html = html.replace(token, text.replace("</", "<\\/"))
    return html


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--standalone", action="store_true")
    ap.add_argument("--build", default="build")
    ap.add_argument("--out", default="figures")
    a = ap.parse_args()

    b = HERE / a.build
    index_json = (b / "figure_index.json").read_text(encoding="utf-8").strip()

    if a.standalone:
        detail = {e: json.loads((b / f"figure_detail_{e}.json").read_text()) for e in ENZYMES}
        wasm_b64 = base64.b64encode((HERE / "src/RDKit_minimal.wasm").read_bytes()).decode("ascii")
        html = assemble(index_json, json.dumps(detail, separators=(",", ":")), wasm_b64)
        out = HERE / a.out / "tdi_shift_facets.html"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(html, encoding="utf-8")
        print(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB)")
    else:
        d = HERE / a.out / "embed"
        d.mkdir(parents=True, exist_ok=True)
        (d / "index.html").write_text(assemble(index_json, None, None), encoding="utf-8")
        shutil.copy(HERE / "src/RDKit_minimal.wasm", d / "RDKit_minimal.wasm")
        for e in ENZYMES:
            shutil.copy(b / f"figure_detail_{e}.json", d / f"figure_detail_{e}.json")
        total = sum(f.stat().st_size for f in d.iterdir())
        print(f"wrote {d}/ ({total / 1e6:.1f} MB across {len(list(d.iterdir()))} files)")


if __name__ == "__main__":
    main()
