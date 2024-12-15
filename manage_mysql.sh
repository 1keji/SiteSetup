#!/usr/bin/env bash

############################################################
# 说明：
# 该脚本在 Debian/Ubuntu 系列系统下测试。
# 功能：
#   1. 安装 MySQL (可选择版本5.7或8.0)
#   2. 添加数据库
#   3. 管理数据库（查看和修改已创建的数据库信息）
#   4. 卸载 MySQL（需要确认文字）
#   0. 退出
#
# 使用注意：
# - 需要sudo权限执行
# - 若在无交互环境下运行，可提前设定 DEBIAN_FRONTEND=noninteractive
#
# 更新点（方案一修正）：
# - 添加 MySQL 官方 APT 源，以支持安装5.7或8.0版本的 MySQL
# - 移除对mysql-server-5.7直接安装的逻辑，改为通过apt仓库选择
############################################################

MYSQL_USER="root"
MYSQL_PASSWORD=""
MYSQL_CMD="mysql"
DB_ROOT_PW_SET=false

# 检查并安装依赖项
check_and_install_dependencies() {
    echo "正在检查并安装依赖项..."
    sudo apt-get update -y
    sudo apt-get install -y curl gnupg expect wget lsb-release
}

# 添加并配置 MySQL 官方 APT 仓库
set_mysql_apt_repo() {
    # 获取系统代号
    DISTRO_CODENAME=$(lsb_release -sc)
    # 下载MySQL APT配置包，根据MySQL官方仓库选择最新版本，这里使用0.8.31-1为例
    # 请根据实际情况替换URL为最新的MySQL APT配置包
    wget https://dev.mysql.com/get/mysql-apt-config_0.8.31-1_all.deb -O /tmp/mysql-apt-config.deb
    # 安装apt-config包，交互过程中可选择MySQL版本
    # 为避免交互，这里使用debconf-set-selections预先设置
    # 若希望手动选择版本，可在此处手动运行dpkg -i并交互选择。
    # 下方是直接安装，然后用户选择时再进行交互。
    sudo dpkg -i /tmp/mysql-apt-config.deb
    sudo apt-get update -y
}

# 使用 expect 自动运行 mysql_secure_installation
run_mysql_secure_installation() {
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
send \"n\r\"        # 如果需要禁止远程登录改为y
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
    echo "$SECURE_MYSQL"
    DB_ROOT_PW_SET=true
}

# 安装MySQL（可选择版本）
install_mysql() {
    echo "请选择需要安装的 MySQL 版本："
    echo "1) MySQL 5.7"
    echo "2) MySQL 8.0"
    read -p "输入选项编号(1或2): " version_choice

    case $version_choice in
        1)
            # 用户选择MySQL5.7时重新配置mysql-apt-config
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y debconf-utils
            # 设置mysql-apt-config选择5.7
            sudo debconf-set-selections <<< "mysql-apt-config mysql-apt-config/select-server select mysql-5.7"
            sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure mysql-apt-config
            sudo apt-get update -y
            sudo apt-get install -y mysql-server
            ;;
        2)
            # 用户选择MySQL8.0时重新配置mysql-apt-config
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y debconf-utils
            sudo debconf-set-selections <<< "mysql-apt-config mysql-apt-config/select-server select mysql-8.0"
            sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure mysql-apt-config
            sudo apt-get update -y
            sudo apt-get install -y mysql-server
            ;;
        *)
            echo "无效的选项."
            return 1
            ;;
    esac

    # 设置root密码
    set_mysql_root_password
}

set_mysql_root_password() {
    read -sp "请为 MySQL root 用户设置密码: " MYSQL_PASSWORD
    echo
    run_mysql_secure_installation
    MYSQL_CMD="mysql -u$MYSQL_USER -p$MYSQL_PASSWORD"
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
    echo "2) 新增数据表(输入CREATE TABLE语句)"
    echo "3) 修改数据表结构(输入ALTER TABLE语句)"
    echo "4) 查看数据记录(输入SELECT查询)"
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
# 设置MySQL APT源
set_mysql_apt_repo
# 进入主菜单
main_menu
