#!/bin/bash

# MySQL 管理脚本
# 需要以 root 或具有 sudo 权限的用户运行

# 检查 Docker 是否安装
function check_docker() {
    if ! command -v docker &> /dev/null
    then
        echo "Docker 未安装。正在安装 Docker..."
        # 安装 Docker（适用于基于 Debian/Ubuntu 的系统）
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        if ! command -v docker &> /dev/null
        then
            echo "Docker 安装失败。请手动安装 Docker 后重试。"
            exit 1
        fi
        echo "Docker 安装成功。"
    fi
}

# 安装 MySQL
function install_mysql() {
    echo "请选择要安装的 MySQL 版本（例如 5.7, 8.0）："
    read -p "版本: " mysql_version
    if [[ -z "$mysql_version" ]]; then
        echo "未输入版本号，安装已取消。"
        return
    fi

    read -p "请输入持久化挂载路径（默认: /root/.docker/mysql）: " mount_path
    mount_path=${mount_path:-/root/.docker/mysql}

    read -p "请输入端口号（默认: 3306）: " port
    port=${port:-3306}

    read -s -p "请输入 MySQL root 用户密码: " root_password
    echo
    if [[ -z "$root_password" ]]; then
        echo "未设置 root 密码，安装已取消。"
        return
    fi

    # 检查端口是否被占用
    if lsof -i:$port &> /dev/null
    then
        echo "端口 $port 已被占用，请选择其他端口。"
        return
    fi

    # 创建挂载目录
    mkdir -p "$mount_path"

    # 运行 Docker 容器
    docker run -d \
    --name mysql-docker \
    -p ${port}:3306 \
    -e MYSQL_ROOT_PASSWORD=${root_password} \
    -v ${mount_path}:/var/lib/mysql \
    mysql:${mysql_version}

    if [ $? -eq 0 ]; then
        echo "MySQL ${mysql_version} 安装并运行成功。"
    else
        echo "MySQL 安装失败。"
    fi
}

# 添加数据库
function add_database() {
    # 检查 MySQL 容器是否运行
    if ! docker ps | grep -q mysql-docker
    then
        echo "MySQL 容器未运行，请先安装并启动 MySQL。"
        return
    fi

    read -p "请输入要创建的数据库名称: " db_name
    if [[ -z "$db_name" ]]; then
        echo "未输入数据库名称，操作已取消。"
        return
    fi

    read -p "请输入要创建的用户名: " db_user
    if [[ -z "$db_user" ]]; then
        echo "未输入用户名，操作已取消。"
        return
    fi

    read -s -p "请输入该用户的密码: " db_password
    echo
    if [[ -z "$db_password" ]]; then
        echo "未设置用户密码，操作已取消。"
        return
    fi

    echo "请选择数据库编码："
    echo "1. utf8"
    echo "2. utf8mb4"
    echo "3. latin1"
    echo "4. gbk"
    read -p "选择编码 (1-4): " encoding_choice

    case $encoding_choice in
        1)
            db_charset="utf8"
            ;;
        2)
            db_charset="utf8mb4"
            ;;
        3)
            db_charset="latin1"
            ;;
        4)
            db_charset="gbk"
            ;;
        *)
            echo "无效的选择，操作已取消。"
            return
            ;;
    esac

    read -s -p "请输入 MySQL root 用户密码: " root_password
    echo
    if [[ -z "$root_password" ]]; then
        echo "未输入 root 密码，操作已取消。"
        return
    fi

    # 创建数据库
    docker exec -i mysql-docker mysql -uroot -p${root_password} -e "CREATE DATABASE \`${db_name}\` CHARACTER SET ${db_charset} COLLATE ${db_charset}_general_ci;"

    if [ $? -ne 0 ]; then
        echo "数据库创建失败。请检查密码是否正确或数据库是否已存在。"
        return
    fi

    # 创建用户并授权
    docker exec -i mysql-docker mysql -uroot -p${root_password} -e "CREATE USER '${db_user}'@'%' IDENTIFIED BY '${db_password}';"
    if [ $? -ne 0 ]; then
        echo "用户创建失败。请检查用户名是否已存在。"
        # 尝试删除已创建的数据库
        docker exec -i mysql-docker mysql -uroot -p${root_password} -e "DROP DATABASE \`${db_name}\`;"
        return
    fi

    docker exec -i mysql-docker mysql -uroot -p${root_password} -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'%'; FLUSH PRIVILEGES;"
    if [ $? -eq 0 ]; then
        echo "数据库 '${db_name}' 和用户 '${db_user}' 创建并授权成功。"
    else
        echo "授权失败。"
    fi
}

