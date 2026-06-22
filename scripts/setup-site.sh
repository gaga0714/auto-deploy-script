#!/usr/bin/env bash
#
# setup-site.sh — 在服务器上一键接入新项目的 nginx 配置
#
# 用法:
#   sudo ./setup-site.sh <project-name> [--root <path>] [--port <port>]
#
# 行为:
#   1. 校验静态文件根目录已存在
#   2. 已有同名 config → 复用退出(幂等)
#   3. 未指定端口 → 扫描 sites-available/enabled 已用端口,取最大值 +1,基线 8080
#   4. 渲染 nginx 模板 → 写临时文件 → 临时软链 → nginx -t
#   5. 通过则正式落地 + reload nginx;失败则回滚临时文件与软链
#
# 退出码: 0=成功 1=运行错误 2=参数错误

set -euo pipefail

PORT_BASE=8080
NGINX_AVAIL_DIR=/etc/nginx/sites-available
NGINX_ENABLED_DIR=/etc/nginx/sites-enabled

usage() {
  cat <<'EOF' >&2
usage: sudo setup-site.sh <project-name> [--root <path>] [--port <port>]

  <project-name>   nginx config 文件名 / 项目标识(必填)
  --root <path>    静态文件根目录,默认 /home/html/<project-name>
  --port <port>    手动指定端口,跳过自动分配
EOF
  exit 2
}

log()  { echo "[setup-site] $*"; }
die()  { echo "[setup-site] error: $*" >&2; exit 1; }

# 必须 root(读写 /etc/nginx、调 systemctl)
[[ $EUID -eq 0 ]] || die "must run as root (use sudo)"

# 参数解析
[[ $# -ge 1 ]] || usage
PROJECT="$1"; shift
ROOT="/home/html/$PROJECT"
PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:?--root requires a value}"; shift 2;;
    --port) PORT="${2:?--port requires a value}"; shift 2;;
    -h|--help) usage;;
    *) echo "unknown arg: $1" >&2; usage;;
  esac
done

# 项目名合法性(避免奇怪字符进路径)
[[ "$PROJECT" =~ ^[a-zA-Z0-9._-]+$ ]] || die "invalid project name: $PROJECT"

AVAIL="$NGINX_AVAIL_DIR/$PROJECT"
ENABLED="$NGINX_ENABLED_DIR/$PROJECT"

# 1. 校验 root 目录
[[ -d "$ROOT" ]] || die "root not found: $ROOT (先确认 CI 已 rsync 过)"

# 2. 幂等:已存在则复用
if [[ -e "$AVAIL" ]]; then
  EXIST_PORT=$(grep -oE 'listen[[:space:]]+[0-9]+' "$AVAIL" | awk '{print $2}' | head -1)
  log "config exists, reusing: $AVAIL (port=$EXIST_PORT)"
  # 顺便补一下软链(防止之前 enable 出问题)
  [[ -L "$ENABLED" ]] || ln -sfn "$AVAIL" "$ENABLED"
  exit 0
fi

# 3. 端口分配
if [[ -z "$PORT" ]]; then
  MAX_PORT=$(grep -rhoE 'listen[[:space:]]+[0-9]+' \
              "$NGINX_AVAIL_DIR" "$NGINX_ENABLED_DIR" 2>/dev/null \
              | awk '{print $2}' \
              | awk -v base="$PORT_BASE" '$1 >= base' \
              | sort -un \
              | tail -1 || true)
  PORT=$(( ${MAX_PORT:-$((PORT_BASE - 1))} + 1 ))
fi

# 端口合法性 + 范围
[[ "$PORT" =~ ^[0-9]+$ ]] || die "invalid port: $PORT"
(( PORT > 0 && PORT < 65536 )) || die "port out of range: $PORT"

log "project=$PROJECT root=$ROOT port=$PORT"

# 4. 渲染配置到临时文件
TMP=$(mktemp "${AVAIL}.XXXXXX")
# 保证异常退出时不留垃圾
trap 'rm -f "$TMP"; [[ -L "$ENABLED" && "$(readlink "$ENABLED")" == "$TMP" ]] && rm -f "$ENABLED" || true' EXIT

cat > "$TMP" <<EOF
# managed by setup-site.sh — project=$PROJECT
server {
    listen $PORT;
    server_name localhost;

    root $ROOT;
    index index.html;

    # Flutter web SPA:任何路径回退到 index.html
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # hash 化的静态资源 → 长缓存
    location ~* \.(js|css|woff2?|png|jpg|svg|webp)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # index.html 不缓存,更新立即生效
    location = /index.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }
}
EOF

# 5. 临时软链 → 语法检查
ln -sfn "$TMP" "$ENABLED"
if ! nginx -t 2>&1 | sed 's/^/[nginx -t] /'; then
  die "nginx -t failed, rolled back (临时文件已删除)"
fi

# 6. 正式落地
mv "$TMP" "$AVAIL"
ln -sfn "$AVAIL" "$ENABLED"
trap - EXIT  # 落地成功,取消清理 trap

if ! systemctl reload nginx; then
  die "systemctl reload nginx failed (config 已落地,手动检查 systemctl status nginx)"
fi

log "ok: $PROJECT listening on :$PORT, root=$ROOT"
log "test: curl -I http://127.0.0.1:$PORT/"
