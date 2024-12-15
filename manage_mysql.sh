#!/bin/bash

# MySQL 管理脚本
# 需要以 root 或具有 sudo 权限的用户运行

# Docker 容器名称
MYSQL_CONTAINER_NAME="mysql-docker"

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

    # 检查是否已存在同名容器
    if docker ps -a --format '{{.Names}}' | grep -wq "$MYSQL_CONTAINER_NAME"; then
        echo "容器名称 '$MYSQL_CONTAINER_NAME' 已存在。请先删除现有容器或选择不同的名称。"
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
    --name "$MYSQL_CONTAINER_NAME" \
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
    if ! docker ps | grep -q "$MYSQL_CONTAINER_NAME"
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
            db_collate="utf8_general_ci"
            ;;
        2)
            db_charset="utf8mb4"
            db_collate="utf8mb4_general_ci"
            ;;
        3)
            db_charset="latin1"
            db_collate="latin1_swedish_ci"
            ;;
        4)
            db_charset="gbk"
            db_collate="gbk_chinese_ci"
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
    docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "CREATE DATABASE \`${db_name}\` CHARACTER SET ${db_charset} COLLATE ${db_collate};"

    if [ $? -ne 0 ]; then
        echo "数据库创建失败。请检查密码是否正确或数据库是否已存在。"
        return
    fi

    # 创建用户并授权
    docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "CREATE USER '${db_user}'@'%' IDENTIFIED BY '${db_password}';"
    if [ $? -ne 0 ]; then
        echo "用户创建失败。请检查用户名是否已存在。"
        # 尝试删除已创建的数据库
        docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "DROP DATABASE \`${db_name}\`;"
        return
    fi

    docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'%'; FLUSH PRIVILEGES;"
    if [ $? -eq 0 ]; then
        echo "数据库 '${db_name}' 和用户 '${db_user}' 创建并授权成功。"
    else
        echo "授权失败。"
    fi
}

