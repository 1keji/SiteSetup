#!/bin/bash

# 文件存储已安装应用列表
INSTALLED_APPS_FILE="$HOME/.installed_apps"

# 初始化已安装应用文件
if [ ! -f "$INSTALLED_APPS_FILE" ]; then
    touch "$INSTALLED_APPS_FILE"
fi

# 检测系统的包管理器
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PM="apt"
    elif command -v yum &> /dev/null; then
        PM="yum"
    elif command -v dnf &> /dev/null; then
        PM="dnf"
    elif command -v pacman &> /dev/null; then
        PM="pacman"
    else
        echo "不支持的包管理器。"
        exit 1
    fi
}

# 安装应用
install_apps() {
    read -p "请输入需要安装的应用名称，用逗号分隔： " apps_input
    IFS=',' read -ra APPS <<< "$apps_input"
    for app in "${APPS[@]}"; do
        app=$(echo "$app" | xargs) # 去除空格
        if grep -qw "$app" "$INSTALLED_APPS_FILE"; then
            echo "应用 '$app' 已经安装。"
            continue
        fi
        echo "正在安装 '$app'..."
        case "$PM" in
            apt)
                sudo apt-get update
                sudo apt-get install -y "$app"
                ;;
            yum)
                sudo yum install -y "$app"
                ;;
            dnf)
                sudo dnf install -y "$app"
                ;;
            pacman)
                sudo pacman -Sy --noconfirm "$app"
                ;;
            *)
                echo "不支持的包管理器。"
                ;;
        esac
        if [ $? -eq 0 ]; then
            echo "$app" >> "$INSTALLED_APPS_FILE"
            echo "应用 '$app' 安装成功。"
        else
            echo "应用 '$app' 安装失败。"
        fi
    done
}

# 查看已安装应用
view_installed_apps() {
    if [ ! -s "$INSTALLED_APPS_FILE" ]; then
        echo "没有通过脚本安装的应用。"
    else
        echo "已安装的应用列表："
        cat "$INSTALLED_APPS_FILE"
    fi
}

# 升级应用
upgrade_app() {
    view_installed_apps
    read -p "请输入需要升级的应用名称： " app
    if ! grep -qw "$app" "$INSTALLED_APPS_FILE"; then
        echo "应用 '$app' 不在已安装列表中。"
        return
    fi
    echo "正在升级 '$app'..."
    case "$PM" in
        apt)
            sudo apt-get update
            sudo apt-get install --only-upgrade -y "$app"
            ;;
        yum)
            sudo yum update -y "$app"
            ;;
        dnf)
            sudo dnf upgrade -y "$app"
            ;;
        pacman)
            sudo pacman -Syu --noconfirm "$app"
            ;;
        *)
            echo "不支持的包管理器。"
            ;;
    esac
    if [ $? -eq 0 ]; then
        echo "应用 '$app' 升级成功。"
    else
        echo "应用 '$app' 升级失败。"
    fi
}

# 卸载应用
uninstall_app() {
    view_installed_apps
    read -p "请输入需要卸载的应用名称： " app
    if ! grep -qw "$app" "$INSTALLED_APPS_FILE"; then
        echo "应用 '$app' 不在已安装列表中。"
        return
    fi
    echo "正在卸载 '$app'..."
    case "$PM" in
        apt)
            sudo apt-get remove -y "$app"
            ;;
        yum)
            sudo yum remove -y "$app"
            ;;
        dnf)
            sudo dnf remove -y "$app"
            ;;
        pacman)
            sudo pacman -Rns --noconfirm "$app"
            ;;
        *)
            echo "不支持的包管理器。"
            ;;
    esac
    if [ $? -eq 0 ]; then
        grep -vw "$app" "$INSTALLED_APPS_FILE" > "${INSTALLED_APPS_FILE}.tmp"
        mv "${INSTALLED_APPS_FILE}.tmp" "$INSTALLED_APPS_FILE"
        echo "应用 '$app' 卸载成功。"
    else
        echo "应用 '$app' 卸载失败。"
    fi
}

