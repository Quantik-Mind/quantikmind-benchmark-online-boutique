FROM python:3.12-slim

WORKDIR /workspace

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git \
       curl \
       jq \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git config --global --add safe.directory /workspace

RUN pip install --no-cache-dir --upgrade pip

CMD ["qmind", "--help"]
