#!/usr/bin/env python3
"""Derive the post body in index.qmd from the Google Docs export.

The prose in ``scratch/CYP Inhibition Blog Post.md`` is the authors' published
writing and has to survive verbatim.  So it is never retyped: this script reads
the export and applies exactly the mechanical transformations that the export
itself made necessary, as explicit string operations.

  1. HEADINGS   bold-only pseudo-heading lines become real ``##``/``###``
                headings, so the table of contents works.  Matched by line
                number *and* exact text, so the bolded image on source line 76
                cannot be mistaken for a heading.
  2. SUBSCRIPTS four subscripted symbols the export flattened into running
                text are restored as HTML ``<sub>`` spans.
  3. ESCAPES    the export's backslash escapes are removed.
  4. TRAILING   trailing whitespace is dropped.  It is layout noise from the
     WHITESPACE export, not prose, and two consecutive list items that keep it
                turn into markdown hard breaks and render a stray ``<br>``.

Nothing else is touched.  No rewording, no reflowing, no reordering, no
spelling or punctuation "fixes" -- every other byte of every line is copied
through unchanged, curly apostrophes, em dashes, ``ΔpIC50``, ``μM``, ``≈`` and
the authors' own double spaces after sentences included.

Everything above the body (YAML front matter, the ``.doc-authors`` block) is
left alone.

Each transformation carries an expected occurrence count, asserted after the
run.  A shifted or reworded export therefore fails loudly instead of quietly
emitting, say, a heading-less document.

The script refuses to overwrite a body that has been edited since it was
generated unless ``--force`` is given, because from Task 4 onward the .qmd
grows figure blocks, citations and sections that do not come from the export.

Usage:
    python3 scripts/build_post_body.py            # generate the .qmd body
    python3 scripts/build_post_body.py --check     # verify only, write nothing
    python3 scripts/build_post_body.py --force     # overwrite an edited body
"""

from __future__ import annotations

import difflib
import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scratch" / "CYP Inhibition Blog Post.md"
QMD = ROOT / "index.qmd"
# The export lives in gitignored scratch/, so it can never be committed and a
# future contributor cannot re-check the prose against it.  Recording its
# checksum at least makes drift *detectable*.  Same format and tooling as
# data/MANIFEST.sha256, so `sha256sum -c` works on it directly.
SOURCE_SHA = ROOT / "post" / "PROSE-SOURCE.sha256"

# Source lines to take, 1-indexed and inclusive: "Introduction" heading through
# the last paragraph of the Conclusion.  Lines 1-5 are the title/author/DOI
# block that the YAML front matter and the .doc-authors block now carry;
# References (100-106) and Acknowledgements (108-113) are added by later tasks
# as Quarto-native sections; 116-126 are base64 image definitions.
BODY_FIRST_LINE = 6
BODY_LAST_LINE = 98

# --- 1. Headings ------------------------------------------------------------
# (source line number, exact source text) -> replacement line.  Keyed on both
# so a drifting source can never silently rewrite the wrong line.  Note that
# source line 76, "**![][image6]**", is a *bolded image*, not a heading, and is
# deliberately absent: it stays prose here and becomes a figure block later.
HEADINGS = {
    (6, "**Introduction**"): "## Introduction",
    (10, "**Background**"): "## Background",
    (20, "**Assay Design**"): "## Assay Design",
    (56, "**Discussion**"): "## Discussion",
    (58, "**Assay Effect Sizes**"): "### Assay Effect Sizes",
    (68, "**Tiering strategy**"): "### Tiering strategy",
    (80, "**Calling TDI**"): "### Calling TDI",
    # The orphaned "3." is a numbering artefact of the export -- the other
    # sections carry no numbers -- so the heading text is just "Conclusion".
    (94, "**3\\. Conclusion**"): "## Conclusion",
}

