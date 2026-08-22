# Third-party attribution

This directory is a **vendored copy of a third-party Quarto extension**, committed into
the repo rather than installed at build time so that CI needs nothing but Quarto. It is
*not* covered by the repo-root `LICENSE` (Apache-2.0), which applies to OpenADMET's own
code in this repository.

Every file here was copied verbatim from the `_extensions/` tree of the sibling
`OpenADMET/Octant_CYP_blog_post` repo (which had installed it with Quarto's extension
manager); the copies are byte-identical to their source and nothing has been modified.

## What is here

| Path | What it is |
|---|---|
| `_extension.yml`, `academicons.lua` | the Quarto extension wrapper (one shortcode, `ai`) |
| `assets/css/all.css`, `assets/css/size.css` | Academicons' own stylesheets |
| `assets/webfonts/academicons.{eot,svg,ttf,woff}` | the Academicons icon font |

## Academicons — the icon font and CSS

Verbatim from the header comment of `assets/css/all.css`:

    Academicons 1.9.4 by James Walsh (https://github.com/jpswalsh) and Katja Bercic
    (https://github.com/katjabercic)
    Fonts generated using FontForge - https://fontforge.org
    Square icons designed to be used alongside Font Awesome square icons
    Licenses - Font: SIL OFL 1.1, CSS: MIT License

So the webfonts are licensed under the **SIL Open Font License 1.1** and the CSS under
the **MIT License**, by James Walsh and Katja Bercic. Upstream:
<https://jpswalsh.github.io/academicons/>. `academicons.lua` declares the same version,
1.9.4, when it registers the HTML dependency.

## The Quarto wrapper — `_extension.yml` and `academicons.lua`

`_extension.yml` records `author: David Schoch` and `version: 0.4.0`. The
`_extensions/schochastics/academicons/` layout is Quarto's
`_extensions/<owner>/<extension>/` convention, i.e. what
`quarto add schochastics/academicons` produces, which points at
<https://github.com/schochastics/academicons> as the upstream — though that URL is
inferred from the directory layout, not recorded in any file here.

**The wrapper's licence is not established from what is on disk.** No licence or notice
file came with the copied tree, and neither `_extension.yml` nor `academicons.lua`
states any terms. Before redistributing this repo beyond its current scope, check the
upstream repository and record its licence here rather than assuming one.

## How it is used

`index.qmd` invokes the shortcode twice — `{{< ai orcid color=#a6ce39 >}}`
for the two authors with known ORCIDs. Nothing else in the repo depends on this
extension.
