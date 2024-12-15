#!/bin/bash

# 确保脚本以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以 root 权限运行"
   exit 1
fi

# 定义默认禁用的高危函数
DEFAULT_DISABLED_FUNCTIONS=("exec" "passthru" "shell_exec" "system" "proc_open" "popen" "pcntl_exec" "putenv" "getenv" "curl_exec" "curl_multi_exec" "parse_ini_file" "show_source" "proc_get_status" "proc_terminate" "proc_nice" "dl")

# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo "无法检测操作系统。"
        exit 1
    fi
}

# 添加相应的 PHP 仓库
add_repository() {
    case "$OS" in
        ubuntu)
            echo "检测到 Ubuntu 系统，添加 ondrej/php PPA..."
            if ! grep -q "^deb .*$" /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list 2>/dev/null; then
                apt update
                apt install -y software-properties-common
                add-apt-repository ppa:ondrej/php -y
                if [[ $? -ne 0 ]]; then
                    echo "添加 ondrej/php PPA 失败。请手动检查。"
                    exit 1
                fi
                apt update
            else
                echo "ondrej/php PPA 已存在，跳过添加。"
            fi
            ;;
        debian)
            echo "检测到 Debian 系统，添加 Debian Sury 仓库..."
            if ! grep -q "^deb .*$" /etc/apt/sources.list.d/php.list 2>/dev/null; then
                apt update
                apt install -y apt-transport-https lsb-release ca-certificates wget gnupg
                wget -qO- https://packages.sury.org/php/apt.gpg | gpg --dearmor | tee /etc/apt/keyrings/php-archive-keyring.gpg >/dev/null
                echo "deb [signed-by=/etc/apt/keyrings/php-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
                apt update
            else
                echo "Debian Sury 仓库已存在，跳过添加。"
            fi
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
}

# 获取可用的 PHP 版本
get_available_php_versions() {
    available_versions=("7.4" "8.0" "8.1" "8.2" "8.3")
}

# 获取已安装的 PHP 版本
get_installed_php_versions() {
    installed_versions=()
    for ver in "${available_versions[@]}"; do
        if dpkg -l | grep -q "php$ver " ; then
            installed_versions+=("$ver")
        fi
    done
}

# 主菜单
main_menu() {
    while true; do
        echo "=============================="
        echo "        PHP 管理脚本"
        echo "=============================="
        echo "1. 安装 PHP"
        echo "2. 管理 PHP"
        echo "3. 卸载 PHP 版本"
        echo "0. 退出脚本"
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
    echo "$(( ${#available_versions[@]} +1 ))). 返回主菜单"
    read -p "请选择要安装的 PHP 版本（可以多选，用空格分隔）: " -a selections
    for sel in "${selections[@]}"; do
        if [[ "$sel" -ge 1 && "$sel" -le "${#available_versions[@]}" ]]; then
            version="${available_versions[$((sel-1))]}"
            if dpkg -l | grep -q "php$version " ; then
                echo "PHP $version 已经安装，跳过。"
            else
                echo "正在安装 PHP $version..."
                apt install -y php$version php$version-cli php$version-fpm
                if [[ $? -eq 0 ]]; then
                    echo "PHP $version 安装成功。"
                    disable_default_functions "$version"
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

# 禁用默认高危函数
disable_default_functions() {
    local version="$1"
    local php_ini
    php_ini=$(get_php_ini "$version")
    if [[ -z "$php_ini" ]]; then
        echo "未找到 PHP $version 的 php.ini 文件，无法禁用函数。"
        return
    fi

    echo "正在禁用默认高危函数..."
    
    # 获取当前禁用的函数
    current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')

    for func in "${DEFAULT_DISABLED_FUNCTIONS[@]}"; do
        if echo "$current_disabled" | grep -qw "$func"; then
            echo "函数 $func 已经被禁用，跳过。"
        else
            if grep -q "^disable_functions" "$php_ini"; then
                # Append function
                sed -i "/^disable_functions\s*=/ s/$/,${func}/" "$php_ini"
            else
                # Add disable_functions line
                echo "disable_functions = ${func}" >> "$php_ini"
            fi
            echo "函数 $func 已被禁用。"
            # Update current_disabled variable
            current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')
        fi
    done

    # 重启 PHP-FPM 服务
    restart_php_fpm "$version"
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
        php_manage_menu "$version"
    elif [[ "$sel" -eq $(( ${#installed_versions[@]} +1 )) ]]; then
        return
    else
        echo "无效的选择。"
    fi
}

# PHP 管理子菜单
php_manage_menu() {
    local version="$1"
    while true; do
        echo "=============================="
        echo "管理 PHP $version"
        echo "=============================="
        echo "1. 安装扩展"
        echo "2. 卸载扩展"
        echo "3. 禁用函数"
        echo "4. 解除禁用函数"
        echo "0. 返回上级菜单"
        echo "=============================="
        read -p "请输入选项: " choice
        case $choice in
            0)
                return
                ;;
            1)
                install_php_extensions "$version"
                ;;
            2)
                uninstall_php_extensions "$version"
                ;;
            3)
                disable_php_functions "$version"
                ;;
            4)
                enable_php_functions "$version"
                ;;
            *)
                echo "无效的选项，请重新选择。"
                ;;
        esac
    done
}