# --- 2. Flattened subscripts ------------------------------------------------
# (flattened form, restored form, expected occurrences in the body).  Ordered
# longest-first so the two-part symbols are matched before the short ones that
# share a prefix; the counts are consuming, i.e. they are what each pattern
# matches once the patterns above it have already been substituted.
SUBSCRIPTS = [
    ("pIC50CI\\_lower,TDI\\_condition", "pIC50<sub>CI lower, TDI condition</sub>", 1),
    ("pIC50CI\\_upper,direct\\_condition", "pIC50<sub>CI upper, direct condition</sub>", 1),
    ("ΔpIC50CI\\_lower", "ΔpIC50<sub>CI lower</sub>", 1),
    ("pIC50TDI\\_condition", "pIC50<sub>TDI condition</sub>", 2),
]

# --- 3. Backslash escapes ---------------------------------------------------
# The export escaped these wherever they appeared, e.g. "\~72%", "\<$1/well",
# "\> log10(2)", "Figure 1\.".  Pandoc renders them correctly either way, but
# they make the source unreadable and unmaintainable.
ESCAPED_CHARS = "<>[]~.()-"
# The body's 40 escapes are: 32 of the above, 7 "\_" consumed by the subscript
# patterns, and 1 "\." consumed by the Conclusion heading.  The transformed body
# therefore contains no backslash at all, which is a stronger and simpler
# invariant than the specific set scripts/check_post.sh forbids -- and it also
# catches an escape type the export has not used before.
RESIDUE = re.compile(r"\\.", re.DOTALL)


def require(condition, message):
    """Precondition that cannot be switched off by `python -O`."""
    if not condition:
        raise SystemExit(f"build_post_body.py: {message}")


def read_bytes(path, hint=""):
    try:
        return path.read_bytes()
    except FileNotFoundError:
        raise SystemExit(f"build_post_body.py: {path} not found.{hint}")


def transform(lines):
    """Apply the four transformations to the body lines.

    ``lines`` is the raw source slice.  Every transformation is counted and
    checked against its expected number of occurrences, so a shifted or edited
    export fails here rather than producing a plausible-looking wrong document.
    """
    out = []
    headings = 0
    subs = {flat: 0 for flat, _, _ in SUBSCRIPTS}

    for offset, line in enumerate(lines):
        lineno = BODY_FIRST_LINE + offset

        heading = HEADINGS.get((lineno, line))
        if heading is not None:
            out.append(heading)
            headings += 1
            continue

        for flat, restored, _ in SUBSCRIPTS:
            found = line.count(flat)
            if found:
                subs[flat] += found
                line = line.replace(flat, restored)

        for char in ESCAPED_CHARS:
            line = line.replace("\\" + char, char)

        out.append(line.rstrip())

    require(
        headings == len(HEADINGS),
        f"applied {headings} of {len(HEADINGS)} headings -- the export's line "
        f"numbering or heading text has changed, so the body would have been "
        f"written without its section headings. Update HEADINGS.",
    )
    for flat, _, expected in SUBSCRIPTS:
        require(
            subs[flat] == expected,
            f"subscript {flat!r} matched {subs[flat]} time(s), expected "
            f"{expected} -- the export's notation has changed. Update SUBSCRIPTS.",
        )

    leftover = RESIDUE.search("\n".join(out))
    require(
        leftover is None,
        f"backslash escape {leftover.group(0)!r} survived the transformation. "
        f"The export has introduced an escape this script does not handle; add "
        f"its character to ESCAPED_CHARS after checking it really is an export "
        f"artefact and not something the authors wrote." if leftover else "",
    )
    return out


def body_lines(source_text):
    lines = source_text.split("\n")
    require(
        len(lines) >= BODY_LAST_LINE,
        f"{SOURCE.name} has only {len(lines)} lines, fewer than the expected "
        f"body range {BODY_FIRST_LINE}-{BODY_LAST_LINE}; the export changed.",
    )
    return lines[BODY_FIRST_LINE - 1 : BODY_LAST_LINE]


def split_qmd(text):
    """Return everything in the .qmd up to and including the author block."""
    lines = text.split("\n")
    try:
        start = lines.index(":::{.doc-authors}")
        end = lines.index(":::", start + 1)
    except ValueError:
        raise SystemExit(
            "build_post_body.py: could not find the .doc-authors block in "
            f"{QMD.name}; refusing to guess where the body starts."
        )
    return "\n".join(lines[: end + 1])


