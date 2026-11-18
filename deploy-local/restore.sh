#!/usr/bin/env bash
# =====================================================================
# 从备份恢复 WeKnora 数据
# 用法：bash deploy-local/restore.sh backups/weknora-backup-xxxx.tar.gz
# 前置：目标机器已能正常启动（数据库容器存在且 healthy）
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TARBALL="${1:-}"

[ -n "$TARBALL" ] || { echo "用法：bash deploy-local/restore.sh <备份文件.tar.gz>"; exit 1; }
[ -f "$TARBALL" ] || { echo "文件不存在：$TARBALL"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$TARBALL" -C "$WORK"

echo ">>> 备份信息"
cat "$WORK/manifest.txt" 2>/dev/null || echo "(无 manifest)"

echo ""
echo "!!! 恢复会覆盖现有数据库内容，按 Ctrl-C 取消，回车继续"
read -r _

echo ">>> 停止应用容器"
docker compose stop app docreader frontend || true

echo ">>> 重建数据库"
docker exec WeKnora-postgres psql -U postgres -d postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='WeKnora' AND pid<>pg_backend_pid();" >/dev/null
docker exec WeKnora-postgres psql -U postgres -d postgres -c 'DROP DATABASE IF EXISTS "WeKnora";' >/dev/null
docker exec WeKnora-postgres psql -U postgres -d postgres -c 'CREATE DATABASE "WeKnora";' >/dev/null

echo ">>> 导入数据"
docker cp "$WORK/WeKnora.dump" WeKnora-postgres:/tmp/WeKnora.dump
docker exec WeKnora-postgres pg_restore -U postgres -d WeKnora --no-owner --no-acl /tmp/WeKnora.dump || \
  echo "    pg_restore 有警告（多为 owner 差异，通常可忽略）"
docker exec WeKnora-postgres rm -f /tmp/WeKnora.dump

if [ -d "$WORK/files" ]; then
  echo ">>> 恢复上传文件"
  docker cp "$WORK/files" WeKnora-app:/data/ 2>/dev/null || echo "    跳过（容器无 /data 目录）"
fi

echo ">>> 启动服务"
docker compose up -d

cat <<'EOF'

恢复完成。请检查：
  1. http://localhost 能否登录（账号来自备份）
  2. 知识库 → 文档列表，状态是否正常
  3. 若向量模型与备份时不同，需重新解析文档并重建索引
EOF
