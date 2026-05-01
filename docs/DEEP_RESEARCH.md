# TRIBE Review MVP — Deep Research Guide

## 1) What this project is doing end-to-end

At runtime, this project wraps the official **Meta TRIBE v2** model and adds a practical editorial layer for short-video review. The complete flow is:

1. **User uploads 1–4 videos** in the web UI.
2. FastAPI stores each upload under `runtime_media/<report_id>/`.
3. The backend runs official TRIBE v2 event extraction and prediction (`preds` over cortical vertices across time).
4. It converts raw model output into:
   - an official-style timeline (`signal_score` over time),
   - a local “editorial” analysis layer (drops, windows, recommendations),
   - a 3D brain visualization payload for browser playback.
5. UI renders single-video review or multi-video comparison.
6. Report can be exported as JSON/PDF.

This is orchestrated in `app.py` via `/review`, `/reports/{id}.json`, `/reports/{id}.pdf`, and `/reports/{id}` routes.

---

## 2) The model layer: what is actually being run

## 2.1 Official model source and loading path

The model backend is `TribeVideoBackend` in `tribe_runtime.py`.

- Model repo constant: `facebook/tribev2`.
- On first run, it downloads only `config.yaml` and `best.ckpt` from Hugging Face snapshot.
- It creates a runtime-specific model directory (`runtime-cpu` or `runtime-cuda`) and rewrites config `device:` field accordingly.
- It loads the model through `TribeModel.from_pretrained(...)`.

Important: this app does not ship model weights; it pulls them at runtime.

## 2.2 Inference inputs and modalities

The backend calls:

- `model.get_events_dataframe(video_path=...)` to generate multimodal events.
- `model.predict(events=..., verbose=False)` to get predictions and segments.

`modalities` is inferred from event dataframe `type` values and stored into report metadata.

## 2.3 Text events behavior (very important)

By default, the app removes TRIBE `word` events unless env var `TRIBE_ENABLE_TEXT_EVENTS` is enabled.

Why: official TRIBE word events require gated text encoder dependencies; this project keeps a **separate local speech layer** (`speech_runtime.py`) and therefore strips `word` events by default for simpler installs.

So, unless explicitly enabled, model inference is effectively using non-word event channels from official extraction.

## 2.4 Device strategy

The backend chooses `cuda` only if CUDA is available *and* a CUDA tensor allocation succeeds; otherwise CPU is used. Runtime config forces batch size and worker counts to conservative values for stability on local machines.

---

## 3) What the raw TRIBE output means in this app

TRIBE output is represented as:

- `preds`: 2D array shaped `[timesteps, vertices]`.
- `timestamps`: time-aligned segment points.

The app consistently converts this to a scalar timeline by computing:

- `response_magnitude[t] = mean(abs(preds[t, :]))`

Then it applies per-video min-max normalization to derive `signal_score` in `[0, 100]` for display.

### Practical implication

`signal_score` is **relative within a specific video**, not absolute across the world. In compare mode, the app applies additional harmonization logic to avoid naive comparisons when durations differ.

---

## 4) “Brain representation” in this repo: how it works and what it means

This is the most important conceptual section.

## 4.1 What the 3D brain object is

`brain_visualization.py` constructs a browser-ready mesh/frames package (`build_brain_simulation`). It uses `tribev2.plotting.cortical.PlotBrainNilearn` with mesh level `fsaverage5` to map per-vertex TRIBE signal onto cortical surface.

Returned payload includes:

- triangle faces,
- normalized cortical surfaces (`normal`, `inflated`),
- grayscale background map,
- per-frame heat signal values quantized to uint8 (0–255),
- region-level scores per frame,
- metadata labels/hints.

## 4.2 Time sampling and smoothing

- Temporal signal is transformed with absolute value and smoothed using kernel `[1,2,3,2,1]`.
- Number of visualization frames is bounded (`MIN_BRAIN_FRAMES=24`, `MAX_BRAIN_FRAMES=40`) and derived from duration and `TARGET_BRAIN_FPS`.
- Frame-level cortical maps are interpolated between TRIBE timestamps.

This is a visualization-oriented resampling, not raw frame-by-frame TRIBE output.

## 4.3 Thresholding and normalization

Per-frame maps are clipped and normalized by percentile-based `threshold` and `vmax`, then gamma-adjusted (`power 0.76`). This enhances salient regions for visual readability.

Meaning: bright regions are **relative high-activation zones under this normalization**, not calibrated biological units.

## 4.4 Region definitions (critical caveat)