def recorded_digest():
    if not SOURCE_SHA.exists():
        return None
    first = SOURCE_SHA.read_text(encoding="utf-8").split()
    return first[0] if first else None


def diff_summary(current, result, limit=10):
    diff = list(
        difflib.unified_diff(
            current.split("\n"), result.split("\n"),
            fromfile="index.qmd (on disk)",
            tofile="index.qmd (regenerated)",
            n=0, lineterm="",
        )
    )
    changed = sum(1 for d in diff if d[:1] in "+-" and d[:3] not in ("+++", "---"))
    head = "\n".join("    " + d for d in diff[:limit])
    more = f"\n    ... and {len(diff) - limit} more diff line(s)" if len(diff) > limit else ""
    return changed, head + more


def main(argv):
    args = argv[1:]
    known = {"--check", "--force"}
    unknown = [a for a in args if a not in known]
    require(not unknown, f"unknown argument(s): {' '.join(unknown)}. See --help in the docstring.")
    check_only = "--check" in args
    force = "--force" in args

    raw = read_bytes(
        SOURCE,
        " The Google Docs export is kept in scratch/, which is gitignored on"
        " purpose; stage the export there before running this script."
        f" Its expected SHA-256 is recorded in {SOURCE_SHA.relative_to(ROOT)}.",
    )
    digest = hashlib.sha256(raw).hexdigest()
    expected = recorded_digest()

    current = read_bytes(QMD).decode("utf-8")
    header = split_qmd(current)
    body = transform(body_lines(raw.decode("utf-8")))
    result = header + "\n\n" + "\n".join(body).rstrip("\n") + "\n"

    if check_only:
        failed = False
        if expected is None:
            print(f"WARN no recorded checksum at {SOURCE_SHA.relative_to(ROOT)}")
            failed = True
        elif digest == expected:
            print(f"ok   export matches the checksum recorded in {SOURCE_SHA.relative_to(ROOT)}")
        else:
            print(
                f"FAIL the export has drifted from the version this body was derived from.\n"
                f"       recorded {expected}\n"
                f"       on disk  {digest}\n"
                f"     The committed prose can no longer be assumed to match scratch/."
            )
            failed = True

        if current == result:
            print(f"ok   {QMD.name} body is exactly what the export generates")
        else:
            changed, head = diff_summary(current, result)
            # Expected from Task 4 onward: figures, citations and the closing
            # sections are authored in the .qmd, not derived from the export.
            # Not a failure -- only the checksum decides the exit status.
            print(
                f"note {QMD.name} has been edited since generation "
                f"({changed} line(s) differ). Expected once figures, citations "
                f"and closing sections were added.\n{head}"
            )
        return 1 if failed else 0

    if current == result:
        print(f"ok   {QMD.name} already matches the export; nothing to write")
    else:
        has_body = current[len(header):].strip() != ""
        if has_body and not force:
            changed, head = diff_summary(current, result)
            raise SystemExit(
                f"build_post_body.py: refusing to write.\n"
                f"  {QMD.name} has been edited since it was generated from the "
                f"export -- {changed} line(s) differ from what this script would "
                f"produce.\n"
                f"  Regenerating would DISCARD those edits (figure blocks, "
                f"citations, References/Acknowledgements sections and any other\n"
                f"  hand-authored content are not derived from the export and "
                f"cannot be reproduced by this script).\n"
                f"  Re-run with --force only if you genuinely want to throw them "
                f"away and revert the body to the raw export.\n{head}"
            )
        QMD.write_text(result, encoding="utf-8")
        verb = "overwrote (--force)" if has_body else "wrote"
        print(f"{verb} {QMD.name}: {len(body)} source lines, {len(' '.join(body).split())} tokens")

    if expected != digest:
        SOURCE_SHA.write_text(f"{digest}  {SOURCE.name}\n", encoding="utf-8")
        was = "updated" if expected else "recorded"
        print(f"{was} {SOURCE_SHA.relative_to(ROOT)}: {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
