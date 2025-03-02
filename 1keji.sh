#!/bin/bash

# 设置快捷命令管理脚本URL
CMD_SCRIPT_URL="https://sh.1keji.net/f/L91iQ/cmd_manager.sh"

# 如果没有安装curl，则尝试自动安装
if ! command -v curl &>/dev/null; then
    echo "curl 未安装，正在尝试自动安装..."
    if [ -x "$(command -v apt-get)" ]; then
        apt-get update && apt-get install -y curl
    elif [ -x "$(command -v yum)" ]; then
        yum install -y curl
    else
        echo "无法确定包管理器，请手动安装curl"
        exit 1
    fi
fi

# 获取脚本的路径
SCRIPT_PATH=$(readlink -f "$0")

# 检查是否是第一次运行，只在第一次运行时添加快捷命令
SHORTCUT_MARKER="$HOME/.keji_shortcut_added"
if [ ! -f "$SHORTCUT_MARKER" ] && [ -f ~/.bashrc ]; then
    echo "首次运行，正在添加快捷命令 'keji' ..."
    # 下载并执行快捷命令管理脚本以添加快捷命令
    bash <(curl -sL "$CMD_SCRIPT_URL") "$SCRIPT_PATH" "keji" "add"
    # 创建标记文件，表示已添加过快捷命令
    touch "$SHORTCUT_MARKER"
fi

# 自动生成的统一脚本

while true; do
    clear
    echo -e "\033[1;32m╔══════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;32m║\033[0m\033[1;37m          一点科技 综合 管理脚本          \033[0m\033[1;32m║\033[0m"
    echo -e "\033[1;32m╠══════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;32m║\033[0m\033[1;37m 作者：一点科技                           \033[0m\033[1;32m║\033[0m"
    echo -e "\033[1;32m║\033[0m\033[1;37m 频道：https://www.youtube.com/@1keji_net \033[0m\033[1;32m║\033[0m"
    echo -e "\033[1;32m║\033[0m\033[1;37m TG群：  https://t.me/tg_1keji            \033[0m\033[1;32m║\033[0m"
    echo -e "\033[1;32m║\033[0m\033[1;37m 网站：  https://1keji.net                \033[0m\033[1;32m║\033[0m"
    echo -e "\033[1;32m╚══════════════════════════════════════════╝\033[0m"

    echo -e "\033[1;33m请选择一个功能：\033[0m"
    echo -e "\033[1;37m1: nginx管理\033[0m"
    echo -e "\033[1;37m2: php管理\033[0m"
    echo -e "\033[1;37m3: docker管理\033[0m"
    echo -e "\033[1;37m4: mysql管理（基于docker）\033[0m"
    echo -e "\033[1;37m5: ssl证书下载\033[0m"
    echo -e "\033[1;37m6: 备份功能\033[0m"
    echo -e "\033[1;37m8: app管理\033[0m"
    echo -e "\033[1;37m9: BBR\033[0m"
    echo -e "\033[1;32m----------------------------------------\033[0m"
    echo -e "\033[1;37m11: cloudreve网盘\033[0m"
    echo -e "\033[1;37m12: 哪吒监控（综合管理）\033[0m"
    echo -e "\033[1;32m----------------------------------------\033[0m"
    echo -e "\033[1;37m41: ssh防护\033[0m"
    echo -e "\033[1;37m42: 流量控制\033[0m"
    echo -e "\033[1;32m----------------------------------------\033[0m"
    echo -e "\033[1;37m101: dd系统\033[0m"
    echo -e "\033[1;32m----------------------------------------\033[0m"
    echo -e "\033[1;37mcmd: 管理快捷命令\033[0m"
    echo -e "\033[1;37m0: 退出\033[0m"
    read -p "请输入对应的数字或命令: " choice
    case $choice in
        1 )
            bash <(curl -sL "https://sh.1keji.net/f/4Oil/nginx_1kejiv1.sh")
            continue
            ;;
        2 )
            bash <(curl -sL "https://sh.1keji.net/f/vlsA/manage_php.sh")
            continue
            ;;
        3 )
            bash <(curl -sL "https://sh.1keji.net/f/w0ty/docker_1keji.sh")
            continue
            ;;
        4 )
            bash <(curl -sL "https://sh.1keji.net/f/x2ux/manage_mysql.sh")
            continue
            ;;
        5 )
            wget -O ssl_get.sh "https://sh.1keji.net/f/jESR/ssl_get.sh" && chmod +x ssl_get.sh && ./ssl_get.sh
            continue
            ;;
        6 )
            wget -O bf_1keji.sh "https://sh.1keji.net/f/5Ds6/bf_1keji.sh" && chmod +x bf_1keji.sh && ./bf_1keji.sh
            continue
            ;;
        8 )
            bash <(curl -sL "https://sh.1keji.net/f/65ty/app_manager.sh")
            continue
            ;;
        9 )
            bash <(curl -sL "https://sh.1keji.net/f/znF4/bbr_1keji.sh")
            continue
            ;;
        11 )
            bash <(curl -sL "https://sh.1keji.net/f/QRCo/cloudreve_manager.sh")
            continue
            ;;
        12 )
            bash <(curl -sL "https://sh.1keji.net/f/GzUA/neza_1keji.sh")
            continue
            ;;
        41 )
            bash <(curl -sL "https://sh.1keji.net/f/L1hQ/fail2ban_manager.sh")
            continue
            ;;
        42 )
            bash <(curl -sL "https://sh.1keji.net/f/MXiz/llgk.sh")
            continue
            ;;
        101 )
            bash <(curl -sL "https://sh.1keji.net/f/KEf4/dd_1keji.sh")
            continue
            ;;
        cmd )
            # 调用快捷命令管理脚本
            bash <(curl -sL "$CMD_SCRIPT_URL") "$SCRIPT_PATH" "keji"
            ;;
        0 )
            echo -e "\033[1;31m退出脚本\033[0m"
            break
            ;;
        * )
            echo -e "\033[1;31m无效的选择，请重新输入。\033[0m"
            ;;
    esac
    if [ "$choice" != "0" ]; then
        echo
        read -p "按回车键继续..." 
    fi
done