The app defines 5 macro-zones (`frontal`, `sensorimotor`, `parietal`, `temporal`, `occipital`) by coordinate heuristics on normalized mesh coordinates (`y`, `z` thresholds). This is a pragmatic UI partition, not an official anatomical atlas from TRIBE.

So “region bars” are **application-level summaries** of model-driven cortical signal, grouped by geometric masks.

## 4.5 What users should believe vs not believe

Reasonable interpretation:

- “At this moment, model-predicted cortical response is stronger/weaker overall.”
- “These broad cortical areas carry relatively more signal under the app’s partition.”

Do **not** interpret as:

- medical diagnosis,
- exact neural measurement of real humans,
- proof of actual thoughts/emotions,
- guaranteed virality forecast.

---

## 5) Editorial intelligence layer (local heuristics)

Beyond official report (`official_report.py`), `review_engine.py` adds heuristic metrics and recommendations.

Key derived signals:

- `activation = mean(abs(preds), axis=1)`
- `novelty[t] = ||preds[t]-preds[t-1]||`

Then it computes metrics such as early response, sustain, transition density, stability, activation density, and maps them to 0–100 scores with configurable analysis profiles (`analysis_settings.py`).

This layer is intentionally “practical editing guidance,” not official TRIBE science.

---

## 6) Comparison mode logic (2–4 variants)

`generate_comparison_report(...)` ranks variants by a comparison score that blends:

- early-window average,
- overall average,
- floor robustness (lower-tail average).

A common comparable window is chosen across variants to reduce duration bias.

Implication: the winner is biased toward stronger starts + stable signal, not one isolated peak.

---

## 7) Speech layer architecture

There are two speech-related paths:

1. **Official TRIBE word-event extraction compatibility patch** in `tribe_runtime.py` via WhisperX helper, primarily to keep official extraction callable.
2. **Local speech layer** via `speech_runtime.py` consumed by editorial report generation.

By default, the app still removes TRIBE `word` events from model inference unless enabled by env var, so speech guidance in recommendations can come from local layer rather than TRIBE text channel.

---

## 8) How to use the project effectively

## 8.1 Start and run

- macOS: `./start_mvp.sh`
- Windows: `Start_TRIBE_Review.cmd`
- App URL: `http://127.0.0.1:8000`

First run may be long due to model and dependencies bootstrap.

## 8.2 Solo workflow (best for one cut)

1. Upload one video.
2. Identify major dips in timeline.
3. Click/seek around dip timestamps.
4. Inspect corresponding brain frames + practical cards.
5. Make one edit at a time.
6. Re-run and compare pre/post reports.

## 8.3 Compare workflow (best for creative iteration)

1. Upload 2–4 variants of same concept.
2. Use ranking + overlay curves to isolate strongest sections.
3. Build next cut from best hook/middle/retention segments.
4. Re-run new cut against current leader.

## 8.4 Interpretation guardrails

- Treat this as **decision support**, not oracle.
- Prefer repeated A/B iteration over one-pass conclusions.
- Use absolute timeline context (frame content, pacing, CTA timing) when acting on dips.

---

## 9) Operational details and artifacts

- Runtime outputs and uploads live in `runtime_media/`.
- In-memory report cache is bounded (`MAX_REPORTS=24`) in `app.py`.
- PDF export renders HTML template through headless Chrome path (`pdf_report.py`).
- Optional local copy simplification via Ollama (`ollama_runtime.py`) if model available.

---

## 10) Recommended “advanced user” settings

- Keep default text-events disabled unless you have full gated dependencies and want to experiment with TRIBE word channel.
- If using long videos, prefer CPU stability first; add CUDA only after baseline run works.
- For consistent creative testing, keep clip lengths and opening structures comparable.

---

## 11) Limitations and research integrity notes

- Project mixes official model inference with custom post-processing; separate these mentally.
- Brain region panel is a **UI abstraction** over cortical coordinates, not canonical neuroscience atlas output.
- Normalization is per-clip and visually enhanced; don’t compare raw brightness between unrelated runs without context.
- This repository itself is private/non-commercial evaluation code and points users to official TRIBE licensing constraints.

---

## 12) Quick “mental model” summary

- **TRIBE core**: predicts cortical response trajectory from multimodal video events.
- **This app**: converts that trajectory into editing-friendly timelines, comparisons, recommendations, and an interpretable 3D cortical animation.
- **Brain map meaning**: relative, model-derived saliency over cortical surface under app-defined rendering and region grouping.

If you keep those three layers separate (official inference vs app heuristics vs visualization abstraction), the tool becomes much easier to use correctly.
