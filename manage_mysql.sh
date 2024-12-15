#!/usr/bin/env bash

############################################################
# 说明：
# 该脚本在 Debian/Ubuntu 系列下测试，其他发行版需要根据实际情况更改包管理命令和安装方式。
# 功能：
#   1. 安装 MySQL (可选择版本)
#   2. 添加数据库
#   3. 管理数据库（查看和修改数据库信息）
#   4. 卸载 MySQL（需要确认文字）
#   0. 退出
#
# 使用注意：
# 该脚本需要在具备 sudo 权限的用户下执行。
# 数据库连接和管理可能需要 root 用户或有权限的 MySQL 用户。
# 如需非交互安装 MySQL，可提前设定 DEBIAN_FRONTEND=noninteractive。
############################################################

# 全局变量定义
MYSQL_USER="root"
MYSQL_PASSWORD=""
MYSQL_CMD="mysql"
MYSQLD_CMD="mysqld"
DB_ROOT_PW_SET=false

# 检查依赖项并安装 (expect、curl、gnupg等)
check_and_install_dependencies() {
    echo "正在检查并安装依赖项..."
    # 使用apt方式安装
    sudo apt-get update -y
    sudo apt-get install -y curl gnupg expect
    # 根据需要添加额外依赖，如unzip等
}

# 设置MySQL官方源（可选，确保你可以选择版本安装）
set_mysql_apt_repo() {
    # 该函数可选，如果你需要特定版本，可提前从MySQL官方网站获取repo包
    # 下面仅为示例，如果无需特定版本的 repo 可以跳过此步骤。
    # 假设需要5.7和8.0版本选择
    # 由于MySQL官方提供的repo可以安装多个版本，这里仅演示过程
    wget https://dev.mysql.com/get/mysql-apt-config_0.8.23-1_all.deb -O /tmp/mysql-apt-config.deb
    sudo dpkg -i /tmp/mysql-apt-config.deb
    sudo apt-get update -y
}

# 安装MySQL（可选择版本）
install_mysql() {
    echo "请选择需要安装的 MySQL 版本："
    echo "1) MySQL 5.7"
    echo "2) MySQL 8.0"
    read -p "输入选项编号(1或2): " version_choice

    case $version_choice in
        1)
            # 设置仓库为5.7
            # 假设已经有上面的set_mysql_apt_repo功能，如果不需要可直接安装默认版本
            sudo apt-get install -y mysql-server-5.7
            ;;
        2)
            # 设置仓库为8.0
            sudo apt-get install -y mysql-server-8.0
            ;;
        *)
            echo "无效的选项."
            return 1
            ;;
    esac

    # 安装后可能需要初始化root密码，如果安装过程会要求输入root密码，则可使用expect非交互方式设置
    # 如果已在安装过程中设置，此处可跳过。
    set_mysql_root_password
}

