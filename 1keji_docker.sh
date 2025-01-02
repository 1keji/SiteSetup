#!/bin/bash

# Docker 和 Docker Compose 管理脚本
# 提供安装、卸载、查询状态、容器操作、镜像管理和退出选项
# 适用于 Ubuntu 和 Debian 系统

set -e

# 函数：显示主菜单
show_menu() {
    echo "===========**一点科技**==================="
    echo "Docker 和 Docker Compose 管理脚本"
    echo "  博  客： https://1keji.net"
    echo "  YouTube：https://www.youtube.com/@1keji_net"
    echo "  GitHub： https://github.com/1keji"
    echo "=========================================="
    echo "1. 安装 Docker 和 Docker Compose"
    echo "2. 卸载 Docker 和 Docker Compose"
    echo "3. 查询安装情况和运行状态"
    echo "4. 容器操作（启动、停止、重启、删除）"
    echo "5. 镜像管理（查询、拉取、升级、删除）"
    echo "0. 退出脚本"
    echo "=========================================="
}

# 函数：显示容器操作子菜单
show_container_menu() {
    echo "=========== 容器操作 ==========="
    echo "1. 启动容器"
    echo "2. 停止容器"
    echo "3. 重启容器"
    echo "4. 删除容器"
    echo "5. 查询运行的容器"
    echo "0. 返回主菜单"
    echo "==============================="
}

# 函数：显示镜像管理子菜单
show_image_menu() {
    echo "=========== 镜像管理 ==========="
    echo "1. 查询所有镜像"
    echo "2. 拉取指定镜像"
    echo "3. 升级指定镜像"
    echo "4. 删除指定镜像版本 (通过 IMAGE ID)"
    echo "0. 返回主菜单"
    echo "==============================="
}

# 函数：检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        # 将 ID 和 ID_LIKE 转换为小写
        ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        ID_LIKE=$(echo "$ID_LIKE" | tr '[:upper:]' '[:lower:]')
        # 优先使用 ID 来检测
        case "$ID" in
            ubuntu)
                OS="ubuntu"
                ;;
            debian)
                OS="debian"
                ;;
            *)
                # 如果 ID 不是 ubuntu 或 debian，尝试使用 ID_LIKE
                if echo "$ID_LIKE" | grep -qw 'ubuntu'; then
                    OS="ubuntu"
                elif echo "$ID_LIKE" | grep -qw 'debian'; then
                    OS="debian"
                else
                    OS=""
                fi
                ;;
        esac
        VERSION_CODENAME=$(echo "$VERSION_CODENAME" | tr '[:upper:]' '[:lower:]')
    else
        echo "无法检测操作系统。"
        exit 1
    fi

    # 打印检测到的操作系统和版本代号（用于调试）
    echo "检测到的操作系统: $OS"
    echo "版本代号: $VERSION_CODENAME"
}

