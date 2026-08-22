"use strict";
(function () {
  const INDEX = window.FIGURE_INDEX;
  const LOG2_2 = INDEX.meta.log2_2;
  const COL = { inactive:"#3089FB", active:"#228833", sig:"#CC3311", notsig:"#BBBBBB" };

  // Distinct marker per compound_class (a semantic TDI annotation, recoded
  // from the assay's operational class names at build time in
  // R/figure_data.R::tdi_label) so the ~370 annotated points are separable
  // from the unannotated library cloud without toggling anything off.
  // "Unknown" stays the circle since it is ~95% of points; the four
  // annotated classes get distinct non-circle shapes.
  const CLASS_SYMBOL = {
    "Unknown":               d3.symbolCircle,
    "TDI (control)":         d3.symbolTriangle,
    "Non-TDI (control)":     d3.symbolSquare,
    "TDI (literature)":      d3.symbolDiamond,
    "Non-TDI (literature)":  d3.symbolCross,
  };
  const CLASS_ORDER = ["Unknown", "TDI (control)", "Non-TDI (control)",
                        "TDI (literature)", "Non-TDI (literature)"];
  const symGen = d3.symbol().size(34).type(c => CLASS_SYMBOL[c.compound_class] || d3.symbolCircle);

  // jsonlite auto_unbox collapses a length-1 vector to a bare scalar; normalize
  // to an array either way (defensive — the real 4-enzyme/10-run build never
  // hits this, but a future single-enzyme/single-run subset could).
  const toArray = v => Array.isArray(v) ? v : [v];

  const ENZYMES = toArray(INDEX.meta.enzymes);            // ["CYP1A2","CYP2C9","CYP2D6","CYP3A4"]
  document.title = `${ENZYMES.join(" / ")} TDI-shift explorer`;
  d3.select("#controls h1").text(`${ENZYMES.join(" / ")} TDI-shift explorer`);

  const BY_ENZYME = d3.group(INDEX.compounds, d => d.enzyme);
  const ALL_CLASSES = new Set(INDEX.compounds.map(c => c.compound_class));

  const state = {
    classes: new Set(ALL_CLASSES),
    sigOnly: false,
    search: "",
    hovered: null,   // {enzyme, key}
    pinned: null,    // {enzyme, key}
    mode: "threshold",
    shiftThr: LOG2_2,   // delta pIC50 required to call a shift  (default log10(2) ~= 0.301)
    yThr: 4.3,          // minimum active pIC50 for a callable hit
  };

  // ---- TDI-call modes, simplest first. "threshold" is the default. ---------
  const gapOK = c => (c.active.lo > c.inactive.hi) || (c.inactive.lo > c.active.hi);
  const MODES = {
    // 1. Thresholds only: the shift clears the bar and the compound is potent
    //    enough. This is the only mode in which the potency threshold applies.
    threshold: c => c.shift.mean > state.shiftThr && c.active.pEC50 > state.yThr,
    // 2. The two conditions' 95% CIs must not overlap.
    gap:       c => c.shift.mean > state.shiftThr && gapOK(c),
    // 3. Fully Bayesian: the computed shift's own 95% CI must exclude zero.
    bayes:     c => c.shift.mean > state.shiftThr && c.shift.lo > 0,
    // Neither CI mode applies the potency threshold: an interval test already
    // demands the shift be resolved against its own uncertainty, so a weak
    // compound cannot pass it on noise. Requiring a potency floor on top would
    // discard well-resolved shifts for being low-potency, which is a different
    // question from whether the shift is real.
  };
  const isSig = c => MODES[state.mode](c);

  // Search haystack, not a display string. compound_id is already the full
  // dash-joined id (OCNT-XXXXXXX-YY-ZZZ); concatenating the common name lets
  // the existing filter match either without changing the filter itself, so
  // both "ketoconazole" and "OCNT-1911793" find the same points.
  const fullId = c => c.compound_name ? `${c.compound_name} ${c.compound_id}` : c.compound_id;
  const keyOf = c => `${c.run}:${c.pair_id}`;
  const enzymeOf = sel => sel && sel.enzyme;

  // key -> compound, across all enzymes. `run` is enzyme-prefixed (e.g.
  // "CYP1A2-1"), so this key is already globally unique — no per-enzyme map needed.
  const byKey = new Map(INDEX.compounds.map(c => [keyOf(c), c]));

  const activeCompounds = enzyme => (BY_ENZYME.get(enzyme) || []).filter(c =>
    state.classes.has(c.compound_class) &&
    (!state.sigOnly || isSig(c)) &&
    (!state.search || fullId(c).toLowerCase().includes(state.search.toLowerCase())));

  // Shared pIC50 domain for ALL FOUR panels' both axes, so y=x is a true
  // 45-degree line in every facet and screen position means the same pIC50
  // everywhere. Computed once over the pooled compounds — do not give each
  // panel its own scale.
  const allPe = INDEX.compounds.flatMap(c => [c.inactive.pEC50, c.active.pEC50]);
  const lim = [d3.min(allPe) - 0.2, d3.max(allPe) + 0.2];

  // DRC-viewer y-domain: precomputed in R (drc_y_bounds), since the lazy
  // per-enzyme detail files mean the old startup scan of every curve is no
  // longer possible at this point.
  state.drcYmin = INDEX.meta.drc_y[0];
  state.drcYmax = INDEX.meta.drc_y[1];

  // Axis furniture (PAD) is a fixed pixel cost, so growing W/H by 20% grows the
  // plotting area by rather more than 20% — which is the intent.
  const PAD = {t:10,r:10,b:40,l:46}, W=360, H=360;
  const xScale = d3.scaleLinear(lim, [PAD.l, W-PAD.r]);
  const yScale = d3.scaleLinear(lim, [H-PAD.b, PAD.t]);

  // Per-enzyme layers, populated by drawPanel().
  const svgs = {}, ptLayers = {}, blobLayers = {}, overlays = {}, modeRefs = {}, refGroups = {};

  function drawPanel(enzyme, i) {
    const svg = d3.select(`#panel-${enzyme}`).attr("width", W).attr("height", H);
    svgs[enzyme] = svg;
    const leftCol = i % 2 === 0;
    const bottomRow = i >= 2;

    // Scales are shared; only draw axes where they'd otherwise be redundant.
    if (bottomRow) {
      svg.append("g").attr("class","axis").attr("transform",`translate(0,${H-PAD.b})`).call(d3.axisBottom(xScale).ticks(5));
      svg.append("text").attr("x",(PAD.l+W-PAD.r)/2).attr("y",H-4).attr("text-anchor","middle").attr("fill","currentColor").attr("font-size",10).text("Direct inhibition pIC50");
    }
    if (leftCol) {
      svg.append("g").attr("class","axis").attr("transform",`translate(${PAD.l},0)`).call(d3.axisLeft(yScale).ticks(5));
      svg.append("text").attr("transform","rotate(-90)").attr("x",-(PAD.t+H-PAD.b)/2).attr("y",12).attr("text-anchor","middle").attr("fill","currentColor").attr("font-size",10).text("Time-dependent inhibition pIC50");
    }

    refGroups[enzyme] = svg.append("g");         // y=x and +shiftThr reference lines
    modeRefs[enzyme] = svg.append("g");          // threshold/gap-mode "active pIC50 = yThr" guide
    blobLayers[enzyme] = svg.append("g").attr("class","blob-layer");
    ptLayers[enzyme] = svg.append("g").attr("class","pt-layer");
    overlays[enzyme] = svg.append("g").attr("class","ci-cross").attr("pointer-events","none");

    drawRefLines(enzyme);
  }

  const num = d3.format(",");   // thousands separators for the per-facet tallies
  const fmt = d3.format(".2f");
  // For the two live-threshold labels (the y-guide and its echo in the detail
  // header): these mirror a number the reader just typed into a spinner, so
  // ".2f" would turn a typed "4.3" into a misleading "4.30". Drop the
  // trailing zero instead. Other call sites (measured pIC50s, CIs, slopes)
  // keep `fmt` and its fixed two decimals.
  const fmtThr = d3.format("~g");

  // The reference lines follow the live thresholds, so this is re-callable
  // (mode-select does so below) rather than drawn once at setup.
  function drawRefLines(enzyme) {
    const refs = refGroups[enzyme];
    refs.selectAll("*").remove();
    const b = state.shiftThr;
    const line = off => `M${xScale(lim[0])},${yScale(lim[0]+off)} L${xScale(lim[1]-off)},${yScale(lim[1])}`;
    refs.append("path").attr("class","refline").attr("d", line(0));
    refs.append("path").attr("class","refline").attr("d", line(b)).attr("stroke", COL.sig).attr("opacity",0.5);

    // No "y = x" / "+0.30" labels on the lines. They sat inside the densest
    // part of the scatter, so they were usually unreadable, and when legible
    // they restated what the lines already show — the lower line is parity and
    // the upper one is offset by the shift threshold, which the controls state
    // numerically and the detail header repeats per compound.

    // Guide at active pIC50 = yThr. Only threshold mode applies that cutoff,
    // so only threshold mode draws it — showing it under a CI mode would imply
    // a bar those modes do not enforce.
    const modeRef = modeRefs[enzyme];
    modeRef.selectAll("*").remove();
    if (state.mode === "threshold") {
      // Line only, no label: it sat at the left edge on top of the densest
      // band of points and was the least legible of the three. Its value is
      // the "active pIC50 >" control, a few centimetres away.
      modeRef.append("line").attr("x1",PAD.l).attr("x2",W-PAD.r).attr("y1",yScale(state.yThr)).attr("y2",yScale(state.yThr))
        .attr("class","refline").attr("stroke",COL.sig).attr("opacity",0.4);
    }
  }

  function renderPanel(enzyme) {
    const raw = activeCompounds(enzyme);
    // The annotated classes are ~370 of 6,897 points — draw them after
    // Unknown so they sit on top of the cloud instead of vanishing under it.
    // d3's keyed join inserts newly-entering nodes in data order, so this
    // ordering holds up across re-filtering (e.g. toggling a class off and
    // back on).
    const data = raw.filter(c => c.compound_class === "Unknown")
      .concat(raw.filter(c => c.compound_class !== "Unknown"));
    const svg = svgs[enzyme];
    svg.selectAll(".facet-empty").remove();
    if (data.length === 0) {
      svg.append("text").attr("class","facet-empty")
        .attr("x", W/2).attr("y", H/2).attr("text-anchor","middle")
        .text("no compounds match filters");
    }
    // Per-facet call tally, upper-left of the plotting area — the one corner
    // the diagonal cloud reliably leaves empty. Counted off `data`, i.e. the
    // points actually drawn after class toggles, search and "significant
    // only", so it always agrees with the red/grey the reader can see, and it
    // re-renders with everything else on any threshold or mode change.
    svg.selectAll(".facet-stat").remove();
    if (data.length) {
      const nSig = data.reduce((a, c) => a + (isSig(c) ? 1 : 0), 0);
      const pct = 100 * nSig / data.length;
      const stat = (dy, t, bold) => svg.append("text").attr("class", "facet-stat")
        .attr("x", PAD.l + 6).attr("y", PAD.t + dy).attr("font-size", 10)
        .attr("fill", "currentColor").attr("opacity", bold ? 0.85 : 0.6)
        .text(t);
      stat(12, `${num(nSig)} / ${num(data.length)} called TDI`, true);
      stat(24, `${pct.toFixed(1)}%`, false);
    }

    const ptLayer = ptLayers[enzyme];
    const sel = ptLayer.selectAll("path.pt").data(data, keyOf);
    sel.exit().remove();
    sel.enter().append("path").attr("class","pt")
      .on("mouseover", (e,c)=>onHover(enzyme,c)).on("click",(e,c)=>onPin(enzyme,c))
      .merge(sel)
      .attr("transform", c=>`translate(${xScale(c.inactive.pEC50)},${yScale(c.active.pEC50)})`)
      .attr("d", symGen)
      .attr("fill", c=>isSig(c)?COL.sig:COL.notsig)
      .attr("fill-opacity", c=>isSig(c)?0.75:0.4)
      .attr("stroke", c=>isSig(c)?COL.sig:"none").attr("stroke-opacity",0.5);
    if (state.pinned && state.pinned.enzyme===enzyme && !data.some(c=>keyOf(c)===state.pinned.key)) clearSelection();
    return data.length;
  }

  function renderAll() {
    let total = 0;
    // Reference lines are derived from the live thresholds/mode, so they are
    // redrawn alongside the points on every render — a threshold control
    // that recolours the scatter but leaves the guide line behind would tell
    // the reader the wrong story about what the threshold means.
    ENZYMES.forEach(e => { drawRefLines(e); total += renderPanel(e); });
    d3.select("#count").text(`${total} compounds`);
  }

  // ---- Chemical structure (RDKit-JS/WASM, vendored in src/RDKit_minimal.{js,wasm}) ---
  // Replaces SmilesDrawer, which mislaid heteroatom labels off their bond
  // vertices and mangled some ring systems (a 1,2,4-oxadiazole rendered as
  // floating N/O with stray bond stubs) — a coordinate-space bug in that
  // library's SVG path, not a font-metric or target-element issue. RDKit's
  // own SVG renderer was verified independently (rendered offline, inspected
  // the PNG) to place every label correctly.
  //
  // get_svg_with_highlights() (the details-JSON variant) is used instead of
  // the argument-only get_svg() so a minFontSize floor can be set — verified
  // in this build (mol object exposes the method; the option measurably
  // changes output on real dataset SMILES at this canvas size, confirmed by
  // diffing rendered SVGs against get_svg()'s defaults) — because the panel
  // is small enough that RDKit's natural label size gets cramped otherwise.
  //
  // #structure is a <div> (not an <svg>): mol.get_svg_with_highlights()
  // returns a complete, self-contained `<svg>...</svg>` string, set via
  // innerHTML. It draws on a transparent background with black bonds —
  // invisible against the dark theme's body colour — so #structure gets a
  // fixed light panel behind it in both themes (styles.css), rather than
  // following var(--bg).
  //
  // RDKit's WASM module is ~6.9MB raw (~2.1MB gzipped) and must not be part
  // of the initial page load, so it's fetched only on the first structure
  // render; the module promise is cached in rdkitPromise and reused for
  // every render after that (this IIFE's whole-page lifetime).
  const structureEl = document.getElementById("structure");
  const STRUCTURE_W = 280, STRUCTURE_H = 180; // matches #structure's CSS box
  const STRUCTURE_MIN_FONT = 9; // px floor for atom labels at this canvas size

  let rdkitPromise = null;
  function loadRDKit() {
    if (!rdkitPromise) {
      const opts = { locateFile: () => "RDKit_minimal.wasm" }; // embed build: sibling file
      if (window.RDKIT_WASM_B64) {
        // Standalone build: no sibling .wasm file exists (everything else is
        // inlined into the one HTML file), so the module is base64-embedded
        // and decoded straight to bytes instead of being fetched by path.
        const bin = atob(window.RDKIT_WASM_B64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        opts.wasmBinary = bytes;
      }
      rdkitPromise = initRDKitModule(opts).catch(e => { rdkitPromise = null; throw e; });
    }
    return rdkitPromise;
  }

  const clearStructure = () => { structureEl.innerHTML = ""; };

  // Drawn straight from c.smiles (the index), never from the detail fetch —
  // the whole point of shipping SMILES in the index is that the structure
  // appears the instant a point is hovered, not after a round trip (RDKit
  // load time aside). Cleared unconditionally up front: a missing or
  // unparseable SMILES must leave the panel empty, never the previous
  // compound's structure still showing, which would silently mislabel it.
  // A short "loading…" placeholder fills the gap before RDKit is ready the
  // very first time; once cached, the promise resolves on the same tick and
  // the placeholder is never visibly painted.
  function renderStructure(c) {
    clearStructure();
    if (!c || !c.smiles) return;
    const key = keyOf(c), smiles = c.smiles;
    structureEl.textContent = "loading…";
    loadRDKit().then(RDKit => {
      const cur = state.pinned || state.hovered;
      if (!cur || cur.key !== key) return;   // hover moved on; discard
      clearStructure();
      let mol = null;
      try {
        mol = RDKit.get_mol(smiles);         // null/throws on unparseable SMILES
        if (mol) structureEl.innerHTML = mol.get_svg_with_highlights(JSON.stringify({
          width: STRUCTURE_W, height: STRUCTURE_H, minFontSize: STRUCTURE_MIN_FONT
        }));
      } catch (e) {
        clearStructure();
      } finally {
        // Required even when get_svg_with_highlights throws — hovering
        // across a dense scatter calls this hundreds of times, and leaking
        // every molecule would exhaust the WASM heap.
        if (mol) mol.delete();
      }
    }).catch(() => { clearStructure(); });    // RDKit itself failed to load
  }

  function clearSelection(){
    state.pinned=null; state.hovered=null;
    document.getElementById("detail-body").hidden=true;
    document.getElementById("detail-empty").hidden=false;
    ENZYMES.forEach(e => { blobLayers[e].selectAll("*").remove(); overlays[e].selectAll("*").remove(); });
    clearStructure();
  }

  function onHover(enzyme, c){
    if (state.pinned) return;
    const key = keyOf(c);
    state.hovered = {enzyme, key};
    renderSelection(enzyme, key);
  }
  function onPin(enzyme, c){
    const key = keyOf(c);
    if (state.pinned && state.pinned.enzyme===enzyme && state.pinned.key===key) { clearSelection(); }
    else { state.pinned = {enzyme, key}; state.hovered = {enzyme, key}; renderSelection(enzyme, key); }
  }

  // ---- Lazy per-enzyme detail loading ---------------------------------------
  const detailCache = new Map();          // enzyme -> {key: detail}
  const detailPending = new Map();
  function loadDetail(enzyme) {
    if (detailCache.has(enzyme)) return Promise.resolve(detailCache.get(enzyme));
    if (detailPending.has(enzyme)) return detailPending.get(enzyme);
    const p = (window.FIGURE_DETAIL && window.FIGURE_DETAIL[enzyme])
      ? Promise.resolve(window.FIGURE_DETAIL[enzyme])          // standalone build
      : fetch(`figure_detail_${enzyme}.json`).then(r => r.json());
    const q = p.then(d => { detailCache.set(enzyme, d); detailPending.delete(enzyme); return d; });
    detailPending.set(enzyme, q);
    return q;
  }

  // Reconstruct a density grid from its {lo, hi, n} summary.
  const gridOf = g => d3.range(g.n).map(i => g.lo + (g.hi - g.lo) * i / (g.n - 1));

  // Header + scatter overlay draw immediately from the index; the blob, DRC
  // panel and shift plot draw once detail resolves. Guarded
  // against a stale response: if the hover has moved on by the time the
  // fetch lands, the result is dropped rather than overwriting the panel.
  function renderSelection(enzyme, key) {
    const c = byKey.get(key);
    renderHeader(c);                      // index data, available now
    renderStructure(c);                   // index data, available now
    renderBlob(c);                        // scatter overlay; index data only (unless bayes mode)
    loadDetail(enzyme).then(det => {
      const cur = state.pinned || state.hovered;
      if (!cur || cur.key !== key) return;   // hover moved on; discard
      const d = det[key];
      if (!d) return;
      renderMarginal(c, d); renderCurvePlot(c, d); renderShiftPlot(c, d);
      // The Bayesian 2-D HDR polygon lives only in the detail; the
      // simple/threshold/gap CI-cross already drew synchronously above.
      if (state.mode === "bayes") renderBlob(c, d);
    });
  }

  // What was actually applied to call this compound, in the current mode —
  // reads the live thresholds rather than just naming the mode, since the
  // whole point of making them adjustable is that the same mode can call a
  // different set of compounds depending on where they're set. The potency
  // threshold doesn't apply in bayes mode, so it's omitted there.
  function modeAnnotation(){
    const s = fmt(state.shiftThr);
    // Mirrors the threshold controls, so it uses their wording.
    if (state.mode === "bayes") return `method 3: pIC50 shift > ${s}, 95% CI excludes 0`;
    if (state.mode === "gap")   return `method 2: pIC50 shift > ${s}, CIs disjoint`;
    return `method 1: pIC50 shift > ${s}, TDI pIC50 > ${fmtThr(state.yThr)}`;
  }

  // compound_name comes from a vendor catalogue rather than our own registry,
  // so it is escaped before going into .html(). Identifiers are escaped too,
  // for one rule rather than two.
  const esc = s => String(s).replace(/[&<>"]/g, ch =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));

  function renderHeader(c){
    document.getElementById("detail-empty").hidden = true;
    document.getElementById("detail-body").hidden = false;
    // Slopes are fitted and stored as log2(Hill slope) (SlopeLog2); report the
    // Hill slope itself, which is the unit people read. Exponentiating the
    // quantiles is exact because 2^x is monotone; exponentiating the mean
    // gives the geometric mean, the right central estimate for a parameter
    // estimated on a log scale.
    const hill = v => Math.pow(2, v);
    const sl = s => `slope ${fmt(hill(s.slope.mean))} [${fmt(hill(s.slope.lo))}, ${fmt(hill(s.slope.hi))}]`;
    const sig = isSig(c);
    // Identity and provenance sit beside the structure; the measured values
    // sit between the DRC plot they were fitted from and the plot that shows
    // how the call was made, so each number is next to the picture of it.
    d3.select("#detail-head").html(
      `<b>${esc(c.compound_id)}</b>${c.compound_name ? " · " + esc(c.compound_name) : ""}<br>`+
      `<span class="prov">${["Expt: " + esc(c.run), esc(c.plate)].concat(c.compound_deck ? [esc(c.compound_deck)] : []).join(" · ")}</span>`);
    d3.select("#detail-stats").html(
      `<span style="color:${COL.inactive}">●</span> direct pIC50 ${fmt(c.inactive.pEC50)} [${fmt(c.inactive.lo)}, ${fmt(c.inactive.hi)}] · ${sl(c.inactive)}<br>`+
      `<span style="color:${COL.active}">●</span> TDI pIC50 ${fmt(c.active.pEC50)} [${fmt(c.active.lo)}, ${fmt(c.active.hi)}] · ${sl(c.active)}<br>`+
      `shift ${fmt(c.shift.mean)} [${fmt(c.shift.lo)}, ${fmt(c.shift.hi)}] `+
      `<span class="badge ${sig?'y':'n'}">${sig?'TDI':'not TDI'}</span><br>`+
      // Own line, not appended to the shift: the annotation is long enough that
      // together they overflowed the panel by 69px and wrapped mid-phrase.
      `<span style="opacity:.6">(${modeAnnotation()})</span>`);
  }

  function renderBlob(c, d){
    const enzyme = c.enzyme;
    ENZYMES.forEach(e => { blobLayers[e].selectAll("*").remove(); overlays[e].selectAll("*").remove(); });
    const col = isSig(c)?COL.sig:COL.notsig;
    if (state.mode !== "bayes") {
      // No computed 2-D HDR region for threshold/gap modes — draw the two
      // marginal 95% CIs as capped error bars in both directions (x =
      // inactive CI, y = active CI), centred on the point, purely from index
      // fields. Drawn on the top overlay with a background-colored halo
      // behind each segment so the cross stays visible over the dense scatter.
      const overlay = overlays[enzyme];
      const px=xScale(c.inactive.pEC50), py=yScale(c.active.pEC50);
      const xlo=xScale(c.inactive.lo), xhi=xScale(c.inactive.hi);
      const yTop=yScale(c.active.hi), yBot=yScale(c.active.lo);
      const cap=5;
      const seg=(x1,y1,x2,y2)=>{
        overlay.append("line").attr("x1",x1).attr("y1",y1).attr("x2",x2).attr("y2",y2)
          .style("stroke","var(--bg)").attr("stroke-width",5).attr("stroke-linecap","round").attr("stroke-opacity",0.85);
        overlay.append("line").attr("x1",x1).attr("y1",y1).attr("x2",x2).attr("y2",y2)
          .attr("stroke",col).attr("stroke-width",2.5).attr("stroke-linecap","round");
      };
      seg(xlo,py,xhi,py); seg(xlo,py-cap,xlo,py+cap); seg(xhi,py-cap,xhi,py+cap);        // inactive CI + end caps
      seg(px,yBot,px,yTop); seg(px-cap,yTop,px+cap,yTop); seg(px-cap,yBot,px+cap,yBot);  // active CI + end caps
      overlay.append("circle").attr("cx",px).attr("cy",py).attr("r",4)
        .attr("fill",col).style("stroke","var(--bg)").attr("stroke-width",2);
      return;
    }
    // Bayesian mode: the 2-D HDR polygon lives in the detail, not the index —
    // nothing to draw until it resolves.
    if (!d) return;
    const blobLayer = blobLayers[enzyme];
    const ln = d3.line().x(p=>xScale(p[0])).y(p=>yScale(p[1])).curve(d3.curveLinearClosed);
    blobLayer.selectAll("path").data(d.blob).enter().append("path")
      .attr("d", poly=>ln(poly))
      .attr("fill", col).attr("fill-opacity", 0.15)
      .attr("stroke", col).attr("stroke-width",1.5).attr("stroke-opacity",0.9);
  }

  // DRC plot geometry, shared with the posterior strip drawn directly above it
  // so the two line up pixel for pixel. Kept in one place because the strip is
  // only meaningful if its x positions are the DRC's: a pIC50 of p is the
  // concentration 10^-p, so a posterior peak sits over the dashed pIC50 line
  // of the curve it came from.
  // l is wide enough to clear the tick labels AND the rotated y-axis title:
  // at 40 the title's descenders overlapped the numbers by ~4px.
  const DRC = {w:476, m:{t:10, r:10, b:34, l:78}};
  function drcXScale(d){
    const concsOf = cond => INDEX.concs[d.curve[cond].conc_key - 1];
    const allc = [...concsOf("inactive"), ...concsOf("active"),
                  d.curve.inactive.pEC50.line, ...d.curve.inactive.pEC50.band,
                  d.curve.active.pEC50.line, ...d.curve.active.pEC50.band].filter(v => v > 0);
    return d3.scaleLog(d3.extent(allc), [DRC.m.l, DRC.w - DRC.m.r]);
  }

  // pIC50 posteriors, drawn on the DRC's own concentration axis (hence no axis
  // of its own -- the DRC's serves both). Density is mirrored relative to a
  // pIC50 axis because higher potency is a lower concentration, i.e. further left.
  function renderMarginal(c, d){
    const h = 74, m = DRC.m, w = DRC.w;
    const svg = d3.select("#marginal").attr("width", w).attr("height", h);
    svg.selectAll("*").remove();
    const x = drcXScale(d), g = gridOf(d.dens);
    const maxd = d3.max([...d.dens.inactive, ...d.dens.active]);
    const bot = h - 6, y = d3.scaleLinear([0, maxd], [bot, 16]);
    svg.append("text").attr("x", m.l).attr("y", 10).attr("fill", "currentColor")
      .attr("font-size", 9).attr("opacity", 0.7).text("pIC50 posteriors");
    for (const [key, col] of [["inactive", COL.inactive], ["active", COL.active]]) {
      svg.append("path").attr("fill", col).attr("fill-opacity", 0.35).attr("stroke", col)
        .attr("d", d3.area().x((_, i) => x(Math.pow(10, -g[i]))).y0(bot).y1(v => y(v))
          .curve(d3.curveBasis)(d.dens[key]));
    }
  }

  function renderCurvePlot(c, d){
    const w=DRC.w,h=248,m=DRC.m;   // h sized so the rotated y label fits with slack
    const svg=d3.select("#curve-plot").attr("width",w).attr("height",h); svg.selectAll("*").remove();
    // conc_key is per condition, not per compound: the two preincubation
    // conditions can be fitted over different concentration ranges, so each
    // one looks up its own vector rather than sharing a single compound-level key.
    const concsOf = cond => INDEX.concs[d.curve[cond].conc_key - 1];
    const x=drcXScale(d);
    const y=d3.scaleLinear([state.drcYmin, state.drcYmax],[h-m.b,m.t]);  // user-adjustable bounds
    svg.append("clipPath").attr("id","curve-clip").append("rect")
      .attr("x",m.l).attr("y",m.t).attr("width",w-m.r-m.l).attr("height",h-m.b-m.t);
    svg.append("g").attr("class","axis").attr("transform",`translate(0,${h-m.b})`).call(d3.axisBottom(x).ticks(4,"~e"));
    svg.append("g").attr("class","axis").attr("transform",`translate(${m.l},0)`).call(d3.axisLeft(y).ticks(5));
    svg.append("text").attr("x",w/2).attr("y",h-4).attr("text-anchor","middle").attr("fill","currentColor").attr("font-size",10).text("Concentration (M)");
    // y-axis label. The subscript is a tspan with a dy nudge and a smaller
    // font rather than baseline-shift, which SVG renderers treat inconsistently;
    // it is the last tspan, so the dy does not need resetting afterwards.
    // Two lines rather than one, so the title can be read at 12px instead of
    // being shrunk to fit the plot height. Under rotate(-90) a tspan's y is its
    // distance from the left edge, so the first line takes the smaller y and
    // sits further from the axis -- tilt your head left and it reads in order.
    const ymid = -(m.t + h - m.b) / 2;
    const ylab = svg.append("text").attr("transform","rotate(-90)")
      .attr("text-anchor","middle").attr("fill","currentColor").attr("font-size",12);
    ylab.append("tspan").attr("x", ymid).attr("y", 14).text("Signal relative to");
    ylab.append("tspan").attr("x", ymid).attr("y", 30).text("positive control E");
    ylab.append("tspan").attr("dy", "3").attr("font-size", 9).text("max");
    const plot=svg.append("g").attr("clip-path","url(#curve-clip)");  // clip out-of-bounds curve parts
    for (const [key,col] of [["inactive",COL.inactive],["active",COL.active]]){
      const cc=d.curve[key];
      const concs = concsOf(key);
      // pIC50 CI band + dashed line
      plot.append("rect").attr("x",x(cc.pEC50.band[0])).attr("width",Math.max(1,x(cc.pEC50.band[1])-x(cc.pEC50.band[0])))
        .attr("y",m.t).attr("height",h-m.b-m.t).attr("fill",col).attr("opacity",0.12);
      plot.append("line").attr("x1",x(cc.pEC50.line)).attr("x2",x(cc.pEC50.line)).attr("y1",m.t).attr("y2",h-m.b)
        .attr("stroke",col).attr("stroke-dasharray","4 3");
      // fitted line — concs and cc.y are this condition's own, same length
      plot.append("path").attr("fill","none").attr("stroke",col).attr("stroke-width",1.8)
        .attr("d", d3.line().x((_,i)=>x(concs[i])).y(v=>y(v))(cc.y));
      // raw points carry their own concentration per point, independent of conc_key
      plot.append("g").selectAll("circle").data(cc.pts).enter().append("circle")
        .attr("cx",p=>x(p[0])).attr("cy",p=>y(p[1])).attr("r",2.2)
        .attr("fill","none").attr("stroke",col).attr("stroke-opacity",0.7);
    }
  }

  // Bottom detail panel — mode-aware "what determined the call".
  function renderShiftPlot(c, d){
    const w=DRC.w,h=150,m={t:10,r:10,b:34,l:40};
    const svg=d3.select("#shift-plot").attr("width",w).attr("height",h); svg.selectAll("*").remove();
    if (state.mode === "bayes") renderShiftBayes(c, d, svg, w, h, m);
    else renderShiftSimple(c, d, svg, w, h, m);
  }

  // Bayesian: the computed shift posterior + mean +/- 95% CI errorbar.
  function renderShiftBayes(c, d, svg, w, h, m){
    const g=gridOf(d.dens_shift), dv=d.dens_shift.dens;
    const ext=d3.extent([...g,0,state.shiftThr]), padx=(ext[1]-ext[0])*0.04;
    const x=d3.scaleLinear([ext[0]-padx, ext[1]+padx],[m.l,w-m.r]);
    const y=d3.scaleLinear([0,d3.max(dv)],[h-m.b-24,m.t]);
    svg.append("g").attr("class","axis").attr("transform",`translate(0,${h-m.b})`).call(d3.axisBottom(x).ticks(5));
    svg.append("text").attr("x",w/2).attr("y",h-4).attr("text-anchor","middle").attr("fill","currentColor").attr("font-size",10).text("pIC50 shift = TDI − direct");
    const col=isSig(c)?COL.sig:COL.notsig;
    svg.append("path").attr("fill",col).attr("fill-opacity",0.3).attr("stroke",col)
      .attr("d", d3.area().x((_,i)=>x(g[i])).y0(h-m.b-24).y1(v=>y(v)).curve(d3.curveBasis)(dv));
    for (const [xv,lab,anchor,dx] of [[0,"0","end",-3],[state.shiftThr,fmt(state.shiftThr),"start",3]]) {
      svg.append("line").attr("x1",x(xv)).attr("x2",x(xv)).attr("y1",m.t).attr("y2",h-m.b)
        .attr("stroke",COL.sig).attr("stroke-width",1.5).attr("stroke-dasharray","4 3").attr("opacity",0.9);
      svg.append("text").attr("x",x(xv)+dx).attr("y",m.t+8).attr("font-size",9).attr("fill",COL.sig).attr("text-anchor",anchor).text(lab);
    }
    const yb=h-m.b-10;
    svg.append("line").attr("x1",x(c.shift.lo)).attr("x2",x(c.shift.hi)).attr("y1",yb).attr("y2",yb).attr("stroke",col).attr("stroke-width",2);
    svg.append("circle").attr("cx",x(c.shift.mean)).attr("cy",yb).attr("r",3.5).attr("fill",col);
  }

  // Simple: the two pIC50 posteriors + their 95% CIs as bars below, so you can
  // see whether the intervals touch. Reference at active pIC50 = yThr.
  function renderShiftSimple(c, d, svg, w, h, m){
    const g=gridOf(d.dens);
    // yThr only widens the domain when it is actually drawn (threshold mode).
    const span=[...g, c.inactive.lo, c.active.hi];
    if (state.mode === "threshold") span.push(state.yThr);
    // Pad the domain a little. Without it the threshold, which is often the
    // extreme of the span, lands exactly on the axis and reads as clipped.
    const ext=d3.extent(span), padx=(ext[1]-ext[0])*0.04;
    const x=d3.scaleLinear([ext[0]-padx, ext[1]+padx],[m.l,w-m.r]);
    const dBot=h-m.b-30, dTop=m.t;
    const maxd=d3.max([...d.dens.inactive, ...d.dens.active]);
    const y=d3.scaleLinear([0,maxd],[dBot,dTop]);
    svg.append("g").attr("class","axis").attr("transform",`translate(0,${h-m.b})`).call(d3.axisBottom(x).ticks(5));
    svg.append("text").attr("x",w/2).attr("y",h-4).attr("text-anchor","middle").attr("fill","currentColor").attr("font-size",10).text("pIC50 — do the 95% CIs overlap?");
    // active pIC50 = yThr threshold — threshold mode only, matching the facets.
    if (state.mode === "threshold") {
      svg.append("line").attr("x1",x(state.yThr)).attr("x2",x(state.yThr)).attr("y1",m.t).attr("y2",h-m.b)
        .attr("stroke",COL.sig).attr("stroke-width",1.5).attr("stroke-dasharray","4 3").attr("opacity",0.9);
      svg.append("text").attr("x",x(state.yThr)+3).attr("y",m.t+8).attr("font-size",9).attr("fill",COL.sig).text(fmt(state.yThr));
    }
    // the two posterior densities
    for (const [key,col] of [["inactive",COL.inactive],["active",COL.active]]) {
      svg.append("path").attr("fill",col).attr("fill-opacity",0.3).attr("stroke",col)
        .attr("d", d3.area().x((_,i)=>x(g[i])).y0(dBot).y1(v=>y(v)).curve(d3.curveBasis)(d.dens[key]));
    }
    // 95% CI bars below (overlap = not a threshold/gap-mode TDI)
    for (const [key,col,yb] of [["inactive",COL.inactive,h-m.b-19],["active",COL.active,h-m.b-8]]) {
      const s=c[key];
      svg.append("line").attr("x1",x(s.lo)).attr("x2",x(s.hi)).attr("y1",yb).attr("y2",yb).attr("stroke",col).attr("stroke-width",2);
      svg.append("circle").attr("cx",x(s.pEC50)).attr("cy",yb).attr("r",3).attr("fill",col);
    }
  }

  // ---- Compound-class shape legend (controls bar, not the panels) -----------
  // Shape now carries meaning for all five TDI-annotation classes, not just
  // "controls vs. library", so the legend needs an entry per shape alongside
  // the existing significant/not-significant dots.
  const classLegend = d3.select("#class-legend");
  CLASS_ORDER.forEach(cls => {
    const item = classLegend.append("span").attr("class","legend-item");
    item.append("svg").attr("width",12).attr("height",12)
      .append("path")
        .attr("transform","translate(6,6)")
        .attr("d", d3.symbol().size(50).type(CLASS_SYMBOL[cls])())
        .attr("fill","currentColor").attr("opacity",0.75);
    item.append("span").text(" " + cls);
  });

  // ---- Build the four panels and render -------------------------------------
  ENZYMES.forEach((e,i) => drawPanel(e,i));
  renderAll();

  d3.select("#sig-only").on("change", function(){ state.sigOnly=this.checked; renderAll(); });
  d3.select("#search").on("input", function(){ state.search=this.value; renderAll(); });

  // Compound-class toggles — all five on by default (state.classes already
  // defaults to every class present in the data).
  d3.selectAll(".class-toggle").on("change", function(){
    const cls = this.value;
    this.checked ? state.classes.add(cls) : state.classes.delete(cls);
    renderAll();
  });

  // DRC-viewer y-axis bounds (live; defaults to the precomputed robust range).
  const applyYbounds = () => {
    const lo = parseFloat(d3.select("#drc-ymin").property("value"));
    const hi = parseFloat(d3.select("#drc-ymax").property("value"));
    if (isFinite(lo) && isFinite(hi) && hi > lo) { state.drcYmin = lo; state.drcYmax = hi; }
    const cur = state.pinned || state.hovered;
    if (cur) {
      const key = cur.key;
      // Same stale-response guard as renderSelection: re-read the current
      // selection inside the .then(), not the `cur` captured before the
      // fetch — otherwise a pin/hover change while this fetch is in flight
      // lets a late response overwrite #curve-plot with the wrong compound.
      loadDetail(enzymeOf(cur)).then(det => {
        const now = state.pinned || state.hovered;
        if (!now || now.key !== key) return;
        const d = det[key];
        if (d) renderCurvePlot(byKey.get(key), d);
      });
    }
  };
  d3.select("#drc-ymin").property("value", state.drcYmin.toFixed(1)).on("change", applyYbounds);
  d3.select("#drc-ymax").property("value", state.drcYmax.toFixed(1)).on("change", applyYbounds);

  // Live TDI-threshold inputs (shift, active pIC50) plus the mode toggle
  // (threshold / threshold+gap / fully Bayesian). `input`, not `change`, on
  // the number spinners so the scatter recolours while the spinner is held
  // — that live response is the point of making these adjustable.
  const applyThresholds = () => {
    const s = parseFloat(d3.select("#shift-thr").property("value"));
    const y = parseFloat(d3.select("#y-thr").property("value"));
    if (isFinite(s)) state.shiftThr = s;
    if (isFinite(y)) state.yThr = y;
    renderAll();                                   // recolour + redraw guide lines
    const cur = state.pinned || state.hovered;
    if (cur) renderSelection(cur.enzyme, cur.key); // the detail badge shows the call
  };
  d3.select("#shift-thr").on("input", applyThresholds);
  d3.select("#y-thr").on("input", applyThresholds);
  d3.select("#mode-select").on("change", function () {
    state.mode = this.value;
    d3.select("#y-thr").property("disabled", state.mode !== "threshold");
    applyThresholds();
  });

  // light/dark theme toggle — sets data-theme on <html>. The unset default is
  // light (styles.css), so that is what "current" means before the first
  // click; reading the OS preference here would make the first click a no-op
  // on a dark-preferring machine.
  const root = document.documentElement;
  d3.select("#theme-toggle").on("click", () => {
    const cur = root.dataset.theme || "light";
    root.dataset.theme = cur === "dark" ? "light" : "dark";
    // No structure re-render needed here: RDKit's SVG is theme-agnostic
    // (fixed light panel behind it in both themes, see styles.css), unlike
    // SmilesDrawer which used to bake its theme's colors in at draw time.
  });

  // Auto-select hook for deep-linking / smoke-testing: #first, #sig, or an
  // explicit keyOf() key (run:pair_id) in the URL hash.
  (function autoselect(){
    let h=""; try { h = location.hash ? decodeURIComponent(location.hash.slice(1)) : ""; } catch(e) { h=""; }
    if (!h) return;
    let t, enzyme;
    if (h === "first" || h === "sig") {
      for (const e of ENZYMES) {
        const act = activeCompounds(e);
        if (!act.length) continue;
        t = h === "first" ? act[0] : (act.find(c=>isSig(c)) || act[0]);
        enzyme = e;
        break;
      }
    } else {
      t = byKey.get(h);
      enzyme = t && t.enzyme;
    }
    if (t){ const k = keyOf(t); state.pinned={enzyme,key:k}; state.hovered={enzyme,key:k}; renderSelection(enzyme,k); }
  })();
})();
