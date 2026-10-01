# Lars13 — J.A.R.V.I.S for Hermes Agent (Windows port of `eadmin2/jarvis_ai`)

Fork of [`eadmin2/jarvis_ai`](https://github.com/eadmin2/jarvis_ai) (178★), retargeted to run on **this Windows 10 box** against a **local** Hermes Agent, with a **local-TTS / API-TTS toggle** for latency/resource testing.

This file consolidates the research done before any code was touched. It is the working briefing for the fork/install. Keep it at the repo root.

---

## 1. What upstream is (ground truth)

`eadmin2/jarvis_ai` is an Iron-Man-style **voice + HUD** pipeline on top of Hermes Agent:

```
Browser HUD (any LAN device)          Host
 ── https/wss :443 ──────┐   ┌──────────────────────────────────────────┐
   mic · speaker · panels ├──►│ voice pipeline server (FastAPI/uvicorn) │
                          │   │ STT: RealtimeSTT + faster-whisper (CPU) ├──► Hermes Agent
 Push-to-talk client      │   │ TTS: ElevenLabs Flash (streaming)       │   API :8642
 ── ws :8765 ─────────────┘   │ HUD + auth + dashboard TLS proxy        │   memory · tools
                              └──────────────────────────────────────────┘
```

- **Everything self-hosted.** Only cloud calls are your LLM provider (via Hermes) and ElevenLabs (voice). STT is local.
- **Features worth keeping:** live transcription, streaming TTS reply (3–5s round trip), STOP/barge-in, approval cards, embedded Kanban/session dashboards, HUD media panels (via bundled `hermes-plugin/hud_display`), usage tracking, optional GPU ear.

### Repo layout (the parts that matter)
```
server/            FastAPI voice pipeline + HUD host       <-- THE CORE
  server.py        voice pipeline (STT + TTS + HermesAPI client + uvicorn)
  hud/             single-file HUD (vanilla JS, no build)
  config/server.example.yaml -> config/server.yaml (voice settings live here)
  scripts/         jarvis-{start,stop,restart,health}.sh, make-certs.sh, make-boot-audio.sh
client/            optional Windows/Linux push-to-talk client (wake-word capable)
worker/            optional GPU sidecars (big-model STT + stats)
hermes-plugin/     Hermes plugin: agent can summon/dismiss HUD media panels
launchd/           macOS auto-start (com.jarvis.voice, com.jarvis.dashboard)   <- REPLACE for Windows
docs/              SETUP, ARCHITECTURE, TROUBLESHOOTING
```

### Confirmed stack / deps (all pip-installable on Windows)
`fastapi uvicorn requests pyyaml numpy anthropic RealtimeSTT faster-whisper silero-vad websockets psutil`

> **IMPORTANT:** `faster-whisper` and `silero-vad` are **REQUIRED**. Recent `RealtimeSTT` releases treat them as optional and fail at runtime without them (silently for VAD, loudly for the engine).

---

## 2. Windows port — what must change

Upstream is macOS/Linux. For this box (Windows 10, user `Admin`):

| Upstream (macOS/Linux) | Windows replacement |
|---|---|
| `launchd/com.jarvis.{voice,dashboard}.plist` | `windows/start.cmd`, `stop.cmd`, `health.cmd` + Task Scheduler (or NSSM) for auto-start |
| `server/scripts/jarvis-*.sh` | `windows/*.cmd` / PowerShell equivalents |
| `scripts/make-certs.sh` (self-signed TLS) | `powershell New-SelfSignedCertificate` + trust step |
| Browser-trust TLS cert | `certutil -user -addstore Root cert.pem` (already in upstream SETUP) |
| Python venv `source .venv/bin/activate` | `python -m venv .venv` ; `.venv\Scripts\activate` ; use `.venv\Scripts\python.exe` |

First start: downloads Whisper `small.en` (~460 MB); 60–90 s warm-up (torch import + model load). TLS required for browser mic (secure-origin only). Bind `server.host: 0.0.0.0` for LAN; loopback otherwise.

### Hermes side (unchanged, already configured on this box)
`jarvis_ai` drives Hermes' **API server on `127.0.0.1:8642`** with key from `API_SERVER_KEY`. This box already runs `:9119` dashboard / `:8642` gateway / `:8000` voice via the **Lars plugin stack** — so the Hermes API end is already present. Point `server.yaml` `hermes.base_url` at `http://127.0.0.1:8642` (loopback) and set `API_SERVER_KEY` in `lars13.env`.

---

## 3. The local-TTS / API-TTS toggle (the key custom feature)

Upstream TTS is **hard-wired to ElevenLabs**. The server method `tts_chunks_sync()`:
- reads key `ELEVENLABS_API_KEY` (falls back `ELEVEN_API_KEY`, `XI_API_KEY`)
- POSTs to ElevenLabs with `voice.model`, `voice_id`, `output_format: pcm_16000`
- **streams 4KB chunks** via `yield bytes` (real streaming, feeds barge-in/partial playback)

**Because TTS is streamed chunk-by-chunk, we can swap the provider cleanly.** Plan:

1. `server/config/server.yaml` — add `voice.provider` (default `elevenlabs`):
   ```yaml
   voice:
     provider: elevenlabs   # elevenlabs | local | groq | deepinfra
     model: eleven_flash_v2_5
     voice_id: ...
   ```
2. At the top of `tts_chunks_sync`, branch on `voice.provider` but **keep the identical streaming contract** (`yield bytes`), so barge-in / partial playback is untouched:

   | Provider | Streaming source | Cost / latency / intent |
   |---|---|---|
   | `elevenlabs` | upstream code, unchanged | best quality; per-char cost; network |
   | `local` | **Piper** (on-device, models in `models/piper/`) or Kokoro | zero cost, lowest first-byte; CPU load |
   | `groq` | Groq TTS endpoint (you have key) | cheap/fast; network |
   | `deepinfra` | DeepInfra TTS endpoint (you have key) | cheap/fast; network |

3. **Toggle = edit `server.yaml` + restart.** (Config is re-read at start; can expose as env var for a `.cmd`/Task one-liner switch: `set LARS13_TTS=local && start.cmd`.)

This gives the **latency/resources experiment** you want: local Piper (CPU, no net) vs Groq/DeepInfra (fast net, cheap) vs ElevenLabs (best quality/most cost), all behind one switch.

---

## 4. Resource & hardware eval (this box)

- **CPU:** i7-6600U (2-core / 4-thread, ~2.8 GHz), **RAM** 16 GB, **no GPU** (Intel HD 520), SSD.
- **Local STT** `faster-whisper small.en` int8 on CPU: **works but is the heavy lift.** On 4 threads expect ~2–4 s transcription. For lower latency test `base.en` or `tiny.en` (upstream measures `tiny` at ~0.3 s for language ID; on 2/4 cores the decoder takes half and live-guest STT auto-disables).
- **Local TTS** (Piper): runs fine on CPU, negligible RAM, zero network. Good low-latency baseline.
- **API TTS** (Groq/DeepInfra/ElevenLabs): cloud synthesis, trivial local CPU, needs network + key.
- Total footprint: venv + Whisper model (~460 MB) + Piper voices (~50–100 MB) + server. Fits easily.

**Your toggle test is the right experiment.** Measure first-byte latency + CPU% for local (Piper) vs DeepInfra/Groq vs ElevenLabs to pick the default.

---

## 5. Proposed location & repo/git plan

**Recommendation: do NOT put Lars13 inside `C:\Users\Admin\AppData\Local\hermes\`.**
Hermes' home is Hermes-managed and hot (runtime, `installs/`, `hermes-agent` source, `state.db`, logs, `desktop-plugins/lars`). `jarvis_ai` is a **separate standalone Python app** with its own venv/models/certs. Mixing it into Hermes' home risks the Hermes updater and clutters shared space. It talks to Hermes over the API (`:8642`) — it does not need to live inside Hermes.

**Proposed layout** (dedicated build tree; keep upstream dir structure):
```
C:\Users\Admin\lars13\
├── jarvis_ai\            # the fork (git remote origin -> github.com/AxiomLC/lars13)
│   ├── server\           # FastAPI voice pipeline + HUD
│   ├── client\ worker\ hermes-plugin\   # as upstream
│   └── windows\          # NEW: start/stop/health .cmd, cert, TTS-toggle wrapper
├── lars13.env            # secrets (ELEVENLABS_API_KEY, API_SERVER_KEY, JARVIS_HUD_TOKEN) — gitignored
└── setupREADME.md        # this file
```
(If OneDrive file-locking is a concern, prefer `C:\Users\Admin\Dev\lars13\` over a OneDrive path.)

### Fork / git steps (when terminal is available)
```bash
# Create the empty repo (or via gh) and connect the fork:
gh repo create lars13 --private --fork eadmin2/jarvis_ai --clone=false
# or manual: create empty repo AxiomLC/lars13, then:
git clone https://github.com/AxiomLC/lars13.git
cd lars13
git remote add upstream https://github.com/eadmin2/jarvis_ai.git
git fetch upstream && git merge upstream/main --allow-unrelated-histories
# then apply the Windows port + TTS toggle on a `windows` / `lars13` branch
```

---

## 6. Security model (from upstream — keep)
- Hermes API key never reaches the browser: the HUD proxies through the voice server (allowlist).
- HUD endpoints + dashboard proxy + WebSockets gated by a token (once per device).
- Hermes API + dashboard bind to loopback only.
- `lars13.env` is gitignored.
- LAN-only by design — do not port-forward.

---

## 7. Immediate next steps (tool-dependent)
Restore the `terminal`/`run-code` tools, then:
1. Verify terminal works (with `cd`, no bare `$` — Git Bash golden rule).
2. Clone upstream, init the `lars13` fork, push to `AxiomLC/lars13`.
3. Apply the Windows port (replace `launchd/` + `.sh` with `windows/*.cmd`; TLS cert; venv).
4. Implement the `voice.provider` toggle in `server.py` + `server.example.yaml`.
5. `pip install` into `.venv`, run health check, then live voice-test toggling local vs Groq/DeepInfra.

---
