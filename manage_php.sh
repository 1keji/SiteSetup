#!/bin/bash

# 确保脚本以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以 root 权限运行" 
   exit 1
fi

# 添加 ondrej/php PPA
add_ppa() {
    if ! grep -q "^deb .*$" /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list 2>/dev/null; then
        apt update
        apt install -y software-properties-common
        add-apt-repository ppa:ondrej/php -y
        apt update
    fi
}

# 获取可用的 PHP 版本
get_available_php_versions() {
    available_versions=("7.4" "8.0" "8.1" "8.2")
}

# 获取已安装的 PHP 版本
get_installed_php_versions() {
    installed_versions=()
    for ver in "${available_versions[@]}"; do
        if dpkg -l | grep -q "php$ver "; then
            installed_versions+=("$ver")
        fi
    done
}

# 主菜单
main_menu() {
    while true; do
        echo "=============================="
        echo " PHP 管理脚本"
        echo "=============================="
        echo "0. 退出脚本"
        echo "1. 安装 PHP"
        echo "2. 管理 PHP"
        echo "3. 卸载 PHP 版本"
        echo "=============================="
        read -p "请输入选项: " choice
        case $choice in
            0)
                echo "退出脚本。"
                exit 0
                ;;
            1)
                install_php_menu
                ;;
            2)
                manage_php_menu
                ;;
            3)
                uninstall_php_menu
                ;;
            *)
                echo "无效的选项，请重新选择。"
                ;;
        esac
    done
}

# 安装 PHP 菜单
install_php_menu() {
    get_available_php_versions
    echo "可用的 PHP 版本:"
    for i in "${!available_versions[@]}"; do
        echo "$((i+1)). PHP ${available_versions[i]}"
    done
    echo "$(( ${#available_versions[@]} +1 )). 返回主菜单"
    read -p "请选择要安装的 PHP 版本（可以多选，用空格分隔）: " -a selections
    for sel in "${selections[@]}"; do
        if [[ "$sel" -ge 1 && "$sel" -le "${#available_versions[@]}" ]]; then
            version="${available_versions[$((sel-1))]}"
            if dpkg -l | grep -q "php$version "; then
                echo "PHP $version 已经安装，跳过。"
            else
                echo "正在安装 PHP $version..."
                apt install -y php$version php$version-cli php$version-fpm
                if [[ $? -eq 0 ]]; then
                    echo "PHP $version 安装成功。"
                else
                    echo "PHP $version 安装失败。"
                fi
            fi
        elif [[ "$sel" -eq $(( ${#available_versions[@]} +1 )) ]]; then
            return
        else
            echo "无效的选择: $sel，跳过。"
        fi
    done
}

# 管理 PHP 菜单
manage_php_menu() {
    get_available_php_versions
    get_installed_php_versions
    if [[ ${#installed_versions[@]} -eq 0 ]]; then
        echo "没有已安装的 PHP 版本。请先安装 PHP。"
        return
    fi
    echo "已安装的 PHP 版本:"
    for i in "${!installed_versions[@]}"; do
        echo "$((i+1)). PHP ${installed_versions[i]}"
    done
    echo "$(( ${#installed_versions[@]} +1 ))). 返回主菜单"
    read -p "请选择要管理的 PHP 版本: " sel
    if [[ "$sel" -ge 1 && "$sel" -le "${#installed_versions[@]}" ]]; then
        version="${installed_versions[$((sel-1))]}"
        manage_php_extensions "$version"
    elif [[ "$sel" -eq $(( ${#installed_versions[@]} +1 )) ]]; then
        return
    else
        echo "无效的选择。"
    fi
}

# 管理 PHP 扩展
manage_php_extensions() {
    local version="$1"
    echo "管理 PHP $version 的扩展"
    read -p "请输入要安装的扩展（用逗号分隔）: " extensions_input
    IFS=',' read -ra extensions <<< "$extensions_input"
    installed=()
    skipped=()
    for ext in "${extensions[@]}"; do
        ext_trimmed=$(echo "$ext" | xargs) # 去除空格
        if dpkg -l | grep -q "php$version-$ext_trimmed "; then
            skipped+=("$ext_trimmed")
        else
            echo "正在安装扩展: $ext_trimmed ..."
            apt install -y "php$version-$ext_trimmed"
            if [[ $? -eq 0 ]]; then
                installed+=("$ext_trimmed")
            else
                echo "安装扩展 $ext_trimmed 失败。"
            fi
        fi
    done
    echo "安装完成。"
    if [[ ${#installed[@]} -gt 0 ]]; then
        echo "已安装的扩展: ${installed[*]}"
    fi
    if [[ ${#skipped[@]} -gt 0 ]]; then
        echo "已跳过的扩展（已存在）: ${skipped[*]}"
    fi
}

# 卸载 PHP 菜单
uninstall_php_menu() {
    get_available_php_versions
    get_installed_php_versions
    if [[ ${#installed_versions[@]} -eq 0 ]]; then
        echo "没有已安装的 PHP 版本。"
        return
    fi
    echo "已安装的 PHP 版本:"
    for i in "${!installed_versions[@]}"; do
        echo "$((i+1)). PHP ${installed_versions[i]}"
    done
    echo "$(( ${#installed_versions[@]} +1 ))). 返回主菜单"
    read -p "请选择要卸载的 PHP 版本: " sel
    if [[ "$sel" -ge 1 && "$sel" -le "${#installed_versions[@]}" ]]; then
        version="${installed_versions[$((sel-1))]}"
        read -p "确定要卸载 PHP $version 吗？(y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo "正在卸载 PHP $version ..."
            apt purge -y "php$version" "php$version-cli" "php$version-fpm"
            apt autoremove -y
            if [[ $? -eq 0 ]]; then
                echo "PHP $version 已成功卸载。"
            else
                echo "卸载 PHP $version 失败。"
            fi
        else
            echo "取消卸载。"
        fi
    elif [[ "$sel" -eq $(( ${#installed_versions[@]} +1 )) ]]; then
        return
    else
        echo "无效的选择。"
    fi
}

# 初始化
initialize() {
    add_ppa
}

# 执行初始化并进入主菜单
initialize
main_menu
