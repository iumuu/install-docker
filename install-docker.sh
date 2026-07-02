#!/bin/bash

set -e

# 检测是否以 root 运行时
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 用户运行此脚本: sudo bash $0"
  exit 1
fi

echo "=========================================="
echo "    Docker 一键安装脚本 (Debian/Ubuntu)"
echo "=========================================="

# 检测系统
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VERSION=$VERSION_ID
else
  echo "无法检测操作系统"
  exit 1
fi

echo "检测到系统: $OS $VERSION"

# 仅支持 Debian 和 Ubuntu
if [[ "$OS" != "debian" && "$OS" != "ubuntu" ]]; then
  echo "此脚本仅支持 Debian 和 Ubuntu 系统"
  exit 1
fi

# 安装必要依赖
echo ""
echo "[1/5] 安装必要依赖..."
apt update
apt install -y curl vim wget gnupg dpkg apt-transport-https lsb-release ca-certificates jq gnupg-agent

# 确保 keyring 目录存在
mkdir -p /usr/share/keyrings

# 选择镜像源
echo ""
echo "[2/5] 配置 Docker apt 源..."
echo "请选择 Docker 源:"
echo "  1) 官方源 (国外)"
echo "  2) 清华源 (国内)"
# 默认使用官方源，如需清华源请输入 2
CHOICE=1
read -p "请输入选项 [1=官方源 2=清华源]: " INPUT
[ -n "$INPUT" ] && CHOICE=$INPUT

# 清理旧的 Docker 源
rm -f /etc/apt/sources.list.d/docker.list

case $CHOICE in
  2)
    # 使用清华源
    echo "使用清华源..."
    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg | gpg --dearmor --yes -o /usr/share/keyrings/docker-ce.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-ce.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian $(lsb_release -sc) stable" > /etc/apt/sources.list.d/docker.list
    ;;
  *)
    # 使用官方源
    echo "使用官方源..."
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /usr/share/keyrings/docker-ce.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-ce.gpg] https://download.docker.com/linux/debian $(lsb_release -sc) stable" > /etc/apt/sources.list.d/docker.list
    ;;
esac

# 安装 Docker
echo ""
echo "[3/5] 安装 Docker CE 和 Docker Compose..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 验证安装
echo ""
echo "[4/5] 验证安装..."
echo ""
docker version
echo ""
docker compose version

# 配置 Docker (可选)
echo ""
echo "[5/5] Docker 配置..."
read -p "是否配置 Docker daemon.json? (推荐, y/n): " CONFIGURE

if [[ "$CONFIGURE" == "y" || "$CONFIGURE" == "Y" ]]; then
  cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  },
  "userland-proxy": false,
  "registry-mirrors": []
}
EOF
  
  # 询问是否添加国内镜像加速
  read -p "是否添加国内镜像加速? (y/n): " MIRROR
  if [[ "$MIRROR" == "y" || "$MIRROR" == "Y" ]]; then
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  },
  "userland-proxy": false,
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ]
}
EOF
  fi
  
  systemctl restart docker
  echo "Docker 配置已完成"
fi

echo ""
echo "=========================================="
echo "  Docker 安装完成!"
echo "=========================================="
echo ""
echo "常用命令:"
echo "  docker run hello-world      # 测试 Docker"
echo "  docker ps                   # 查看运行中的容器"
echo "  docker compose up -d        # 启动 Docker Compose"
echo ""