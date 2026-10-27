# syntax=docker/dockerfile:1

# STalign: 空间转录组对齐工具镜像
#
# 参考安装文档: https://jef.works/STalign/overview.html
# 源码:         https://github.com/JEFworks-Lab/STalign
#
# 构建(CPU 版):
#   docker build -t stalign:latest .
#
# 固定 STalign 版本:
#   docker build --build-arg STALIGN_VERSION=<commit-or-tag> -t stalign:latest .
#
# 运行:
#   docker run --rm -it -v $PWD:/workspace stalign:latest python your_script.py
#
# 说明:
#   - 首行 `syntax` 指令启用 BuildKit 缓存挂载(--mount=type=cache)。
#     GitHub Actions 与新版 Docker 默认使用 BuildKit, 无需额外配置。
#   - 依赖版本见 requirements.txt; 需要完全可复现时, 用 `pip freeze` 生成精确 pin。

FROM python:3.11-slim-bookworm

# OCI 注解: 让 GHCR 能链接回仓库。请把 OWNER/REPO 改成你的实际仓库地址。
LABEL org.opencontainers.image.title="STalign" \
      org.opencontainers.image.description="STalign — alignment of spatial transcriptomics data via diffeomorphic metric mapping (LDDMM)" \
      org.opencontainers.image.source="https://github.com/doremiooo/STalign_Docker"

# ---------------------------------------------------------------------------
# 系统依赖
#   g++              : 编译可选 C++ 引擎(加速 LDDMM; 缺失则自动回退纯 torch)
#   git              : clone STalign 源码
#   libgl1/glib2.0-0 : matplotlib / scikit-image 在 slim 镜像下需要
#   --mount=type=cache: 复用 apt 缓存, 重复构建/CI 里大幅提速
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        g++ \
        git \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 依赖清单: 先 COPY 再 install —— 只有 requirements.txt 变化时才重建后续层
# ---------------------------------------------------------------------------
COPY requirements.txt /tmp/requirements.txt

# ---------------------------------------------------------------------------
# 1) PyTorch —— 计算后端(自动求导 + CPU/GPU)
#    默认 CPU 版(PyPI 的 torch wheel 即 CPU 版, 体积小)。
#    需要 GPU 时改成:
#       RUN pip install torch --index-url https://download.pytorch.org/whl/cu121
#    (并改用 nvidia/cuda 基础镜像 + --gpus all 运行)
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir torch

# ---------------------------------------------------------------------------
# 2) STalign runtime 依赖 + 对齐/notebook 常用包 (见 requirements.txt)
#    numpy / matplotlib / pandas / pynrrd / requests
#    scipy / scikit-learn / scikit-image / plotly
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# ---------------------------------------------------------------------------
# 3) STalign 本体(源码安装, 含可选 C++ 引擎编译)
#    CI 里建议把 STALIGN_VERSION 固定到 commit/tag, 保证可复现。
# ---------------------------------------------------------------------------
ARG STALIGN_VERSION=main
RUN --mount=type=cache,target=/root/.cache/pip \
    git clone --depth 1 --branch "${STALIGN_VERSION}" \
        https://github.com/JEFworks-Lab/STalign.git /opt/STalign \
    && cd /opt/STalign \
    && pip install --no-cache-dir .

# 验证导入
RUN python -c "import STalign; from STalign import STalign; print('STalign import OK')"

# ---------------------------------------------------------------------------
# 运行用户(安全最佳实践, 非 root)。
# 注意: 若挂载 `-v $PWD:/workspace` 后遇到写权限问题(常见于 Linux 宿主机),
#       可改用 `docker run --user root` 或 `--user $(id -u):$(id -g)`。
# ---------------------------------------------------------------------------
RUN useradd --create-home --uid 1000 --shell /bin/bash stalign \
    && mkdir -p /workspace \
    && chown -R stalign:stalign /workspace
WORKDIR /workspace
USER stalign

CMD ["python"]
