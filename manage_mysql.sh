#!/bin/bash

# MySQL 管理脚本
# 支持安装、添加数据库、管理数据库和卸载 MySQL

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户运行此脚本。使用 sudo ./mysql_manager.sh"
  exit 1
fi

# 全局变量
DEFAULT_MYSQL_ROOT_PASSWORD="root"  # 默认 MySQL root 密码，可根据需要修改

# 函数：安装 MySQL
install_mysql() {
  echo "请选择要安装的 MySQL 版本："
  echo "1. MySQL 5.7"
  echo "2. MySQL 8.0"
  read -p "请输入数字选择版本（1 或 2）： " version_choice

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

  echo "您选择安装 MySQL $MYSQL_VERSION"

  # 更新包列表
  apt update

  # 安装依赖项
  echo "安装依赖项..."
  apt install -y wget lsb-release gnupg debconf-utils

  # 下载 MySQL APT 配置包
  # 更新此处的版本号为当前最新版本
  MYSQL_APT_CONFIG_VERSION="0.8.24-1"
  MYSQL_APT_CONFIG_URL="https://dev.mysql.com/get/mysql-apt-config_${MYSQL_APT_CONFIG_VERSION}_all.deb"
  MYSQL_APT_CONFIG_DEB="/tmp/mysql-apt-config_${MYSQL_APT_CONFIG_VERSION}_all.deb"

  echo "下载 MySQL APT 配置包 (${MYSQL_APT_CONFIG_URL})..."
  wget "$MYSQL_APT_CONFIG_URL" -O "$MYSQL_APT_CONFIG_DEB"

  if [ ! -f "$MYSQL_APT_CONFIG_DEB" ]; then
    echo "下载 MySQL APT 配置包失败。请检查网络连接或 URL 是否正确。"
    return
  fi

  # 预先配置 debconf 以选择 MySQL 版本
  echo "预先配置 MySQL APT 配置选项..."
  echo "mysql-apt-config mysql-apt-config/select-server select mysql-$MYSQL_VERSION" | debconf-set-selections
  echo "mysql-apt-config mysql-apt-config/select-product select Ok" | debconf-set-selections

  # 安装 MySQL APT 配置包
  echo "安装 MySQL APT 配置包..."
  DEBIAN_FRONTEND=noninteractive dpkg -i "$MYSQL_APT_CONFIG_DEB"

  if [ $? -ne 0 ]; then
    echo "安装 MySQL APT 配置包失败。"
    return
  fi

  # 更新包列表以包括 MySQL 仓库
  apt update

  # 安装 MySQL Server
  echo "安装 MySQL Server..."
  DEBIAN_FRONTEND=noninteractive apt install -y mysql-server

  if [ $? -ne 0 ]; then
    echo "安装 MySQL Server 失败。请检查 MySQL APT 仓库配置或网络连接。"
    return
  fi

  # 启动并启用 MySQL 服务
  systemctl start mysql
  systemctl enable mysql

  # 设置 MySQL root 密码并进行安全配置
  echo "设置 MySQL root 密码并进行安全配置..."

  # 允许用户自定义 MySQL root 密码
  read -s -p "请输入 MySQL root 用户的新密码： " MYSQL_ROOT_PASSWORD
  echo
  read -s -p "请再次输入 MySQL root 用户的新密码以确认： " MYSQL_ROOT_PASSWORD_CONFIRM
  echo

  if [ "$MYSQL_ROOT_PASSWORD" != "$MYSQL_ROOT_PASSWORD_CONFIRM" ]; then
    echo "两次输入的密码不一致。取消安装。"
    return
  fi

  # 使用 debconf 配置密码
  echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
  echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections

  # 重新安装 mysql-server 以应用密码设置
  DEBIAN_FRONTEND=noninteractive apt install -y mysql-server

  # 运行 mysql_secure_installation
  echo "运行 mysql_secure_installation 以完成安全配置..."
  mysql_secure_installation <<EOF

y
$MYSQL_ROOT_PASSWORD
$MYSQL_ROOT_PASSWORD
y
y
y
y
EOF

  if [ $? -eq 0 ]; then
    echo "MySQL $MYSQL_VERSION 安装完成。"
    DEFAULT_MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
  else
    echo "MySQL 安装完成，但运行 mysql_secure_installation 时出现错误。请手动完成安全配置。"
  fi

  # 清理下载的 APT 配置包
  rm -f "$MYSQL_APT_CONFIG_DEB"
}