# 管理数据库
function manage_database() {
    # 检查 MySQL 容器是否运行
    if ! docker ps | grep -q mysql-docker
    then
        echo "MySQL 容器未运行，请先安装并启动 MySQL。"
        return
    fi

    echo "请选择操作："
    echo "1. 查看所有数据库"
    echo "2. 删除数据库"
    echo "3. 重命名数据库"
    echo "0. 返回主菜单"
    read -p "选择: " manage_choice

    case $manage_choice in
        1)
            read -s -p "请输入 MySQL root 用户密码: " root_password
            echo
            docker exec -i mysql-docker mysql -uroot -p${root_password} -e "SHOW DATABASES;"
            ;;
        2)
            read -p "请输入要删除的数据库名称: " db_name
            if [[ -z "$db_name" ]]; then
                echo "未输入数据库名称，操作已取消。"
                return
            fi
            read -s -p "请输入 MySQL root 用户密码: " root_password
            echo
            docker exec -i mysql-docker mysql -uroot -p${root_password} -e "DROP DATABASE \`${db_name}\`;"
            if [ $? -eq 0 ]; then
                echo "数据库 '${db_name}' 删除成功。"
            else
                echo "删除数据库失败。请检查名称是否正确。"
            fi
            ;;
        3)
            read -p "请输入要重命名的数据库名称: " old_db
            read -p "请输入新数据库名称: " new_db
            if [[ -z "$old_db" || -z "$new_db" ]]; then
                echo "输入不完整，操作已取消。"
                return
            fi
            read -s -p "请输入 MySQL root 用户密码: " root_password
            echo
            # 检查是否支持重命名（MySQL 8.0.23+ 支持 RENAME DATABASE）
            mysql_version=$(docker exec -i mysql-docker mysql -uroot -p${root_password} -e "SELECT VERSION();" | awk 'NR==2 {print $1}')
            if [[ "$(printf '%s\n' "8.0.23" "$mysql_version" | sort -V | head -n1)" = "8.0.23" && "$mysql_version" != "8.0.23" ]]; then
                # MySQL 支持 RENAME DATABASE
                docker exec -i mysql-docker mysql -uroot -p${root_password} -e "RENAME DATABASE \`${old_db}\` TO \`${new_db}\`;"
                if [ $? -eq 0 ]; then
                    echo "数据库 '${old_db}' 重命名为 '${new_db}' 成功。"
                else
                    echo "重命名数据库失败。"
                fi
            else
                # 不支持直接重命名，采用导出导入方式
                docker exec -i mysql-docker mysqldump -uroot -p${root_password} ${old_db} > /tmp/${old_db}.sql
                docker exec -i mysql-docker mysql -uroot -p${root_password} -e "CREATE DATABASE \`${new_db}\`;"
                docker exec -i mysql-docker mysql -uroot -p${root_password} ${new_db} < /tmp/${old_db}.sql
                docker exec -i mysql-docker mysql -uroot -p${root_password} -e "DROP DATABASE \`${old_db}\`;"
                rm -f /tmp/${old_db}.sql
                if [ $? -eq 0 ]; then
                    echo "数据库 '${old_db}' 重命名为 '${new_db}' 成功。"
                else
                    echo "重命名数据库失败。"
                fi
            fi
            ;;
        0)
            return
            ;;
        *)
            echo "无效的选择。"
            ;;
    esac
}

# 卸载 MySQL
function uninstall_mysql() {
    read -p "确定要卸载 MySQL 吗？输入 'y' 以确认: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "确认失败，卸载已取消。"
        return
    fi

    # 停止并移除容器
    docker stop mysql-docker
    docker rm mysql-docker

    if [ $? -eq 0 ]; then
        echo "MySQL Docker 容器已成功卸载。"
    else
        echo "卸载失败。请检查 Docker 容器是否存在或当前用户是否有权限。"
    fi
}

# 主菜单
function main_menu() {
    while true
    do
        echo "================ MySQL 管理脚本 ================"
        echo "1. 安装 MySQL"
        echo "2. 添加数据库"
        echo "3. 管理数据库"
        echo "4. 卸载 MySQL"
        echo "0. 退出"
        echo "==============================================="
        read -p "请选择一个选项: " choice
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
                exit 0
                ;;
            *)
                echo "无效的选择，请重新输入。"
                ;;
        esac
        echo
    done
}

# 检查依赖项
check_docker

# 运行主菜单
main_menu
