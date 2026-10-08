#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "请使用 root 用户运行此脚本: sudo bash $0" >&2
  exit 1
fi

printf '%s\n' '==========================================' '    Docker 一键安装脚本 (Debian/Ubuntu)' '=========================================='

if [[ ! -r /etc/os-release ]]; then
  echo "无法检测操作系统" >&2
  exit 1
fi
. /etc/os-release
OS=${ID:-}
VERSION=${VERSION_ID:-}
CODENAME=${VERSION_CODENAME:-}

# 某些精简系统没有 VERSION_CODENAME
if [[ -z "$CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
  CODENAME=$(lsb_release -sc)
fi

case "$OS" in
  ubuntu|debian) ;;
  *) echo "此脚本仅支持 Debian 和 Ubuntu 系统" >&2; exit 1 ;;
esac

if [[ -z "$CODENAME" ]]; then
  echo "无法确定系统发行版代号" >&2
  exit 1
fi

echo "检测到系统: $OS $VERSION ($CODENAME)"

# Debian 11 的 backports 已归档，当前镜像通常返回 404；禁用后再更新。
if [[ "$OS" == "debian" && "$CODENAME" == "bullseye" ]]; then
  find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print0 2>/dev/null |
    xargs -0r sed -i '/bullseye-backports/s/^/# disabled: /'
  sed -i '/bullseye-backports/s/^/# disabled: /' /etc/apt/sources.list 2>/dev/null || true
fi

echo
echo '[1/5] 安装必要依赖...'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget gnupg ca-certificates lsb-release

# 直接覆盖 Docker 源文件；不扫描其他 APT 文件，避免影响系统源。
# 旧的 docker.list 会被下面的正确配置覆盖。
rm -f /etc/apt/sources.list.d/docker-ce.list

printf '\n[2/5] 配置 Docker apt 源...\n'
CHOICE=1
if [[ -t 0 ]]; then
  echo '请选择 Docker 源:'
  echo '  1) 官方源 (国外)'
  echo '  2) 清华源 (国内，仅适用于 Debian/Ubuntu)'
  read -r -p '请输入选项 [1=官方源 2=清华源]: ' INPUT || true
  [[ -n "${INPUT:-}" ]] && CHOICE=$INPUT
fi

case "$OS" in
  ubuntu) DOCKER_OS=ubuntu; KEY_URL=https://download.docker.com/linux/ubuntu; TSINGHUA_URL=https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu ;;
  debian) DOCKER_OS=debian; KEY_URL=https://download.docker.com/linux/debian; TSINGHUA_URL=https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian ;;
esac

install -m 0755 -d /etc/apt/keyrings
if [[ "$CHOICE" == 2 ]]; then
  echo '使用清华源...'
  curl -fsSL "$TSINGHUA_URL/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  REPO_URL=$TSINGHUA_URL
else
  echo '使用官方源...'
  curl -fsSL "$KEY_URL/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  REPO_URL=$KEY_URL
fi
chmod a+r /etc/apt/keyrings/docker.gpg
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] %s %s stable\n' \
  "$(dpkg --print-architecture)" "$REPO_URL" "$CODENAME" > /etc/apt/sources.list.d/docker.list

printf '\n[3/5] 安装 Docker CE 和 Docker Compose...\n'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

printf '\n[4/5] 验证安装...\n'
docker --version
docker compose version

printf '\n[5/5] Docker 配置...\n'
CONFIGURE=n
if [[ -t 0 ]]; then read -r -p '是否配置 Docker daemon.json? (推荐, y/n): ' CONFIGURE || true; fi
if [[ "$CONFIGURE" =~ ^[Yy]$ ]]; then
  install -d -m 0755 /etc/docker
  cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "20m", "max-file": "3"},
  "userland-proxy": false,
  "registry-mirrors": []
}
EOF
  if [[ -t 0 ]]; then
    read -r -p '是否添加国内镜像加速? (y/n): ' MIRROR || true
    if [[ "$MIRROR" =~ ^[Yy]$ ]]; then
      sed -i 's/"registry-mirrors": \[\]/"registry-mirrors": ["https:\/\/docker.mirrors.ustc.edu.cn", "https:\/\/hub-mirror.c.163.com", "https:\/\/mirror.baidubce.com"]/' /etc/docker/daemon.json
    fi
  fi
  systemctl enable --now docker
  systemctl restart docker
  echo 'Docker 配置已完成'
else
  systemctl enable --now docker 2>/dev/null || true
fi

echo
echo '=========================================='
echo '  Docker 安装完成!'
echo '=========================================='
echo '测试命令: docker run --rm hello-world'