# 修改数据库信息
function modify_database_info() {
    # 检查 MySQL 容器是否运行
    if ! docker ps | grep -q "$MYSQL_CONTAINER_NAME"
    then
        echo "MySQL 容器未运行，请先安装并启动 MySQL。"
        return
    fi

    read -s -p "请输入 MySQL root 用户密码: " root_password
    echo
    if [[ -z "$root_password" ]]; then
        echo "未输入 root 密码，操作已取消。"
        return
    fi

    # 获取所有数据库列表，排除系统数据库
    databases=$(docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "SHOW DATABASES;" | grep -Ev "Database|information_schema|performance_schema|mysql|sys")

    if [[ -z "$databases" ]]; then
        echo "没有可修改的数据库。"
        return
    fi

    echo "可修改的数据库列表："
    select db in $databases "取消"
    do
        if [[ "$db" == "取消" ]]; then
            echo "操作已取消。"
            return
        elif [[ -n "$db" ]]; then
            selected_db="$db"
            break
        else
            echo "无效的选择，请重新选择。"
        fi
    done

    echo "请选择要修改的项："
    echo "1. 修改数据库名称"
    echo "2. 修改用户名"
    echo "3. 修改用户密码"
    echo "4. 同时修改数据库名称、用户名和密码"
    echo "0. 返回"
    read -p "选择: " modify_choice

    case $modify_choice in
        1)
            # 修改数据库名称
            read -p "请输入新的数据库名称: " new_db
            if [[ -z "$new_db" ]]; then
                echo "未输入新数据库名称，操作已取消。"
                return
            fi

            # 检查 MySQL 版本以决定是否支持 RENAME DATABASE
            mysql_version=$(docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "SELECT VERSION();" | awk 'NR==2 {print $1}')
            required_version="8.0.23"
            if [[ "$(printf '%s\n' "$required_version" "$mysql_version" | sort -V | head -n1)" == "$required_version" && "$mysql_version" != "$required_version" ]]; then
                # MySQL 支持 RENAME DATABASE
                docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "RENAME DATABASE \`${selected_db}\` TO \`${new_db}\`;"
                if [ $? -eq 0 ]; then
                    echo "数据库 '${selected_db}' 重命名为 '${new_db}' 成功。"
                else
                    echo "重命名数据库失败。"
                fi
            else
                # 不支持直接重命名，采用导出导入方式
                docker exec -i "$MYSQL_CONTAINER_NAME" mysqldump -uroot -p${root_password} ${selected_db} > /tmp/${selected_db}.sql
                if [ $? -ne 0 ]; then
                    echo "导出数据库 '${selected_db}' 失败。"
                    return
                fi
                docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "CREATE DATABASE \`${new_db}\`;"
                if [ $? -ne 0 ]; then
                    echo "创建新数据库 '${new_db}' 失败。"
                    rm -f /tmp/${selected_db}.sql
                    return
                fi
                docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} ${new_db} < /tmp/${selected_db}.sql
                if [ $? -ne 0 ]; then
                    echo "导入数据到新数据库 '${new_db}' 失败。"
                    docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "DROP DATABASE \`${new_db}\`;"
                    rm -f /tmp/${selected_db}.sql
                    return
                fi
                docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "DROP DATABASE \`${selected_db}\`;"
                rm -f /tmp/${selected_db}.sql
                if [ $? -eq 0 ]; then
                    echo "数据库 '${selected_db}' 重命名为 '${new_db}' 成功。"
                else
                    echo "重命名数据库失败。"
                fi
            fi
            ;;
        2)
            # 修改用户名
            read -p "请输入要修改的用户名: " old_user
            if [[ -z "$old_user" ]]; then
                echo "未输入用户名，操作已取消。"
                return
            fi

            read -p "请输入新的用户名: " new_user
            if [[ -z "$new_user" ]]; then
                echo "未输入新用户名，操作已取消。"
                return
            fi

            docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "RENAME USER '${old_user}'@'%' TO '${new_user}'@'%';"
            if [ $? -eq 0 ]; then
                echo "用户名从 '${old_user}' 修改为 '${new_user}' 成功。"
            else
                echo "修改用户名失败。请确保旧用户名存在且新用户名未被使用。"
            fi
            ;;
        3)
            # 修改用户密码
            read -p "请输入要修改密码的用户名: " user
            if [[ -z "$user" ]]; then
                echo "未输入用户名，操作已取消。"
                return
            fi

            read -s -p "请输入新的密码: " new_password
            echo
            if [[ -z "$new_password" ]]; then
                echo "未输入新密码，操作已取消。"
                return
            fi

            docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "ALTER USER '${user}'@'%' IDENTIFIED BY '${new_password}'; FLUSH PRIVILEGES;"
            if [ $? -eq 0 ]; then
                echo "用户 '${user}' 的密码修改成功。"
            else
                echo "修改密码失败。请确保用户名存在。"
            fi
            ;;
        4)
            # 同时修改数据库名称、用户名和密码
            # 修改数据库名称
            read -p "请输入新的数据库名称: " new_db
            if [[ -z "$new_db" ]]; then
                echo "未输入新数据库名称，操作已取消。"
                return
            fi

            # 修改用户名
            read -p "请输入要修改的用户名: " old_user
            if [[ -z "$old_user" ]]; then
                echo "未输入用户名，操作已取消。"
                return
            fi

            read -p "请输入新的用户名: " new_user
            if [[ -z "$new_user" ]]; then
                echo "未输入新用户名，操作已取消。"
                return
            fi

            # 修改用户密码
            read -s -p "请输入新的密码: " new_password
            echo
            if [[ -z "$new_password" ]]; then
                echo "未输入新密码，操作已取消。"
                return
            fi

            # 进行数据库重命名
            mysql_version=$(docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "SELECT VERSION();" | awk 'NR==2 {print $1}')
            required_version="8.0.23"
            if [[ "$(printf '%s\n' "$required_version" "$mysql_version" | sort -V | head -n1)" == "$required_version" && "$mysql_version" != "$required_version" ]]; then
                # MySQL 支持 RENAME DATABASE
                docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "RENAME DATABASE \`${selected_db}\` TO \`${new_db}\`;"
                if [ $? -eq 0 ]; then
                    echo "数据库 '${selected_db}' 重命名为 '${new_db}' 成功。"
                else
                    echo "重命名数据库失败。"
                    return
                fi
            else
                # 不支持直接重命名，采用导出导入方式
                docker exec -i "$MYSQL_CONTAINER_NAME" mysqldump -uroot -p${root_password} ${selected_db} > /tmp/${selected_db}.sql
                if [ $? -ne 0 ]; then
                    echo "导出数据库 '${selected_db}' 失败。"
                    return
                fi
                docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "CREATE DATABASE \`${new_db}\`;"
                if [ $? -ne 0 ]; then
                    echo "创建新数据库 '${new_db}' 失败。"
                    rm -f /tmp/${selected_db}.sql
                    return
                fi
                docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} ${new_db} < /tmp/${selected_db}.sql
                if [ $? -ne 0 ]; then
                    echo "导入数据到新数据库 '${new_db}' 失败。"
                    docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "DROP DATABASE \`${new_db}\`;"
                    rm -f /tmp/${selected_db}.sql
                    return
                fi
                docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "DROP DATABASE \`${selected_db}\`;"
                rm -f /tmp/${selected_db}.sql
                if [ $? -eq 0 ]; then
                    echo "数据库 '${selected_db}' 重命名为 '${new_db}' 成功。"
                else
                    echo "重命名数据库失败。"
                    return
                fi
            fi

            # 修改用户名
            docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "RENAME USER '${old_user}'@'%' TO '${new_user}'@'%';"
            if [ $? -eq 0 ]; then
                echo "用户名从 '${old_user}' 修改为 '${new_user}' 成功。"
            else
                echo "修改用户名失败。请确保旧用户名存在且新用户名未被使用。"
            fi

            # 修改用户密码
            docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "ALTER USER '${new_user}'@'%' IDENTIFIED BY '${new_password}'; FLUSH PRIVILEGES;"
            if [ $? -eq 0 ]; then
                echo "用户 '${new_user}' 的密码修改成功。"
            else
                echo "修改密码失败。请确保用户名存在。"
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

