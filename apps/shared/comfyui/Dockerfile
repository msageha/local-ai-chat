# syntax=docker/dockerfile:1
# NVIDIA GPU で動かす ComfyUI。Apple Silicon の構成ではホストで動かす (apps/shared/comfyui/serve.sh) ので使わない
FROM python:3.13.18-slim-trixie@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90

# 版は apps/shared/comfyui/compose.yaml の build args で決め、ホストで動かすときと揃える
ARG COMFYUI_VERSION
ADD https://github.com/Comfy-Org/ComfyUI.git#${COMFYUI_VERSION} /opt/comfyui
WORKDIR /opt/comfyui
# NVIDIA 20 系以降の GPU は CUDA 13.0 以上の PyTorch が要る (ComfyUI の README)。その版は PyTorch の index にあるので、
# 先にそこから入れ、requirements.txt の torch をそれで満たす
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130 \
  && pip install --no-cache-dir -r requirements.txt

EXPOSE 8188
# ComfyUI は base directory の下の custom_nodes を作らずに読み、無いと起動に失敗する (v0.46.0 で確認) ので先に作る。
# 既定では 127.0.0.1 だけで待ち受けるので、コンテナの外から届くよう全アドレスで待ち受ける
ENTRYPOINT ["sh", "-c", "mkdir -p /data/custom_nodes && exec python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --base-directory /data"]