# 安装 PHP 扩展
install_php_extensions() {
    local version="$1"
    echo "管理 PHP $version 的扩展 - 安装扩展"
    read -p "请输入要安装的扩展（用逗号分隔）: " extensions_input
    IFS=',' read -ra extensions <<< "$extensions_input"
    installed=()
    skipped=()
    for ext in "${extensions[@]}"; do
        ext_trimmed=$(echo "$ext" | xargs) # 去除空格
        if dpkg -l | grep -q "php$version-$ext_trimmed " ; then
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

# 卸载 PHP 扩展
uninstall_php_extensions() {
    local version="$1"
    echo "管理 PHP $version 的扩展 - 卸载扩展"
    read -p "请输入要卸载的扩展（用逗号分隔）: " extensions_input
    IFS=',' read -ra extensions <<< "$extensions_input"
    uninstalled=()
    skipped=()
    for ext in "${extensions[@]}"; do
        ext_trimmed=$(echo "$ext" | xargs) # 去除空格
        if dpkg -l | grep -q "php$version-$ext_trimmed " ; then
            echo "正在卸载扩展: $ext_trimmed ..."
            apt purge -y "php$version-$ext_trimmed"
            if [[ $? -eq 0 ]]; then
                uninstalled+=("$ext_trimmed")
            else
                echo "卸载扩展 $ext_trimmed 失败。"
            fi
        else
            skipped+=("$ext_trimmed")
        fi
    done
    echo "卸载完成。"
    if [[ ${#uninstalled[@]} -gt 0 ]]; then
        echo "已卸载的扩展: ${uninstalled[*]}"
    fi
    if [[ ${#skipped[@]} -gt 0 ]]; then
        echo "已跳过的扩展（未安装）: ${skipped[*]}"
    fi
}

# 禁用 PHP 函数
disable_php_functions() {
    local version="$1"
    echo "管理 PHP $version 的函数 - 禁用函数"
    
    php_ini=$(get_php_ini "$version")
    if [[ -z "$php_ini" ]]; then
        echo "未找到 PHP $version 的 php.ini 文件。"
        return
    fi
    
    # 获取当前禁用的函数
    current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')
    
    if [[ -n "$current_disabled" ]]; then
        echo "当前已禁用的函数：$current_disabled"
    else
        echo "当前没有禁用任何函数。"
    fi

    echo
    read -p "请输入要禁用的函数（用逗号分隔）: " functions_input
    IFS=',' read -ra functions <<< "$functions_input"
    
    for func in "${functions[@]}"; do
        func_trimmed=$(echo "$func" | xargs) # 去除空格
        if echo "$current_disabled" | grep -qw "$func_trimmed"; then
            echo "函数 $func_trimmed 已经被禁用，跳过。"
        else
            if grep -q "^disable_functions" "$php_ini"; then
                if [[ -z "$current_disabled" ]]; then
                    new_disabled="$func_trimmed"
                else
                    new_disabled="$current_disabled,$func_trimmed"
                fi
                sed -i "s/^disable_functions\s*=.*/disable_functions = $new_disabled/" "$php_ini"
            else
                echo "disable_functions = $func_trimmed" >> "$php_ini"
            fi
            echo "函数 $func_trimmed 已被禁用。"
            # 更新当前禁用的函数变量
            current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')
        fi
    done
    
    # 重启 PHP-FPM 服务
    restart_php_fpm "$version"
}

# 解除禁用 PHP 函数
enable_php_functions() {
    local version="$1"
    echo "管理 PHP $version 的函数 - 解除禁用函数"
    
    php_ini=$(get_php_ini "$version")
    if [[ -z "$php_ini" ]]; then
        echo "未找到 PHP $version 的 php.ini 文件。"
        return
    fi
    
    # 获取当前禁用的函数
    current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')
    
    if [[ -n "$current_disabled" ]]; then
        echo "当前已禁用的函数：$current_disabled"
    else
        echo "当前没有禁用任何函数。"
    fi
    
    echo
    read -p "请输入要解除禁用的函数（用逗号分隔）: " functions_input
    IFS=',' read -ra functions <<< "$functions_input"
    
    for func in "${functions[@]}"; do
        func_trimmed=$(echo "$func" | xargs) # 去除空格
        if echo "$current_disabled" | grep -qw "$func_trimmed"; then
            # Remove the function from the disable_functions list
            new_disabled=$(echo "$current_disabled" | sed "s/\b$func_trimmed\b//g" | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')
            if [[ -z "$new_disabled" ]]; then
                # 删除 disable_functions 行
                sed -i "/^disable_functions\s*=/d" "$php_ini"
                echo "函数 $func_trimmed 已被解除禁用。"
                current_disabled=""
            else
                sed -i "s/^disable_functions\s*=.*/disable_functions = $new_disabled/" "$php_ini"
                echo "函数 $func_trimmed 已被解除禁用。"
                current_disabled="$new_disabled"
            fi
        else
            echo "函数 $func_trimmed 未被禁用，跳过。"
        fi
    done
    
    # 重启 PHP-FPM 服务
    restart_php_fpm "$version"
}

# 获取 PHP.ini 文件路径
get_php_ini() {
    local version="$1"
    # 尝试通过 php -i 获取 ini 文件路径
    php_executable=$(which php"$version")
    if [[ -z "$php_executable" ]]; then
        echo ""
        return
    fi
    php_ini_path=$("$php_executable" -i | grep "Loaded Configuration File" | awk '{print $5}')
    echo "$php_ini_path"
}

# 重启 PHP-FPM 服务
restart_php_fpm() {
    local version="$1"
    # 判断系统是否使用 systemd
    if systemctl list-unit-files | grep -q "php$version-fpm.service"; then
        systemctl restart "php$version-fpm"
        if [[ $? -eq 0 ]]; then
            echo "PHP $version-FPM 服务已重启。"
        else
            echo "重启 PHP $version-FPM 服务失败。"
        fi
    else
        # 尝试使用 service 命令
        service "php$version-fpm" restart
        if [[ $? -eq 0 ]]; then
            echo "PHP $version-FPM 服务已重启。"
        else
            echo "重启 PHP $version-FPM 服务失败。"
        fi
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
    detect_os
    add_repository
}

# 执行初始化并进入主菜单
initialize
main_menu
