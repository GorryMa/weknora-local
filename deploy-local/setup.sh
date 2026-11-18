#!/usr/bin/env bash
# =====================================================================
# WeKnora 本地部署脚本（在仓库内直接运行）
# 用法：bash deploy-local/setup.sh
# 前置：已安装 Docker Desktop（或 docker + compose 插件）
# 说明：本脚本作用于**当前仓库**，不额外克隆源码。
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EMBED_MODEL="${EMBED_MODEL:-bge-m3}"
PULL_MODELS="${PULL_MODELS:-1}"

info() { printf '\n\033[36m>>> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m    OK  %s\033[0m\n' "$1"; }
warn() { printf '\033[33m    !!  %s\033[0m\n' "$1"; }
die()  { printf '\033[31m    XX  %s\033[0m\n' "$1"; exit 1; }

# ---------- 1. 依赖检查 ----------
info "检查 Docker 环境"
command -v docker >/dev/null 2>&1 || die "未找到 docker，请先安装 Docker Desktop"
docker info >/dev/null 2>&1 || die "Docker 引擎未运行，请先启动 Docker Desktop 并等到状态变绿"
docker compose version >/dev/null 2>&1 || die "缺少 docker compose 插件"
[ -f docker-compose.yml ] || die "当前目录不是 WeKnora 仓库根目录（缺少 docker-compose.yml）"
ok "docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?')"

# ---------- 2. 生成 .env ----------
info "准备配置文件"
if [ -f .env ]; then
  warn ".env 已存在，保留现有配置（如需重建请先备份后删除）"
else
  [ -f deploy-local/.env.example ] || die "缺少 deploy-local/.env.example"
  cp deploy-local/.env.example .env

  gen() {
    local n="${1:-24}" out=""
    if command -v openssl >/dev/null 2>&1; then
      out=$(openssl rand -base64 96 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-"$n") || true
    fi
    if [ -z "$out" ] && [ -r /dev/urandom ]; then
      out=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | cut -c1-"$n") || true
    fi
    printf '%s' "$out"
  }

  DB_PW="$(gen 20)"; REDIS_PW="$(gen 20)"; JWT_PW="$(gen 48)"; AES_KEY="$(gen 32)"
  for kv in "DB_PASSWORD=$DB_PW" "REDIS_PASSWORD=$REDIS_PW" "JWT_SECRET=$JWT_PW" "SYSTEM_AES_KEY=$AES_KEY"; do
    key="${kv%%=*}"; val="${kv#*=}"
    [ -n "$val" ] || die "随机密码生成失败，请手动编辑 .env"
    # awk 重写单行，规避 sed -i 在 Git Bash 与 GNU/BSD 之间的差异
    awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="}
      $1==k && !done {print k "=" v; done=1; next} {print}' .env > .env.tmp
    # 先确认结果非空再覆盖，避免异常时把 .env 清空
    [ -s .env.tmp ] || { rm -f .env.tmp; die "重写 .env 失败（$key），原文件未改动"; }
    mv .env.tmp .env
  done
  if grep -q '^JWT_SECRET=CHANGE_ME' .env; then
    die "配置写入失败，请检查 .env"
  fi
  if [ -z "$(awk -F= '$1=="SYSTEM_AES_KEY"{print $2}' .env)" ]; then
    die "SYSTEM_AES_KEY 未写入（缺失时模型 API Key 会明文入库），请手动填写 32 字节密钥"
  fi
  ok "已生成 .env（随机密码 + 加密主密钥）"
fi

# ---------- 3. 拉取镜像 ----------
info "拉取镜像（首次约 10 GB，请确保磁盘充足）"
docker compose pull
ok "镜像就绪"

# ---------- 4. 本地向量模型 ----------
if [ "$PULL_MODELS" = "1" ]; then
  info "检查 Ollama 与向量模型"
  if command -v ollama >/dev/null 2>&1; then
    if ollama list 2>/dev/null | grep -q "^${EMBED_MODEL}"; then
      ok "$EMBED_MODEL 已存在"
    else
      ollama pull "$EMBED_MODEL" || warn "拉取失败，可稍后执行：ollama pull $EMBED_MODEL"
    fi
  else
    warn "未安装 Ollama。若用云端 Embedding，可在设置页直接配置"
  fi
fi

# ---------- 5. 启动 ----------
info "启动服务"
docker compose up -d

info "等待服务就绪（最多 180 秒）"
for i in $(seq 1 60); do
  if curl -sf -m 2 http://localhost:8080/health >/dev/null 2>&1; then
    ok "后端已就绪"
    break
  fi
  [ "$i" -eq 60 ] && warn "等待超时，执行 docker compose logs -f app 查看原因"
  sleep 3
done

cat <<EOF

=====================================================================
 部署完成
=====================================================================
 访问地址   http://localhost
 首次使用   页面注册的第一个账号自动成为管理员
 服务状态   docker compose ps
 查看日志   docker compose logs -f app
 停止服务   docker compose down

 下一步必做（否则上传文档检索不到内容）：
   设置 → 模型管理 → 添加两个模型
     1) 类型 知识问答  来源 Ollama   模型名 qwen3:4b
     2) 类型 向量      来源 Ollama   模型名 bge-m3    维度 1024
   然后新建知识库并上传文档
 详见 deploy-local/README.md
=====================================================================
EOF