# 管理数据库
function manage_database() {
    # 检查 MySQL 容器是否运行
    if ! docker ps | grep -q "$MYSQL_CONTAINER_NAME"
    then
        echo "MySQL 容器未运行，请先安装并启动 MySQL。"
        return
    fi

    echo "请选择操作："
    echo "1. 查看所有数据库"
    echo "2. 删除数据库"
    echo "3. 修改数据库信息"
    echo "0. 返回主菜单"
    read -p "选择: " manage_choice

    case $manage_choice in
        1)
            read -s -p "请输入 MySQL root 用户密码: " root_password
            echo
            docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "SHOW DATABASES;"
            ;;
        2)
            read -p "请输入要删除的数据库名称: " db_name
            if [[ -z "$db_name" ]]; then
                echo "未输入数据库名称，操作已取消。"
                return
            fi
            read -s -p "请输入 MySQL root 用户密码: " root_password
            echo
            docker exec -i "$MYSQL_CONTAINER_NAME" mysql -uroot -p${root_password} -e "DROP DATABASE \`${db_name}\`;"
            if [ $? -eq 0 ]; then
                echo "数据库 '${db_name}' 删除成功。"
            else
                echo "删除数据库失败。请检查名称是否正确。"
            fi
            ;;
        3)
            modify_database_info
            ;;
        0)
            return
            ;;
        *)
            echo "无效的选择。"
            ;;
    esac
}

