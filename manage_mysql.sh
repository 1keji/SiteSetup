#!/bin/bash

# 检查是否以root运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root用户或使用sudo运行此脚本。"
  exit
fi

# 更新包列表
update_system() {
    echo "更新系统包列表..."
    apt-get update
}

# 安装必要的依赖项
install_dependencies() {
    echo "安装依赖项..."
    apt-get install -y wget gnupg lsb-release
}

# 安装 MySQL
install_mysql() {
    echo "请选择要安装的 MySQL 版本："
    echo "1. 8.0"
    echo "2. 5.7"
    read -p "请输入选项 (1-2): " version_choice

    case $version_choice in
        1)
            MYSQL_VERSION="8.0"
            ;;
        2)
            MYSQL_VERSION="5.7"
            ;;
        *)
            echo "无效的选项。返回主菜单。"
            return
            ;;
    esac

    echo "安装 MySQL ${MYSQL_VERSION}..."

    # 下载并添加 MySQL APT repository
    wget https://dev.mysql.com/get/mysql-apt-config_${MYSQL_VERSION}-1_all.deb -O /tmp/mysql-apt-config.deb
    dpkg -i /tmp/mysql-apt-config.deb

    # 更新包列表
    apt-get update

    # 安装 MySQL Server
    DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

    # 启动并启用 MySQL 服务
    systemctl start mysql
    systemctl enable mysql

    echo "MySQL ${MYSQL_VERSION} 安装完成。"
}

# 添加数据库
add_database() {
    read -p "请输入要创建的数据库名称: " db_name
    read -p "请输入 MySQL root 用户的密码: " -s root_password
    echo

    mysql -u root -p${root_password} -e "CREATE DATABASE ${db_name};"

    if [ $? -eq 0 ]; then
        echo "数据库 '${db_name}' 创建成功。"
    else
        echo "数据库创建失败。请检查 MySQL 是否已正确安装并且密码正确。"
    fi
}

# 管理数据库
manage_database() {
    read -p "请输入 MySQL root 用户的密码: " -s root_password
    echo

    echo "可用的数据库列表："
    mysql -u root -p${root_password} -e "SHOW DATABASES;"

    echo "请选择要管理的数据库："
    read -p "数据库名称: " db_name

    echo "1. 查看表"
    echo "2. 创建表"
    echo "3. 删除表"
    read -p "请输入选项 (1-3): " manage_choice

    case $manage_choice in
        1)
            mysql -u root -p${root_password} -e "USE ${db_name}; SHOW TABLES;"
            ;;
        2)
            read -p "请输入要创建的表名: " table_name
            read -p "请输入表结构 (例如: id INT PRIMARY KEY, name VARCHAR(50)): " table_structure
            mysql -u root -p${root_password} -e "USE ${db_name}; CREATE TABLE ${table_name} (${table_structure});"
            if [ $? -eq 0 ]; then
                echo "表 '${table_name}' 创建成功。"
            else
                echo "表创建失败。"
            fi
            ;;
        3)
            read -p "请输入要删除的表名: " table_name
            mysql -u root -p${root_password} -e "USE ${db_name}; DROP TABLE ${table_name};"
            if [ $? -eq 0 ]; then
                echo "表 '${table_name}' 删除成功。"
            else
                echo "表删除失败。"
            fi
            ;;
        *)
            echo "无效的选项。返回主菜单。"
            ;;
    esac
}

# 卸载 MySQL
uninstall_mysql() {
    read -p "请输入确认卸载 MySQL 的文字: " confirm_text
    if [ "$confirm_text" == "卸载 MySQL" ]; then
        echo "正在卸载 MySQL..."
        apt-get remove --purge -y mysql-server mysql-client mysql-common
        apt-get autoremove -y
        apt-get autoclean
        rm -rf /etc/mysql /var/lib/mysql
        echo "MySQL 已成功卸载。"
    else
        echo "确认文字不正确。取消卸载。"
    fi
}

# 显示菜单
show_menu() {
    echo "============================"
    echo " MySQL 管理脚本"
    echo "============================"
    echo "1. 安装 MySQL"
    echo "2. 添加数据库"
    echo "3. 管理数据库"
    echo "4. 卸载 MySQL"
    echo "0. 退出"
    echo "============================"
}

# 主循环
main() {
    update_system
    install_dependencies

    while true; do
        show_menu
        read -p "请输入选项: " choice
        case $choice in
            1)
                install_mysql
                ;;
            2)
                add_database
                ;;
            3)
                manage_database
                ;;
            4)
                uninstall_mysql
                ;;
            0)
                echo "退出脚本。"
                exit
                ;;
            *)
                echo "无效的选项，请重新选择。"
                ;;
        esac
        echo
    done
}

# 运行主函数
main