# 函数：添加数据库
add_database() {
  read -p "请输入要创建的数据库名称： " db_name
  if [[ -z "$db_name" ]]; then
    echo "数据库名称不能为空。"
    return
  fi

  mysql -u root -p"$DEFAULT_MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE \`$db_name\`;" 2>/dev/null

  if [ $? -eq 0 ]; then
    echo "数据库 '$db_name' 创建成功。"
  else
    echo "创建数据库失败。请确保 MySQL 已安装并且 root 密码正确。"
  fi
}

# 函数：管理数据库
manage_database() {
  echo "现有数据库列表："
  mysql -u root -p"$DEFAULT_MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;" | grep -vE "Database|information_schema|performance_schema|mysql|sys"

  read -p "请输入要管理的数据库名称： " db_name
  if [[ -z "$db_name" ]]; then
    echo "数据库名称不能为空。"
    return
  fi

  # 检查数据库是否存在
  exists=$(mysql -u root -p"$DEFAULT_MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES LIKE '$db_name';" | grep "$db_name")
  if [[ "$exists" != "$db_name" ]]; then
    echo "数据库 '$db_name' 不存在。"
    return
  fi

  echo "请选择要执行的操作："
  echo "1. 查看数据库表"
  echo "2. 创建新表"
  echo "3. 删除数据库"
  read -p "请输入数字选择操作（1、2 或 3）： " action_choice

  case $action_choice in
    1)
      mysql -u root -p"$DEFAULT_MYSQL_ROOT_PASSWORD" -e "USE \`$db_name\`; SHOW TABLES;"
      ;;
    2)
      read -p "请输入要创建的表名： " table_name
      read -p "请输入表的列定义（例如: id INT PRIMARY KEY, name VARCHAR(50)）： " columns
      mysql -u root -p"$DEFAULT_MYSQL_ROOT_PASSWORD" -e "USE \`$db_name\`; CREATE TABLE \`$table_name\` ($columns);"
      if [ $? -eq 0 ]; then
        echo "表 '$table_name' 创建成功。"
      else
        echo "创建表失败。"
      fi
      ;;
    3)
      read -p "您确定要删除数据库 '$db_name' 吗？请输入 '确认' 以继续： " confirm
      if [ "$confirm" == "确认" ]; then
        mysql -u root -p"$DEFAULT_MYSQL_ROOT_PASSWORD" -e "DROP DATABASE \`$db_name\`;"
        if [ $? -eq 0 ]; then
          echo "数据库 '$db_name' 已删除。"
        else
          echo "删除数据库失败。"
        fi
      else
        echo "取消删除数据库。"
      fi
      ;;
    *)
      echo "无效的选择。"
      ;;
  esac
}

# 函数：卸载 MySQL
uninstall_mysql() {
  read -p "请输入 '确认卸载 MySQL 数据库' 以继续卸载： " confirm_uninstall
  if [ "$confirm_uninstall" == "确认卸载 MySQL 数据库" ]; then
    echo "卸载 MySQL..."
    apt remove --purge -y mysql-server mysql-client mysql-common
    apt autoremove -y
    apt autoclean

    # 删除 MySQL 数据目录
    rm -rf /var/lib/mysql
    rm -rf /etc/mysql

    echo "MySQL 已成功卸载。"
  else
    echo "未确认卸载，取消操作。"
  fi
}

# 主循环
while true; do
  echo "=============================="
  echo " MySQL 安装与管理脚本"
  echo "=============================="
  echo "1. 安装 MySQL"
  echo "2. 添加数据库"
  echo "3. 管理数据库"
  echo "4. 卸载 MySQL 数据库"
  echo "0. 退出脚本"
  echo "=============================="
  read -p "请输入选项编号： " choice

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
      echo "无效的选项，请重新选择。"
      ;;
  esac
done
