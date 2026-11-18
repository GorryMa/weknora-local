#!/usr/bin/env bash
# =====================================================================
# 备份 WeKnora 数据（数据库 + 上传文件）
# 用法：bash deploy-local/backup.sh [输出目录]
# 产物：weknora-backup-YYYYmmdd-HHMMSS.tar.gz
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT_DIR="${1:-$ROOT/backups}"
TS="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f docker-compose.yml ] || { echo "请在仓库根目录执行"; exit 1; }
docker ps --format '{{.Names}}' | grep -q '^WeKnora-postgres$' || { echo "数据库容器未运行"; exit 1; }
mkdir -p "$OUT_DIR"

echo ">>> 导出数据库"
# 注意：导出内容含 models 表中的 API Key（未设 SYSTEM_AES_KEY 时为明文）与密码哈希，
# 切勿提交到公开仓库或放公开网盘。
docker exec WeKnora-postgres pg_dump -U postgres -d WeKnora -Fc -f /tmp/WeKnora.dump
docker cp WeKnora-postgres:/tmp/WeKnora.dump "$WORK/WeKnora.dump"
docker exec WeKnora-postgres rm -f /tmp/WeKnora.dump

echo ">>> 导出上传文件"
if docker ps --format '{{.Names}}' | grep -q '^WeKnora-app$'; then
  docker cp WeKnora-app:/data/files "$WORK/files" 2>/dev/null \
    || echo "    无 /data/files，跳过"
fi

echo ">>> 记录版本"
{
  echo "backup_time=$TS"
  grep -E '^WEKNORA_VERSION=' .env 2>/dev/null || echo "WEKNORA_VERSION=unknown"
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -i weknora || true
  ollama list 2>/dev/null | awk 'NR>1{print "ollama_model="$1}' || true
} > "$WORK/manifest.txt"

TARBALL="$OUT_DIR/weknora-backup-$TS.tar.gz"
tar -czf "$TARBALL" -C "$WORK" .
echo ">>> 完成：$TARBALL ($(du -h "$TARBALL" | cut -f1))"
echo "    恢复：bash deploy-local/restore.sh \"$TARBALL\""