set_mysql_root_password() {
    if [ "$DB_ROOT_PW_SET" = false ]; then
        read -sp "请为 MySQL root 用户设置密码:" MYSQL_PASSWORD
        echo
        # 使用expect来非交互式设置root密码
        SECURE_MYSQL=$(expect -c "
set timeout 10
spawn sudo mysql_secure_installation
expect \"Press y|Y for Yes, any other key for No:\"
send \"y\r\"
expect \"New password:\"
send \"$MYSQL_PASSWORD\r\"
expect \"Re-enter new password:\"
send \"$MYSQL_PASSWORD\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"n\r\"        # 根据需求选择y或n，此处示例为允许远程
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")

        echo "$SECURE_MYSQL"
        DB_ROOT_PW_SET=true
        MYSQL_CMD="mysql -u$MYSQL_USER -p$MYSQL_PASSWORD"
    fi
}

# 添加数据库
add_database() {
    if [ "$DB_ROOT_PW_SET" = false ]; then
        read -sp "请输入MySQL root密码: " MYSQL_PASSWORD
        echo
        MYSQL_CMD="mysql -u$MYSQL_USER -p$MYSQL_PASSWORD"
    fi
    read -p "请输入要创建的数据库名称: " dbname
    if [ -z "$dbname" ]; then
        echo "数据库名称不能为空!"
        return 1
    fi
    echo "正在创建数据库 '$dbname' ..."
    echo "CREATE DATABASE \`$dbname\`;" | $MYSQL_CMD
    if [ $? -eq 0 ]; then
        echo "数据库 '$dbname' 创建成功!"
    else
        echo "数据库 '$dbname' 创建失败!"
    fi
}

# 管理数据库（查看和修改数据库信息）
manage_database() {
    if [ "$DB_ROOT_PW_SET" = false ]; then
        read -sp "请输入MySQL root密码: " MYSQL_PASSWORD
        echo
        MYSQL_CMD="mysql -u$MYSQL_USER -p$MYSQL_PASSWORD"
    fi
    # 显示已创建的数据库列表
    echo "当前已有的数据库列表："
    echo "SHOW DATABASES;" | $MYSQL_CMD
    echo "请选择要管理的数据库（输入数据库名称）："
    read -p "数据库名称: " dbname

    # 确认数据库是否存在
    DB_EXIST=$(echo "SHOW DATABASES LIKE '$dbname';" | $MYSQL_CMD | grep "$dbname")
    if [ -z "$DB_EXIST" ]; then
        echo "数据库 '$dbname' 不存在."
        return 1
    fi

    echo "管理选项："
    echo "1) 查看数据表列表"
    echo "2) 新增数据表(需要手动输入SQL)"
    echo "3) 修改数据表结构(需要手动输入ALTER SQL)"
    echo "4) 查看数据记录(需要SELECT查询)"
    echo "0) 返回上级菜单"
    read -p "请输入选项: " manage_choice

    case $manage_choice in
        1)
            echo "USE \`$dbname\`; SHOW TABLES;" | $MYSQL_CMD
            ;;
        2)
            read -p "请输入创建表的SQL(以分号结束): " create_table_sql
            echo "USE \`$dbname\`;$create_table_sql" | $MYSQL_CMD
            ;;
        3)
            read -p "请输入修改表结构的SQL(例如: ALTER TABLE ...;): " alter_table_sql
            echo "USE \`$dbname\`;$alter_table_sql" | $MYSQL_CMD
            ;;
        4)
            read -p "请输入查看数据的SQL(例如: SELECT * FROM table;): " select_sql
            echo "USE \`$dbname\`;$select_sql" | $MYSQL_CMD
            ;;
        0)
            echo "返回上级菜单。"
            ;;
        *)
            echo "无效选项."
            ;;
    esac
}

# 卸载MySQL
uninstall_mysql() {
    read -p "确定要卸载 MySQL 吗？请输入: '确认卸载mysql数据库' 以继续: " confirm_text
    if [ "$confirm_text" = "确认卸载mysql数据库" ]; then
        echo "正在卸载 MySQL..."
        sudo apt-get remove --purge -y mysql-server mysql-client mysql-common
        sudo apt-get autoremove -y
        sudo apt-get autoclean
        # 清理数据目录
        sudo rm -rf /var/lib/mysql
        sudo rm -rf /etc/mysql
        echo "MySQL 卸载完成。"
        DB_ROOT_PW_SET=false
    else
        echo "未确认卸载，操作取消。"
    fi
}

# 主菜单函数
main_menu() {
    while true; do
        echo "========================================"
        echo "          MySQL 管理脚本"
        echo "========================================"
        echo "1) 安装 MySQL"
        echo "2) 添加数据库"
        echo "3) 管理数据库"
        echo "4) 卸载 MySQL"
        echo "0) 退出脚本"
        echo "========================================"
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
                echo "退出脚本..."
                exit 0
                ;;
            *)
                echo "无效选项，请重新输入。"
                ;;
        esac
    done
}

# 主逻辑开始
check_and_install_dependencies
# 如需设置 MySQL APT 源，可在此调用 set_mysql_apt_repo 函数
# set_mysql_apt_repo
main_menu