# 函数：删除错误的 Docker 仓库配置
remove_incorrect_docker_repo() {
    echo "检查并删除错误的 Docker 仓库配置..."

    # 定义正确的仓库 URL
    CORRECT_REPO="https://download.docker.com/linux/${OS}"

    # 在 sources.list 中查找错误的 Docker 仓库配置
    if grep -E "download.docker.com/linux/(ubuntu|debian)" /etc/apt/sources.list | grep -v "${CORRECT_REPO}" >/dev/null 2>&1; then
        echo "在 /etc/apt/sources.list 中发现错误的 Docker 仓库配置，正在删除..."
        sed -i "/download.docker.com\/linux\/\(ubuntu\|debian\)/d" /etc/apt/sources.list
    fi

    # 在 sources.list.d 目录下查找并删除错误的 Docker 仓库配置文件
    for file in /etc/apt/sources.list.d/*.list; do
        if [ -f "$file" ]; then
            if grep -E "download.docker.com/linux/(ubuntu|debian)" "$file" | grep -v "${CORRECT_REPO}" >/dev/null 2>&1; then
                echo "发现错误的 Docker 仓库配置文件：$file，正在删除..."
                rm -f "$file"
            fi
        fi
    done
}

# 函数：添加 Docker 仓库
add_docker_repo() {
    echo "添加 Docker 的官方 GPG 密钥..."
    curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # 删除旧的 Docker 仓库配置
    echo "删除旧的 Docker 仓库配置..."
    rm -f /etc/apt/sources.list.d/docker.list

    echo "设置 Docker 的 APT 仓库..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${OS} \
      ${VERSION_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
}

# 函数：列出所有非系统用户
list_non_system_users() {
    echo "服务器上的用户列表："
    # 根据 UID 列出非系统用户（UID >= 1000）
    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd
}

# 函数：安装 Docker 和 Docker Compose
install_docker() {
    echo "开始安装 Docker 和 Docker Compose..."

    # 更新 APT 包索引
    echo "更新 APT 包索引..."
    apt-get update -y

    # 安装必要的依赖包
    echo "安装必要的依赖包..."
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # 检查并删除错误的 Docker 仓库配置
    remove_incorrect_docker_repo

    # 添加 Docker 的官方 GPG 密钥和 APT 仓库
    add_docker_repo

    # 再次更新 APT 包索引
    echo "再次更新 APT 包索引..."
    apt-get update -y

    # 安装最新版本的 Docker Engine、CLI 和容器运行时
    echo "安装最新版本的 Docker Engine、CLI 和 容器运行时..."
    apt-get install -y docker-ce docker-ce-cli containerd.io

    # 启动并启用 Docker 服务
    echo "启动并启用 Docker 服务..."
    systemctl start docker
    systemctl enable docker

    # 验证 Docker 是否安装成功
    echo "验证 Docker 是否安装成功..."
    docker --version

    # 安装 Docker Compose
    echo "安装 Docker Compose..."

    # 获取最新的 Docker Compose 版本号
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f4)

    # 下载 Docker Compose 二进制文件
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    # 赋予执行权限
    chmod +x /usr/local/bin/docker-compose

    # 创建软链接
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

    # 验证 Docker Compose 是否安装成功
    echo "验证 Docker Compose 是否安装成功..."
    docker-compose --version

    # 将当前用户添加到 docker 用户组（以便无需 sudo 运行 Docker 命令）
    echo "将当前用户添加到 docker 用户组（以便无需 sudo 运行 Docker 命令）..."

    # 获取当前运行脚本的用户
    CURRENT_USER=""
    if [ "$SUDO_USER" ]; then
        CURRENT_USER="$SUDO_USER"
    else
        CURRENT_USER=$(logname 2>/dev/null || echo "")
    fi

    # 检查是否为 root 用户
    if [ "$CURRENT_USER" = "root" ] || [ -z "$CURRENT_USER" ]; then
        echo "当前用户为 root。您可以选择添加其他用户到 docker 组，或直接跳过。"
        list_non_system_users
        echo "提示：按回车键跳过，或输入一个存在的非 root 用户名。"
        read -p "请输入要添加到 docker 组的用户名（按回车键跳过）： " USERNAME

        if [ -z "$USERNAME" ]; then
            echo "已跳过将用户添加到 docker 组的步骤。"
        else
            # 检查用户是否存在且不是 root
            if id "$USERNAME" >/dev/null 2>&1 && [ "$USERNAME" != "root" ]; then
                if id -nG "$USERNAME" | grep -qw "docker"; then
                    echo "用户 $USERNAME 已经在 docker 组中。"
                else
                    usermod -aG docker "$USERNAME"
                    echo "用户 $USERNAME 已添加到 docker 组。"
                    echo "请注销并重新登录以使更改生效。"
                fi
            else
                echo "错误：用户 '$USERNAME' 不存在或为 root 用户。跳过将用户添加到 docker 组的步骤。"
            fi
        fi
    else
        # 非 root 用户，默认添加当前用户到 docker 组
        USERNAME="$CURRENT_USER"
        if id -nG "$USERNAME" | grep -qw "docker"; then
            echo "用户 $USERNAME 已经在 docker 组中。"
        else
            usermod -aG docker "$USERNAME"
            echo "用户 $USERNAME 已添加到 docker 组。"
            echo "请注销并重新登录以使更改生效。"
        fi
    fi

    echo "Docker 和 Docker Compose 安装完成！"
}

# 函数：卸载 Docker 和 Docker Compose
uninstall_docker() {
    echo "开始卸载 Docker 和 Docker Compose..."

    # 停止并禁用 Docker 服务
    echo "停止并禁用 Docker 服务..."
    systemctl stop docker
    systemctl disable docker

    # 卸载 Docker Engine、CLI 和 容器运行时
    echo "卸载 Docker Engine、CLI 和 容器运行时..."
    apt-get purge -y docker-ce docker-ce-cli containerd.io

    # 删除所有 Docker 数据
    echo "删除所有 Docker 数据..."
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd

    # 删除 Docker Compose
    echo "删除 Docker Compose..."
    rm -f /usr/local/bin/docker-compose
    rm -f /usr/bin/docker-compose

    # 删除 Docker 的 APT 仓库
    echo "删除 Docker 的 APT 仓库..."
    rm -f /etc/apt/sources.list.d/docker.list

    # 删除 Docker 的 GPG 密钥
    echo "删除 Docker 的 GPG 密钥..."
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg

    # 更新 APT 包索引
    echo "更新 APT 包索引..."
    apt-get update -y

    # 从 docker 组中移除用户
    echo "从 docker 组中移除用户..."

    # 获取当前运行脚本的用户
    CURRENT_USER=""
    if [ "$SUDO_USER" ]; then
        CURRENT_USER="$SUDO_USER"
    else
        CURRENT_USER=$(logname 2>/dev/null || echo "")
    fi

    # 检查是否为 root 用户
    if [ "$CURRENT_USER" = "root" ] || [ -z "$CURRENT_USER" ]; then
        echo "当前用户为 root。您可以选择从 docker 组中移除其他用户，或直接跳过。"
        list_non_system_users
        echo "提示：按回车键跳过，或输入一个存在的非 root 用户名。"
        read -p "请输入要从 docker 组中移除的用户名（按回车键跳过）： " USERNAME

        if [ -z "$USERNAME" ]; then
            echo "已跳过从 docker 组中移除用户的步骤。"
        else
            # 检查用户是否存在且不是 root
            if id "$USERNAME" >/dev/null 2>&1 && [ "$USERNAME" != "root" ]; then
                if id -nG "$USERNAME" | grep -qw "docker"; then
                    gpasswd -d "$USERNAME" docker
                    echo "用户 $USERNAME 已从 docker 组中移除。"
                else
                    echo "用户 $USERNAME 不在 docker 组中。"
                fi
            else
                echo "错误：用户 '$USERNAME' 不存在或为 root 用户。跳过从 docker 组中移除用户的步骤。"
            fi
        fi
    else
        # 非 root 用户，默认从 docker 组中移除当前用户
        USERNAME="$CURRENT_USER"
        if id -nG "$USERNAME" | grep -qw "docker"; then
            gpasswd -d "$USERNAME" docker
            echo "用户 $USERNAME 已从 docker 组中移除。"
        else
            echo "用户 $USERNAME 不在 docker 组中。"
        fi
    fi

    echo "Docker 和 Docker Compose 已成功卸载！"
}

# 函数：查询安装情况和运行状态
check_status() {
    echo "查询 Docker 和 Docker Compose 的安装情况和运行状态..."

    # 检查 Docker 是否安装
    if command -v docker >/dev/null 2>&1; then
        echo "Docker 已安装，版本信息："
        docker --version
    else
        echo "Docker 未安装。"
    fi

    # 检查 Docker 服务状态
    if systemctl is-active --quiet docker; then
        echo "Docker 服务正在运行。"
    else
        echo "Docker 服务未运行。"
    fi

    echo ""

    # 检查 Docker Compose 是否安装
    if command -v docker-compose >/dev/null 2>&1; then
        echo "Docker Compose 已安装，版本信息："
        docker-compose --version
    else
        echo "Docker Compose 未安装。"
    fi
}

# 函数：启动多个容器
start_containers() {
    list_all_containers
    read -p "请输入要启动的容器名称或ID（多个用逗号分隔）： " containers_input
    IFS=',' read -ra containers <<< "$containers_input"

    for container in "${containers[@]}"; do
        container=$(echo "$container" | xargs) # 去除空格
        if [ -z "$container" ]; then
            continue
        fi
        if docker ps -a --format '{{.Names}} {{.ID}}' | grep -w "$container" >/dev/null 2>&1; then
            docker start "$container"
            echo "容器 '$container' 已启动。"
        else
            echo "未找到容器 '$container'。"
        fi
    done
}

# 函数：停止多个容器
stop_containers() {
    list_running_containers
    read -p "请输入要停止的容器名称或ID（多个用逗号分隔）： " containers_input
    IFS=',' read -ra containers <<< "$containers_input"

    for container in "${containers[@]}"; do
        container=$(echo "$container" | xargs) # 去除空格
        if [ -z "$container" ]; then
            continue
        fi
        if docker ps --format '{{.Names}} {{.ID}}' | grep -w "$container" >/dev/null 2>&1; then
            docker stop "$container"
            echo "容器 '$container' 已停止。"
        else
            echo "未找到运行中的容器 '$container'。"
        fi
    done
}

# 函数：重启多个容器
restart_containers() {
    list_all_containers
    read -p "请输入要重启的容器名称或ID（多个用逗号分隔）： " containers_input
    IFS=',' read -ra containers <<< "$containers_input"

    for container in "${containers[@]}"; do
        container=$(echo "$container" | xargs) # 去除空格
        if [ -z "$container" ]; then
            continue
        fi
        if docker ps -a --format '{{.Names}} {{.ID}}' | grep -w "$container" >/dev/null 2>&1; then
            docker restart "$container"
            echo "容器 '$container' 已重启。"
        else
            echo "未找到容器 '$container'。"
        fi
    done
}

# 函数：删除多个容器
delete_containers() {
    list_all_containers
    read -p "请输入要删除的容器名称或ID（多个用逗号分隔）： " containers_input
    IFS=',' read -ra containers <<< "$containers_input"

    # 收集有效的容器列表
    declare -a valid_containers=()
    for container in "${containers[@]}"; do
        container=$(echo "$container" | xargs) # 去除空格
        if [ -z "$container" ]; then
            continue
        fi
        if docker ps -a --format '{{.Names}} {{.ID}}' | grep -w "$container" >/dev/null 2>&1; then
            valid_containers+=("$container")
        else
            echo "未找到容器 '$container'。"
        fi
    done

    if [ ${#valid_containers[@]} -eq 0 ]; then
        echo "没有有效的容器可删除。"
        return
    fi

    echo "将要删除的容器列表："
    for vc in "${valid_containers[@]}"; do
        echo " - $vc"
    done

    read -p "确认删除上述容器吗？ (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for vc in "${valid_containers[@]}"; do
            docker rm -f "$vc"
            echo "容器 '$vc' 已删除。请注意，删除后需要重新手动配置容器。"
        done
    else
        echo "取消删除操作。"
    fi
}

# 函数：查询运行的容器
list_running_containers() {
    echo "正在运行的容器列表："
    docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"
}

# 函数：查询所有容器
list_all_containers() {
    echo "所有容器列表："
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"
}

# 函数：管理容器操作
manage_containers() {
    while true; do
        show_container_menu
        read -p "请输入你的选择 [0-5]: " choice
        case $choice in
            1)
                start_containers
                ;;
            2)
                stop_containers
                ;;
            3)
                restart_containers
                ;;
            4)
                delete_containers
                ;;
            5)
                list_running_containers
                ;;
            0)
                break
                ;;
            *)
                echo "无效的选择，请输入 0-5 之间的数字。"
                ;;
        esac
        echo ""
    done
}

# 函数：查询所有镜像
list_images() {
    echo "所有镜像列表："
    docker images --format "table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}"
}

# 函数：拉取指定镜像
pull_image() {
    read -p "请输入要拉取的镜像名称（例如 nginx）： " image
    if [ -z "$image" ]; then
        echo "镜像名称不能为空。"
        return
    fi

    read -p "请输入要拉取的标签（例如 latest，留空则默认使用 latest）： " tag
    tag=${tag:-latest}

    echo "正在拉取镜像 ${image}:${tag} ..."
    if docker pull "${image}:${tag}"; then
        echo "镜像 ${image}:${tag} 已成功拉取。"
    else
        echo "错误：无法拉取镜像 ${image}:${tag}。请核实镜像名称和标签是否正确，然后重试。"
    fi
}

# 函数：升级多个镜像
upgrade_image() {
    list_images
    read -p "请输入要升级的镜像名称（例如 nginx），多个用逗号分隔： " images_input
    IFS=',' read -ra images <<< "$images_input"

    for image_entry in "${images[@]}"; do
        image_entry=$(echo "$image_entry" | xargs) # 去除空格
        if [ -z "$image_entry" ]; then
            continue
        fi

        # 分离镜像名称和标签
        if [[ "$image_entry" == *":"* ]]; then
            image=$(echo "$image_entry" | cut -d':' -f1)
            tag=$(echo "$image_entry" | cut -d':' -f2)
        else
            image="$image_entry"
            tag="latest"
        fi

        echo "正在升级镜像 ${image}:${tag} ..."
        if docker pull "${image}:${tag}"; then
            echo "镜像 ${image}:${tag} 已升级。"
        else
            echo "错误：无法升级镜像 ${image}:${tag}。请核实镜像名称和标签是否正确，然后重试。"
        fi
    done
}

# 函数：删除多个镜像版本 (通过 IMAGE ID)
delete_image_versions() {
    list_images
    read -p "请输入要删除的镜像 IMAGE ID（多个用逗号分隔）： " image_ids_input
    IFS=',' read -ra image_ids <<< "$image_ids_input"

    # 收集有效的镜像ID列表
    declare -a valid_image_ids=()
    for image_id in "${image_ids[@]}"; do
        image_id=$(echo "$image_id" | xargs) # 去除空格
        if [ -z "$image_id" ]; then
            continue
        fi

        # 检查 IMAGE ID 是否存在
        if docker images --format '{{.ID}}' | grep -w "^${image_id}" >/dev/null 2>&1; then
            valid_image_ids+=("$image_id")
        else
            echo "未找到镜像 ID '$image_id'。"
        fi
    done

    if [ ${#valid_image_ids[@]} -eq 0 ]; then
        echo "没有有效的镜像 ID 可删除。"
        return
    fi

    echo "将要删除的镜像 ID 列表："
    for vid in "${valid_image_ids[@]}"; do
        echo " - $vid"
    done

    read -p "确认删除上述镜像吗？ (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for vid in "${valid_image_ids[@]}"; do
            docker rmi "$vid"
            echo "镜像 ID '$vid' 已删除。"
        done
    else
        echo "取消删除操作。"
    fi
}

# 函数：管理镜像操作
manage_images() {
    while true; do
        show_image_menu
        read -p "请输入你的选择 [0-4]: " choice
        case $choice in
            1)
                list_images
                ;;
            2)
                pull_image
                ;;
            3)
                upgrade_image
                ;;
            4)
                delete_image_versions
                ;;
            0)
                break
                ;;
            *)
                echo "无效的选择，请输入 0-4 之间的数字。"
                ;;
        esac
        echo ""
    done
}

# 函数：退出脚本
exit_script() {
    echo "退出脚本。"
    exit 0
}

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户或使用 sudo 运行此脚本。"
    exit 1
fi

# 检测操作系统
detect_os

# 验证是否支持当前操作系统
if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    echo "当前操作系统不受支持。本脚本仅支持 Ubuntu 和 Debian。"
    exit 1
fi

# 检查 Docker 仓库是否存在
REPO_URL="https://download.docker.com/linux/${OS}/dists/${VERSION_CODENAME}/stable/"
echo "正在检查 Docker 仓库是否存在： $REPO_URL"

if ! curl --head --silent --fail "$REPO_URL" >/dev/null; then
    echo "错误： Docker 仓库不存在或不可访问。请检查操作系统类型和版本代号。"
    echo "请确保 Docker 支持您的操作系统版本。"
    exit 1
fi

# 主循环
while true; do
    show_menu
    read -p "请输入你的选择 [0-5]: " choice
    case $choice in
        1)
            install_docker
            ;;
        2)
            uninstall_docker
            ;;
        3)
            check_status
            ;;
        4)
            manage_containers
            ;;
        5)
            manage_images
            ;;
        0)
            exit_script
            ;;
        *)
            echo "无效的选择，请输入 0-5 之间的数字。"
            ;;
    esac
    echo ""
done