# 查询指定应用
query_app() {
    read -p "请输入要查询的应用名称： " app
    if grep -qw "$app" "$INSTALLED_APPS_FILE"; then
        echo "应用 '$app' 已安装。请选择操作："
        echo "1. 更新应用"
        echo "2. 卸载应用"
        echo "0. 返回上级目录"
        read -p "请输入您的选择：" q_choice
        case "$q_choice" in
            1)
                echo "正在升级 '$app'..."
                case "$PM" in
                    apt)
                        sudo apt-get update
                        sudo apt-get install --only-upgrade -y "$app"
                        ;;
                    yum)
                        sudo yum update -y "$app"
                        ;;
                    dnf)
                        sudo dnf upgrade -y "$app"
                        ;;
                    pacman)
                        sudo pacman -Syu --noconfirm "$app"
                        ;;
                    *)
                        echo "不支持的包管理器。"
                        ;;
                esac
                if [ $? -eq 0 ]; then
                    echo "应用 '$app' 升级成功。"
                else
                    echo "应用 '$app' 升级失败。"
                fi
                ;;
            2)
                echo "正在卸载 '$app'..."
                case "$PM" in
                    apt)
                        sudo apt-get remove -y "$app"
                        ;;
                    yum)
                        sudo yum remove -y "$app"
                        ;;
                    dnf)
                        sudo dnf remove -y "$app"
                        ;;
                    pacman)
                        sudo pacman -Rns --noconfirm "$app"
                        ;;
                    *)
                        echo "不支持的包管理器。"
                        ;;
                esac
                if [ $? -eq 0 ]; then
                    grep -vw "$app" "$INSTALLED_APPS_FILE" > "${INSTALLED_APPS_FILE}.tmp"
                    mv "${INSTALLED_APPS_FILE}.tmp" "$INSTALLED_APPS_FILE"
                    echo "应用 '$app' 卸载成功。"
                else
                    echo "应用 '$app' 卸载失败。"
                fi
                ;;
            0)
                ;;
            *)
                echo "无效的选择，请重新输入。"
                ;;
        esac
    else
        echo "应用 '$app' 未安装。"
    fi
}

# 升级系统
upgrade_system() {
    echo "开始升级系统..."
    case "$PM" in
        apt)
            sudo apt-get update && sudo apt-get upgrade -y
            ;;
        yum)
            sudo yum update -y
            ;;
        dnf)
            sudo dnf upgrade -y
            ;;
        pacman)
            sudo pacman -Syu --noconfirm
            ;;
        *)
            echo "不支持的包管理器。"
            ;;
    esac
    if [ $? -eq 0 ]; then
        echo "系统升级成功。"
    else
        echo "系统升级失败。"
    fi
}

# 管理应用菜单
manage_apps() {
    while true; do
        echo "-------------------------"
        echo "管理应用选项："
        echo "1. 查看已安装应用"
        echo "2. 升级应用"
        echo "3. 卸载应用"
        echo "4. 查询指定应用"
        echo "0. 返回主菜单"
        read -p "请输入您的选择：" choice
        case "$choice" in
            1)
                view_installed_apps
                ;;
            2)
                upgrade_app
                ;;
            3)
                uninstall_app
                ;;
            4)
                query_app
                ;;
            0)
                break
                ;;
            *)
                echo "无效的选择，请重新输入。"
                ;;
        esac
        read -p "按回车键继续..."
    done
}

# 显示品牌标识
show_branding() {
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           一点科技 应用安装与管理脚本         ║"
    echo "╠═══════════════════════════════════════════════╣"
    echo "║ 作者：一点科技                                ║"
    echo "║ 网站：https://1keji.net                       ║"
    echo "║ YouTube：https://www.youtube.com/@1keji_net   ║"
    echo "╚═══════════════════════════════════════════════╝"
}

# 主菜单
main_menu() {
    detect_package_manager
    while true; do
        clear
        show_branding
        echo "========================="
        echo "  应用安装与管理脚本"
        echo "========================="
        echo "1. 安装应用"
        echo "2. 管理应用"
        echo "3. 升级系统"
        echo "0. 退出脚本"
        read -p "请输入您的选择：" main_choice
        case "$main_choice" in
            1)
                install_apps
                ;;
            2)
                manage_apps
                ;;
            3)
                upgrade_system
                ;;
            0)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效的选择，请重新输入。"
                ;;
        esac
        read -p "按回车键继续..."
    done
}

# 执行主菜单
main_menu
