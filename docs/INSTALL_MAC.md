# macOS Installation (Apple Silicon and Intel)

This app can run locally on macOS, including Apple Silicon (M1/M2/M3).

## Requirements

Recommended local setup:

- macOS 13+
- Python 3.11
- 16 GB RAM minimum (32 GB recommended)
- 30 GB+ free disk space

Notes for Apple Silicon:

- CUDA is not used on macOS.
- PyTorch runs on CPU (and can use Apple Metal where supported by your local PyTorch build).

## 1. Open Terminal in the project folder

```bash
cd /path/to/tribev2_viralanalyser
```

## 2. First launch

```bash
./start_mvp.sh
```

On first run, the script creates `.venv`, installs Python dependencies, and downloads model/runtime assets.

When bootstrap completes, run the command one more time.

## 3. Start the app

```bash
./start_mvp.sh
```

Then open:

```url
http://127.0.0.1:8000
```

If port `8000` is busy, the launcher tries `8001` through `8010`.

## 4. Optional Hugging Face login

If model download fails due to access requirements:

```bash
./.venv/bin/huggingface-cli login
```

## 5. Optional Ollama setup

Ollama is optional. Without it, recommendations use deterministic built-in copy.

```bash
ollama pull qwen3.5:9b
```
