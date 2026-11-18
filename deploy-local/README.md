# 本地部署层（deploy-local）

本仓库是 [Tencent/WeKnora](https://github.com/Tencent/WeKnora) 的**完整源码镜像**，额外在
`deploy-local/` 下提供了本地私有化部署所需的配置、脚本与踩坑记录。**未修改任何业务源码。**

```
完整代码（上游 v0.9.0） + 本地部署层（本目录）
```

## 为什么有这个目录

上游仓库的部署文档默认你在干净的 Linux 环境、网络通畅、使用云端模型。实际在 Windows +
国内网络 + 本地小模型的组合下会遇到一串问题：镜像拉不到、图片型 PDF 解析出零个汉字、
提问要等五分钟。这个目录把这些问题和对应的解法固化下来，克隆一次即可复现。

## 快速开始

前置：Docker Desktop 已安装并处于运行状态；可选 Ollama（用本地向量模型时需要）。

```bash
bash deploy-local/setup.sh
```

脚本会：检查 Docker → 生成带随机密码与加密主密钥的 `.env` → 拉取镜像（约 10 GB）→ 检查
`bge-m3` → 启动五个容器 → 等待健康检查通过。

完成后打开 **http://localhost**，注册账号（第一个账号自动成为管理员）。

### 然后必须配置模型

**设置 → 模型管理 → 添加模型**，添加两个：

| 字段 | 模型 1（对话） | 模型 2（向量） |
|---|---|---|
| 类型 | 知识问答 `KnowledgeQA` | 向量 `Embedding` |
| 来源 | Ollama（本地）或 远程 API | Ollama（本地） |
| 模型名称 | `qwen3:4b` | `bge-m3` |
| 维度 | — | **1024** |
| Base URL | `http://host.docker.internal:11434` | 同左 |

```bash
ollama pull qwen3:4b     # 约 2.5 GB
ollama pull bge-m3       # 约 1.2 GB
```

> 16 GB 内存的机器建议**对话模型用云端 API**（DeepSeek / 通义 等 OpenAI 兼容接口）。
> 原因见 `docs/部署实录.md` 坑 5：两个本地模型同时常驻会互相驱逐，导致检索从
> 87 ms 变成 300 秒。

## 目录内容

| 文件 | 说明 |
|---|---|
| `.env.example` | 完整配置模板（900 行），密码与加密密钥为 `CHANGE_ME_*` / 空占位，版本固定 `v0.9.0` |
| `setup.sh` | 一键部署 |
| `backup.sh` | 备份数据库与上传文件（换机器必备） |
| `restore.sh` | 从备份恢复 |
| `docs/部署实录.md` | 7 个实际踩到的坑及根因分析 |

## 日常运维

```bash
docker compose ps                # 状态
docker compose logs -f app       # 后端日志
docker compose restart app       # 改配置后重启
docker compose down              # 停止（数据保留）
docker compose up -d             # 启动
```

## 备份与恢复

```bash
bash deploy-local/backup.sh                  # 输出到 backups/
bash deploy-local/restore.sh backups/xxx.tar.gz
```

> ⚠️ 备份文件含**模型 API Key**（`models.parameters` 字段；未设置 `SYSTEM_AES_KEY` 时为
> 明文，设置后为密文）与密码哈希，**不要**提交到仓库或公开网盘。`.gitignore` 已排除
> `backups/`、`*.dump`、`.env`。

## 不纳入版本控制的内容

本仓库只包含代码与部署模板，**不含**任何实际运行数据。以下内容已由 `.gitignore` 排除：

| 排除项 | 原因 |
|---|---|
| `.env` | 含真实数据库密码、JWT 密钥、AES 主密钥 |
| `backups/`、`*.dump`、`*.tar.gz` | 备份含模型 API Key 与密码哈希 |
| `data/`、`uploads/`、`logs/` | 本地运行产生的文档与日志 |

克隆后没有任何凭证 —— 首次运行 `setup.sh` 会现场生成随机值与强密钥。
请在仓库里**永远不要**提交自己的 `.env` 或备份包。

## 与上游的关系

- 本仓库保留了上游**完整提交历史**（4108 个提交）与全部标签，可随时同步官方更新：

```bash
git remote add upstream https://github.com/Tencent/WeKnora.git   # 只需一次
git fetch upstream --tags
git merge upstream/main        # 或 git checkout v0.10.0
```

- 当前源码在 `main` 分支（比 `v0.9.0` 标签新几个提交），而镜像固定为 `v0.9.0`。
  若要源码与镜像严格一致：

```bash
git checkout v0.9.0
```

- 许可证为 **MIT**，Copyright (C) 2026 Tencent，详见根目录 `LICENSE`。分发时**必须保留**该文件。

## 已知问题速查

| 症状 | 原因 | 解决 |
|---|---|---|
| `image not found` | 版本号缺 `v` 前缀 | `WEKNORA_VERSION=v0.9.0` |
| 文档解析出 0 个汉字 | 图片型 PDF，未开 OCR | 开多模态 + 显式传参重解析，见实录坑 3、4 |
| 点重新解析无变化 | 文档带旧参数快照 | 用 API 带 `process_config` 重解析 |
| 提问等几分钟 | 本地模型争抢内存 | 摘要模型改云端，`ollama stop qwen3:4b` |
| 容器连不上 Ollama | 误信需要改 `0.0.0.0` | 无需改，`host.docker.internal` 即可 |
| 日志刷 `langfuse-web` 报错 | 可选组件未启动 | 忽略 |

完整分析见 [`docs/部署实录.md`](docs/部署实录.md)。
