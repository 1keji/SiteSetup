#!/bin/bash

# MySQL 管理脚本

# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo "无法检测操作系统类型。"
        exit 1
    fi
}

# 安装依赖项
install_dependencies() {
    echo "安装必要的依赖项..."

    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        sudo apt update
        sudo apt install -y wget lsb-release gnupg
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        if [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
            sudo yum install -y wget
        else
            sudo dnf install -y wget
        fi
    else
        echo "不支持的操作系统。"
        exit 1
    fi
}

# 安装 MySQL
install_mysql() {
    echo "请选择要安装的 MySQL 版本："
    echo "1) MySQL 5.7"
    echo "2) MySQL 8.0"
    read -p "请输入数字选择版本: " version_choice

    case $version_choice in
        1)
            MYSQL_VERSION="5.7"
            ;;
        2)
            MYSQL_VERSION="8.0"
            ;;
        *)
            echo "无效的选择。返回主菜单。"
            return
            ;;
    esac

    echo "选择的 MySQL 版本: $MYSQL_VERSION"

    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        sudo apt update
        sudo apt install -y gnupg
        wget https://dev.mysql.com/get/mysql-apt-config_${MYSQL_VERSION}-1_all.deb
        sudo dpkg -i mysql-apt-config_${MYSQL_VERSION}-1_all.deb
        sudo apt update
        sudo apt install -y mysql-server
        rm mysql-apt-config_${MYSQL_VERSION}-1_all.deb
    elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
        if [[ "$VER" == "8" ]]; then
            sudo dnf install -y https://dev.mysql.com/get/mysql80-community-release-el8-1.noarch.rpm
        elif [[ "$VER" == "7" ]]; then
            sudo yum install -y https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm
        else
            echo "不支持的 CentOS/RHEL 版本。"
            return
        fi

        if [[ "$MYSQL_VERSION" == "5.7" ]]; then
            sudo yum-config-manager --disable mysql80-community
            sudo yum-config-manager --enable mysql57-community
        elif [[ "$MYSQL_VERSION" == "8.0" ]]; then
            sudo yum-config-manager --disable mysql57-community
            sudo yum-config-manager --enable mysql80-community
        fi

        sudo yum install -y mysql-server
    else
        echo "不支持的操作系统。"
        return
    fi

    echo "MySQL $MYSQL_VERSION 安装完成。"

    # 启动并设置 MySQL 开机自启
    sudo systemctl start mysqld
    sudo systemctl enable mysqld

    # 获取临时密码（适用于 MySQL 5.7）
    if [[ "$MYSQL_VERSION" == "5.7" ]]; then
        TEMP_PWD=$(sudo grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
        echo "MySQL 临时密码: $TEMP_PWD"
        echo "请使用以下命令更改密码:"
        echo "sudo mysql_secure_installation"
    fi
}

# 查询 MySQL 状态
query_status() {
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        sudo systemctl status mysql --no-pager
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        sudo systemctl status mysqld --no-pager
    else
        echo "不支持的操作系统。"
    fi
}

# 卸载 MySQL
uninstall_mysql() {
    read -p "请输入确认文字以卸载 MySQL 数据库: " confirm_text

    if [[ "$confirm_text" != "确认卸载mysql数据库" ]]; then
        echo "确认文字不正确，取消卸载。"
        return
    fi

    echo "开始卸载 MySQL..."

    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        sudo systemctl stop mysql
        sudo apt purge -y mysql-server mysql-client mysql-common
        sudo rm -rf /etc/mysql /var/lib/mysql
        sudo apt autoremove -y
        sudo apt autoclean
    elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
        sudo systemctl stop mysqld
        sudo yum remove -y mysql-server
        sudo rm -rf /var/lib/mysql /etc/my.cnf
    else
        echo "不支持的操作系统。"
        return
    fi

    echo "MySQL 已成功卸载。"
}

# 主菜单
main_menu() {
    while true; do
        echo "=============================="
        echo " MySQL 管理脚本"
        echo "=============================="
        echo "1) 安装 MySQL"
        echo "2) 查询数据库状态"
        echo "3) 卸载 MySQL 数据库"
        echo "0) 退出脚本"
        echo "=============================="
        read -p "请输入您的选择: " choice

        case $choice in
            1)
                install_dependencies
                install_mysql
                ;;
            2)
                query_status
                ;;
            3)
                uninstall_mysql
                ;;
            0)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效的选择，请重新输入。"
                ;;
        esac

        echo ""
    done
}

# 执行脚本
detect_os
main_menu
