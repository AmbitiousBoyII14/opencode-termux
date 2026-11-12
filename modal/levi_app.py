"""
Levi on Modal — CPU only. No payment method required.

    modal deploy modal/levi_app.py

Verified on this workspace 2026-11-11:
    CPU function        OK (8 cores, 32 GiB)
    GPU function        BLOCKED — "Please add a payment method"
    llama-server CPU    7.68 tok/s on Q4_K_M, 31 s model load
"""

import os
import subprocess

import modal

# ------------------------------------------------------------------ knobs
QUANT = "Q4_K_M"          # 18.31 GB. Q3_K_M=14.61 GB if you want more headroom.
CTX = 32768
THREADS = 8
UPSTREAM_PORT = 8081
PUBLIC_PORT = 8000

GGUF_URL = (
    "https://huggingface.co/unsloth/GLM-4.7-Flash-GGUF/resolve/main/"
    f"GLM-4.7-Flash-{QUANT}.gguf"
)
GGUF_PATH = f"/models/GLM-4.7-Flash-{QUANT}.gguf"

HERE = os.path.dirname(os.path.abspath(__file__))

# Modal re-imports this module inside the container, where only files added via
# add_local_file exist. Never hard-fail on it here; the gateway does the real load.
try:
    with open(os.path.join(HERE, "levi-system-prompt.md"), encoding="utf-8") as _f:
        SYSTEM_PROMPT = _f.read().strip()
except OSError:
    SYSTEM_PROMPT = ""

# IMPORTANT: GGML_NATIVE=OFF + runtime variant dispatch.
# The image builds on one CPU and runs on another; a native build dies with SIGILL
# (rc=-4) at startup. This exact failure cost us three deploys — don't "optimise" it back.
llama_image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install(
        "build-essential", "cmake", "git", "curl",
        "libcurl4-openssl-dev", "ca-certificates",
    )
    .pip_install("fastapi>=0.115", "uvicorn[standard]>=0.32", "httpx>=0.27")
    .run_commands(
        "git clone --depth 1 https://github.com/ggml-org/llama.cpp /opt/llama.cpp",
        "cd /opt/llama.cpp && cmake -B build -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON "
        "-DGGML_CPU_ALL_VARIANTS=ON -DGGML_OPENMP=ON -DLLAMA_CURL=ON "
        "-DCMAKE_BUILD_TYPE=Release",
        "cd /opt/llama.cpp && cmake --build build --target llama-server -j 8",
    )
    # The prompt is shipped as a FILE, not an env var: it contains an apostrophe,
    # which breaks the generated Dockerfile ENV line. Do not switch this back.
    .add_local_file(
        os.path.join(HERE, "levi-system-prompt.md"),
        remote_path="/root/levi-system-prompt.txt",
    )
    .add_local_file(
        os.path.join(HERE, "levi_gateway.py"), remote_path="/root/levi_gateway.py"
    )
)

models = modal.Volume.from_name("levi-models", create_if_missing=True)
app = modal.App("levi")


@app.function(
    image=llama_image,
    volumes={"/models": models},
    cpu=THREADS,
    memory=65536,
    timeout=60 * 60,
    scaledown_window=300,   # idle 5 min -> scale to zero, billing stops
    min_containers=0,
    secrets=[modal.Secret.from_name("levi-secret")],
)
@modal.web_server(port=PUBLIC_PORT, startup_timeout=25 * 60)
def serve():
    if not os.path.exists(GGUF_PATH):
        subprocess.run(["curl", "-L", "-sS", "-o", GGUF_PATH, GGUF_URL], check=True)
        models.commit()

    subprocess.Popen([
        "/opt/llama.cpp/build/bin/llama-server",
        "-m", GGUF_PATH,
        "--alias", "glm-4.7-flash",
        "-t", str(THREADS),
        "-c", str(CTX),
        "--host", "127.0.0.1",
        "--port", str(UPSTREAM_PORT),
        "-np", "1",
        "--jinja",
        "--cache-reuse", "256",   # reuse KV for the identical 6-8k system prefix the client resends every turn
        "--reasoning", "off",      # this model thinks for ages; off by default
    ])

    subprocess.Popen([
        "uvicorn", "levi_gateway:api",
        "--app-dir", "/root",
        "--host", "0.0.0.0",
        "--port", str(PUBLIC_PORT),
        "--log-level", "warning",
    ])