# 管理 MySQL 容器
function manage_mysql_container() {
    # 检查是否存在 MySQL 容器
    container_exists=$(docker ps -a --format '{{.Names}}' | grep -w "$MYSQL_CONTAINER_NAME")
    if [[ -z "$container_exists" ]]; then
        echo "MySQL 容器 '$MYSQL_CONTAINER_NAME' 不存在。"
        return
    fi

    echo "请选择容器管理操作："
    echo "1. 启动容器"
    echo "2. 停止容器"
    echo "3. 重启容器"
    echo "4. 删除容器"
    echo "0. 返回主菜单"
    read -p "选择: " container_choice

    case $container_choice in
        1)
            docker start "$MYSQL_CONTAINER_NAME"
            if [ $? -eq 0 ]; then
                echo "容器 '$MYSQL_CONTAINER_NAME' 启动成功。"
            else
                echo "启动容器失败。"
            fi
            ;;
        2)
            docker stop "$MYSQL_CONTAINER_NAME"
            if [ $? -eq 0 ]; then
                echo "容器 '$MYSQL_CONTAINER_NAME' 已停止。"
            else
                echo "停止容器失败。"
            fi
            ;;
        3)
            docker restart "$MYSQL_CONTAINER_NAME"
            if [ $? -eq 0 ]; then
                echo "容器 '$MYSQL_CONTAINER_NAME' 重启成功。"
            else
                echo "重启容器失败。"
            fi
            ;;
        4)
            read -p "确定要删除容器 '$MYSQL_CONTAINER_NAME' 吗？输入 'y' 以确认: " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo "确认失败，删除容器已取消。"
                return
            fi
            docker stop "$MYSQL_CONTAINER_NAME"
            docker rm "$MYSQL_CONTAINER_NAME"
            if [ $? -eq 0 ]; then
                echo "容器 '$MYSQL_CONTAINER_NAME' 已成功删除。"
            else
                echo "删除容器失败。请检查容器是否存在或当前用户是否有权限。"
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

# 管理 MySQL 镜像
function manage_mysql_images() {
    echo "请选择镜像管理操作："
    echo "1. 查看已安装的 MySQL 镜像"
    echo "2. 删除 MySQL 镜像"
    echo "3. 更新（拉取）MySQL 镜像"
    echo "0. 返回主菜单"
    read -p "选择: " image_choice

    case $image_choice in
        1)
            echo "已安装的 MySQL 镜像："
            docker images mysql --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
            ;;
        2)
            read -p "请输入要删除的 MySQL 镜像标签（例如 5.7, 8.0）: " image_tag
            if [[ -z "$image_tag" ]]; then
                echo "未输入镜像标签，操作已取消。"
                return
            fi
            image_name="mysql:${image_tag}"
            # 检查镜像是否存在
            if ! docker images | grep -w "$image_name" &> /dev/null; then
                echo "镜像 '$image_name' 不存在。"
                return
            fi
            # 确认删除
            read -p "确定要删除镜像 '$image_name' 吗？输入 'y' 以确认: " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo "确认失败，删除镜像已取消。"
                return
            fi
            docker rmi "$image_name"
            if [ $? -eq 0 ]; then
                echo "镜像 '$image_name' 已成功删除。"
            else
                echo "删除镜像失败。请确保没有容器在使用该镜像。"
            fi
            ;;
        3)
            echo "请选择要拉取的 MySQL 版本："
            echo "1. 5.7"
            echo "2. 8.0"
            echo "3. 8.0.32" # 例如具体版本
            read -p "选择版本 (1-3): " update_choice

            case $update_choice in
                1)
                    pull_version="5.7"
                    ;;
                2)
                    pull_version="8.0"
                    ;;
                3)
                    pull_version="8.0.32"
                    ;;
                *)
                    echo "无效的选择，操作已取消。"
                    return
                    ;;
            esac

            echo "正在拉取 MySQL 镜像版本 '$pull_version'..."
            docker pull mysql:${pull_version}
            if [ $? -eq 0 ]; then
                echo "MySQL 镜像版本 '$pull_version' 拉取成功。"
            else
                echo "拉取 MySQL 镜像失败。"
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

# 主菜单
function main_menu() {
    while true
    do
        echo "================ MySQL 管理脚本 ================"
        echo "1. 安装 MySQL"
        echo "2. 添加数据库"
        echo "3. 管理数据库"
        echo "4. 管理 MySQL 容器"
        echo "5. 管理 MySQL 镜像"
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
                manage_mysql_container
                ;;
            5)
                manage_mysql_images
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
