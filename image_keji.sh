#!/bin/bash

# ==========================================
#           一点科技 简单图床 安装脚本
#    （已整合原 php_imges.sh 所有功能）
# ==========================================
# 作者：1点科技
# 网站：https://1keji.net
# YouTube：https://www.youtube.com/@1keji_net
# GitHub：https://github.com/1keji
# ==========================================

# ------------------------------------------------------------------------------
#                   1) 原 nginx_images.sh 的所有内容（保持不删减）
# ------------------------------------------------------------------------------

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root用户运行此脚本。"
  exit 1
fi

# 定义需要打开的端口
REQUIRED_PORTS=(80 443)

# 定义支持的PHP版本
SUPPORTED_PHP_VERSIONS=(7.4 8.0 8.1 8.2 8.3)

# 检测并打开必要端口的函数
configure_firewall() {
  echo "检测并配置防火墙以开放必要的端口..."

  # 检查 ufw 是否安装和启用
  if command -v ufw >/dev/null 2>&1; then
    echo "检测到 ufw 防火墙。"
    for port in "${REQUIRED_PORTS[@]}"; do
      if ! ufw status | grep -qw "$port"; then
        echo "允许端口 $port ..."
        ufw allow "$port"
      else
        echo "端口 $port 已经开放。"
      fi
    done
    echo "防火墙配置完成。"
    return
  fi

  # 检查 firewalld 是否安装和启用
  if systemctl is-active --quiet firewalld; then
    echo "检测到 firewalld 防火墙。"
    for port in "${REQUIRED_PORTS[@]}"; do
      if ! firewall-cmd --list-ports | grep -qw "${port}/tcp"; then
        echo "允许端口 $port ..."
        firewall-cmd --permanent --add-port=${port}/tcp
      else
        echo "端口 $port 已经开放。"
      fi
    done
    firewall-cmd --reload
    echo "防火墙配置完成。"
    return
  fi

  # 检查 iptables 是否安装
  if command -v iptables >/dev/null 2>&1; then
    echo "检测到 iptables 防火墙。"
    for port in "${REQUIRED_PORTS[@]}"; do
      if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
        echo "允许端口 $port ..."
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
      else
        echo "端口 $port 已经开放。"
      fi
    done
    # 保存 iptables 规则（根据系统不同，可能需要调整）
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save
    elif command -v service >/dev/null 2>&1; then
      service iptables save
    fi
    echo "防火墙配置完成。"
    return
  fi

  echo "未检测到已知的防火墙工具（ufw、firewalld、iptables）。请手动确保端口 ${REQUIRED_PORTS[*]} 已开放。"
}

# 检测已安装的PHP版本（使用 systemctl 检测）
detect_installed_php_versions() {
  echo "检测已安装的PHP版本..."
  INSTALLED_PHP_VERSIONS=()

  # 使用 systemctl 检测已安装的 PHP-FPM 服务
  for service in $(systemctl list-units --type=service --all | grep 'php.*-fpm.service' | awk '{print $1}'); do
    version=$(echo "$service" | grep -oP '(?<=php)\d+\.\d+(?=-fpm)')
    if [[ $version =~ ^[0-9]+\.[0-9]+$ ]]; then
      INSTALLED_PHP_VERSIONS+=("$version")
    fi
  done

  if [ ${#INSTALLED_PHP_VERSIONS[@]} -eq 0 ]; then
    echo "未检测到已安装的PHP版本。"
  else
    echo "已安装的PHP版本："
    for ver in "${INSTALLED_PHP_VERSIONS[@]}"; do
      echo " - $ver"
    done
  fi
}

# 安装指定的PHP版本（原函数）
install_php() {
  local php_version=$1
  if [[ ! " ${SUPPORTED_PHP_VERSIONS[@]} " =~ " ${php_version} " ]]; then
    echo "不支持的PHP版本：$php_version"
    return 1
  fi

  if dpkg -l | grep -qw "php$php_version-fpm"; then
    echo "PHP $php_version 已经安装。"
  else
    echo "安装PHP $php_version..."
    apt install -y php$php_version-fpm php$php_version-cli php$php_version-common php$php_version-mysql php$php_version-xml php$php_version-mbstring php$php_version-curl php$php_version-zip
    if [ $? -ne 0 ]; then
      echo "安装PHP $php_version失败。"
      return 1
    fi
    systemctl start php$php_version-fpm
    systemctl enable php$php_version-fpm
    echo "PHP $php_version 安装完成。"
  fi
}

# 安装 Certbot
install_certbot() {
  if ! command -v certbot >/dev/null 2>&1; then
    echo "正在安装 Certbot..."
    apt update
    apt install -y certbot python3-certbot-nginx
    if [ $? -ne 0 ]; then
      echo "安装 Certbot 失败。请手动安装 Certbot 并重试。"
      exit 1
    fi
    echo "Certbot 安装完成。"
  else
    echo "Certbot 已经安装。"
  fi
}

# 安装 rsync
install_rsync() {
  if ! command -v rsync >/dev/null 2>&1; then
    echo "检测到 rsync 未安装，正在安装 rsync..."
    apt update
    apt install -y rsync
    if [ $? -ne 0 ]; then
      echo "安装 rsync 失败。请手动安装 rsync 并重试。"
      return 1
    fi
    echo "rsync 安装完成。"
  else
    echo "rsync 已经安装。"
  fi
}

# 安装Nginx（在安装完后会自动安装PHP）
install_nginx() {
  echo "更新系统包..."
  apt update && apt upgrade -y

  echo "安装 Nginx..."
  apt install -y nginx

  echo "配置防火墙以开放必要端口..."
  configure_firewall

  echo "确保 Nginx 配置目录存在..."
  mkdir -p /etc/nginx/sites-available
  mkdir -p /etc/nginx/sites-enabled

  echo "启动并启用 Nginx 服务..."
  systemctl start nginx
  systemctl enable nginx

  echo "Nginx 安装完成。"
  echo "-------------------------------------------------"
  echo "现在开始自动为你安装 PHP（默认安装 PHP 7.4）..."
  initialize_for_php
  install_php_menu
  echo "-------------------------------------------------"
}

# 添加网站配置
add_website() {
  read -p "请输入要添加的域名（例如 example.com 或 sub.example.com）： " DOMAIN
  if [ -f "/etc/nginx/sites-available/$DOMAIN" ]; then
    echo "配置文件 $DOMAIN 已存在。"
    return
  fi

  read -p "请输入用于 TLS 证书的邮箱地址： " EMAIL

  read -p "请输入网站的根目录路径（默认 /var/www/$DOMAIN）： " DOCUMENT_ROOT
  DOCUMENT_ROOT=${DOCUMENT_ROOT:-"/var/www/$DOMAIN"}

  # 设置上传文件大小，默认2M
  read -p "请输入允许上传文件的最大大小（例如 10M，默认 2M）： " UPLOAD_SIZE
  UPLOAD_SIZE=${UPLOAD_SIZE:-2M}

  echo "检测已安装的PHP版本..."
  detect_installed_php_versions

  if [ ${#INSTALLED_PHP_VERSIONS[@]} -eq 0 ]; then
    echo "未检测到已安装的PHP版本，请先安装PHP版本。"
    read -p "是否要继续添加网站但不配置PHP？ (y/n): " php_choice
    case $php_choice in
      y|Y )
        PHP_VERSION=""
        ;;
      *)
        echo "取消添加网站。"
        return
        ;;
    esac
  else
    echo "请选择PHP版本："
    select php_version in "${INSTALLED_PHP_VERSIONS[@]}" "不使用PHP"; do
      if [[ -n "$php_version" ]]; then
        if [ "$php_version" == "不使用PHP" ]; then
          PHP_VERSION=""
        else
          PHP_VERSION="$php_version"
        fi
        break
      else
        echo "无效的选项。"
      fi
    done
  fi

  echo "配置 Nginx..."
  if [ -n "$PHP_VERSION" ]; then
    cat > "/etc/nginx/sites-available/$DOMAIN" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    client_max_body_size $UPLOAD_SIZE;

    root $DOCUMENT_ROOT;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
  else
    cat > "/etc/nginx/sites-available/$DOMAIN" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    client_max_body_size $UPLOAD_SIZE;

    root $DOCUMENT_ROOT;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
  fi

  echo "创建网站目录..."
  mkdir -p "$DOCUMENT_ROOT"
  chown -R www-data:www-data "$DOCUMENT_ROOT"

  # 自动从GitHub克隆图床项目并部署
  echo "检测并安装 Git..."
  if ! command -v git >/dev/null 2>&1; then
    echo "Git 未安装，正在安装 Git..."
    apt update
    apt install -y git
    if [ $? -ne 0 ]; then
      echo "安装 Git 失败。请手动安装 Git 并重试。"
      return
    fi
    echo "Git 安装完成。"
  else
    echo "Git 已经安装。"
  fi

  echo "检测并安装 rsync..."
  install_rsync
  if [ $? -ne 0 ]; then
    echo "安装 rsync 失败。请手动安装 rsync 并重试。"
    return
  fi

  echo "克隆 EasyImages2.0 图床项目..."
  TEMP_DIR=$(mktemp -d)
  git clone https://github.com/icret/EasyImages2.0.git "$TEMP_DIR/EasyImages2.0"
  if [ $? -ne 0 ]; then
    echo "克隆仓库失败。请检查网络连接或仓库地址。"
    rm -rf "$TEMP_DIR"
    return
  fi

  echo "移动图床文件到网站根目录..."
  rsync -av --progress "$TEMP_DIR/EasyImages2.0/" "$DOCUMENT_ROOT/"
  if [ $? -ne 0 ]; then
    echo "移动文件失败。"
    rm -rf "$TEMP_DIR"
    return
  fi

  echo "删除临时目录..."
  rm -rf "$TEMP_DIR"

  echo "设置文件权限为 755..."
  chmod -R 755 "$DOCUMENT_ROOT"
  chown -R www-data:www-data "$DOCUMENT_ROOT"

  echo "图床项目已部署到 $DOCUMENT_ROOT。"

  echo "创建符号链接到 sites-enabled..."
  ln -s "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"

  echo "测试 Nginx 配置..."
  nginx -t

  if [ $? -ne 0 ]; then
      echo "Nginx 配置测试失败，请检查配置文件。"
      rm "/etc/nginx/sites-enabled/$DOMAIN"
      return
  fi

  echo "重新加载 Nginx..."
  systemctl reload nginx

  echo "安装 Certbot 以申请 Let's Encrypt TLS 证书..."
  install_certbot

  echo "申请 Let's Encrypt TLS 证书..."
  if [ -n "$PHP_VERSION" ]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
  else
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"
  fi

  if [ $? -ne 0 ]; then
      echo "Certbot 申请证书失败。请检查域名的 DNS 设置是否正确。"
      rm "/etc/nginx/sites-enabled/$DOMAIN"
      return
  fi

  echo "设置自动续期..."
  systemctl enable certbot.timer
  systemctl start certbot.timer

  echo "网站配置完成！你的网站现在可以通过 https://$DOMAIN 访问。"
}

# 选择网站的辅助函数
select_website() {
  local websites=($(ls /etc/nginx/sites-available/))
  local count=${#websites[@]}

  if [ $count -eq 0 ]; then
    echo "没有配置的网站。"
    return 1
  fi

  echo "可用的网站列表："
  for i in "${!websites[@]}"; do
    printf "%d. %s\n" $((i+1)) "${websites[$i]}"
  done

  while true; do
    read -p "请输入要选择的网站编号 [1-$count]: " selection
    if [[ $selection =~ ^[1-9][0-9]*$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$count" ]; then
      SELECTED_WEBSITE="${websites[$((selection-1))]}"
      break
    else
      echo "无效的选择，请输入一个介于 1 到 $count 之间的数字。"
    fi
  done

  echo "已选择网站：$SELECTED_WEBSITE"

  CONFIG_PATH="/etc/nginx/sites-available/$SELECTED_WEBSITE"

  # 获取根目录路径
  DOCUMENT_ROOT=$(grep -E '^\s*root\s+' "$CONFIG_PATH" | awk '{print $2}' | tr -d ';')

  if [ -z "$DOCUMENT_ROOT" ]; then
    echo "无法找到网站根目录路径。"
    return 1
  fi

  echo "当前根目录路径：$DOCUMENT_ROOT"
  echo "目录中的文件夹："
  ls -d "$DOCUMENT_ROOT"/*/ 2>/dev/null || echo "没有子文件夹。"

  return 0
}

# 修改网站配置
modify_website() {
  if ! select_website; then
    return
  fi

  CONFIG_PATH="/etc/nginx/sites-available/$SELECTED_WEBSITE"
  ENABLED_PATH="/etc/nginx/sites-enabled/$SELECTED_WEBSITE"

  if [ ! -f "$CONFIG_PATH" ]; then
    echo "配置文件 $SELECTED_WEBSITE 不存在。"
    return
  fi

  # 获取当前上传文件大小
  CURRENT_UPLOAD_SIZE=$(grep -E '^\s*client_max_body_size\s+' "$CONFIG_PATH" | awk '{print $2}' | tr -d ';')
  if [ -z "$CURRENT_UPLOAD_SIZE" ]; then
    CURRENT_UPLOAD_SIZE="未设置"
  fi
  echo "当前允许上传文件的最大大小：$CURRENT_UPLOAD_SIZE"

  # 检测是否使用SSL
  if grep -Eq 'ssl_certificate_key|ssl_certificate' "$CONFIG_PATH"; then
    CURRENT_SSL="是"
  else
    CURRENT_SSL="否"
  fi
  echo "当前是否使用 SSL：$CURRENT_SSL"

  # 获取当前是否配置 PHP
  if grep -q "fastcgi_pass" "$CONFIG_PATH"; then
    CURRENT_PHP_VERSION=$(grep "fastcgi_pass" "$CONFIG_PATH" | grep -oP 'php\K[0-9.]+(?=-fpm.sock)')
  else
    CURRENT_PHP_VERSION=""
  fi
  echo "当前使用的 PHP 版本：${CURRENT_PHP_VERSION:-未配置}"

  echo "请选择要修改的内容："
  echo "1. 网站类型（目录服务）"
  echo "2. 反向代理目标地址"
  echo "3. 目录服务的根目录路径"
  echo "4. PHP版本"
  echo "5. TLS设置"
  echo "6. 设置网站目录权限"
  echo "7. 指定网站运行目录"
  echo "8. 修改允许上传文件的大小"
  echo "9. 删除该网站配置"
  echo "0. 返回主菜单"
  read -p "请输入选项 [0-9]: " modify_choice

  case $modify_choice in
    1)
      echo "当前网站类型：目录服务"
      echo "请选择新的网站类型："
      echo "1. 目录服务（带PHP支持）"
      read -p "请输入选项 [1]: " new_site_type

      if [[ "$new_site_type" == "1" ]]; then
        read -p "请输入新的网站根目录路径（例如 /var/www/example.com）： " NEW_DOCUMENT_ROOT
        echo "检测已安装的PHP版本..."
        detect_installed_php_versions

        if [ ${#INSTALLED_PHP_VERSIONS[@]} -eq 0 ]; then
          echo "未检测到已安装的PHP版本，请先安装PHP版本。"
          read -p "是否要继续修改为目录服务但不配置PHP？ (y/n): " php_choice
          case $php_choice in
            y|Y )
              NEW_PHP_VERSION=""
              ;;
            *)
              echo "取消修改网站类型。"
              return
              ;;
          esac
        else
          echo "请选择PHP版本："
          select php_version in "${INSTALLED_PHP_VERSIONS[@]}" "不使用PHP"; do
            if [[ -n "$php_version" ]]; then
              if [ "$php_version" == "不使用PHP" ]; then
                NEW_PHP_VERSION=""
              else
                NEW_PHP_VERSION="$php_version"
              fi
              break
            else
              echo "无效的选项。"
            fi
          done
        fi

        read -p "请输入允许上传文件的最大大小（例如 10M，默认 2M）： " NEW_UPLOAD_SIZE
        NEW_UPLOAD_SIZE=${NEW_UPLOAD_SIZE:-2M}

        # 重写配置为目录服务并使用 Let's Encrypt
        if [ -n "$NEW_PHP_VERSION" ]; then
          install_php "$NEW_PHP_VERSION"
          if [ $? -ne 0 ]; then
            echo "PHP安装失败，无法继续修改。"
            return
          fi
          cat > "$CONFIG_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $SELECTED_WEBSITE;

    client_max_body_size $NEW_UPLOAD_SIZE;

    root $NEW_DOCUMENT_ROOT;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$NEW_PHP_VERSION-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
        else
          cat > "$CONFIG_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $SELECTED_WEBSITE;

    client_max_body_size $NEW_UPLOAD_SIZE;

    root $NEW_DOCUMENT_ROOT;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
        fi

        echo "测试 Nginx 配置..."
        nginx -t
        if [ $? -ne 0 ]; then
            echo "Nginx 配置测试失败，请检查配置文件。"
            return
        fi

        echo "重新加载 Nginx..."
        systemctl reload nginx

        echo "安装 Certbot 以申请 Let's Encrypt TLS 证书..."
        install_certbot

        read -p "请输入用于 TLS 证书的邮箱地址： " EMAIL
        certbot --nginx -d "$SELECTED_WEBSITE" --non-interactive --agree-tos -m "$EMAIL" --redirect

        if [ $? -ne 0 ]; then
            echo "Certbot 申请证书失败。请检查域名的 DNS 设置是否正确。"
            return
        fi

        echo "设置自动续期..."
        systemctl enable certbot.timer
        systemctl start certbot.timer

        echo "网站类型已更新为目录服务，并使用 Let's Encrypt 证书。"
      else
        echo "无效的选项。"
        return
      fi
      ;;
    2)
      # 修改反向代理目标地址
      if grep -q "proxy_pass" "$CONFIG_PATH"; then
        read -p "请输入新的反向代理的目标地址（例如 http://localhost:3000）： " NEW_TARGET
        sed -i "s|proxy_pass .*;|proxy_pass $NEW_TARGET;|" "$CONFIG_PATH"
        echo "反向代理目标地址已更新为 $NEW_TARGET。"
      else
        echo "当前不是反向代理配置。"
        return
      fi
      ;;
    3)
      # 修改目录服务的根目录路径
      if grep -q "root " "$CONFIG_PATH"; then
        read -p "请输入新的网站根目录路径（例如 /var/www/example.com）： " NEW_DOCUMENT_ROOT
        sed -i "s|^\s*root\s\+.*;|root $NEW_DOCUMENT_ROOT;|" "$CONFIG_PATH"
        echo "网站根目录路径已更新为 $NEW_DOCUMENT_ROOT。"
      else
        echo "当前不是目录服务配置。"
        return
      fi
      ;;
    4)
      # 修改PHP版本
      if grep -q "fastcgi_pass" "$CONFIG_PATH"; then
        echo "当前使用的PHP版本：${CURRENT_PHP_VERSION:-未配置}"
        echo "请选择新的PHP版本："
        detect_installed_php_versions
        if [ ${#INSTALLED_PHP_VERSIONS[@]} -eq 0 ]; then
          echo "未检测到已安装的PHP版本，请先安装PHP版本。"
          return
        fi
        select NEW_PHP_VERSION in "${INSTALLED_PHP_VERSIONS[@]}"; do
          if [[ -n "$NEW_PHP_VERSION" ]]; then
            break
          else
            echo "无效的选项。"
          fi
        done
        install_php "$NEW_PHP_VERSION"
        if [ $? -ne 0 ]; then
          echo "PHP安装失败，无法继续修改。"
          return
        fi
        sed -i "s|fastcgi_pass unix:/var/run/php/php[0-9.]\+-fpm.sock;|fastcgi_pass unix:/var/run/php/php$NEW_PHP_VERSION-fpm.sock;|" "$CONFIG_PATH"
        updated_php=$(grep "fastcgi_pass" "$CONFIG_PATH" | grep -oP 'php\K[0-9.]+(?=-fpm.sock)')
        if [[ "$updated_php" != "$NEW_PHP_VERSION" ]]; then
          echo "fastcgi_pass 指令替换失败。"
          return
        fi
        echo "fastcgi_pass 已成功更新为 PHP $NEW_PHP_VERSION。"
      else
        echo "当前配置不使用PHP。"
        echo "是否要为网站指定PHP版本？ (y/n): "
        read -p "" php_choice
        case $php_choice in
          y|Y )
            echo "请选择PHP版本："
            detect_installed_php_versions
            if [ ${#INSTALLED_PHP_VERSIONS[@]} -eq 0 ]; then
              echo "未检测到已安装的PHP版本，请先安装PHP版本。"
              return
            fi
            select NEW_PHP_VERSION in "${INSTALLED_PHP_VERSIONS[@]}"; do
              if [[ -n "$NEW_PHP_VERSION" ]]; then
                break
              else
                echo "无效的选项。"
              fi
            done
            install_php "$NEW_PHP_VERSION"
            if [ $? -ne 0 ]; then
              echo "PHP安装失败，无法继续修改。"
              return
            fi
            sed -i "/location \/ {/a \    index index.php index.html index.htm;" "$CONFIG_PATH"
            sed -i "/location \/ {/a \    location ~ \.php\$ {" "$CONFIG_PATH"
            sed -i "/location \/ {/a \        include snippets/fastcgi-php.conf;" "$CONFIG_PATH"
            sed -i "/location \/ {/a \        fastcgi_pass unix:/var/run/php/php$NEW_PHP_VERSION-fpm.sock;" "$CONFIG_PATH"
            sed -i "/location \/ {/a \    }" "$CONFIG_PATH"
            echo "PHP $NEW_PHP_VERSION 已配置到网站。"
            ;;
          *)
            echo "取消指定PHP版本。"
            ;;
        esac
      fi
      ;;
    5)
      # 修改TLS设置
      echo "请选择 TLS 配置方式："
      echo "1. 使用 Let's Encrypt 自动获取证书"
      read -p "请输入选项 [1]: " tls_choice

      if [[ "$tls_choice" == "1" ]]; then
        read -p "请输入用于 TLS 证书的邮箱地址： " EMAIL
        install_certbot
        certbot --nginx -d "$SELECTED_WEBSITE" --non-interactive --agree-tos -m "$EMAIL" --redirect
        if [ $? -ne 0 ]; then
            echo "Certbot 申请证书失败。请检查域名的 DNS 设置是否正确。"
            return
        fi
        echo "设置自动续期..."
        systemctl enable certbot.timer
        systemctl start certbot.timer
        echo "TLS证书已更新为 Let's Encrypt 证书。"
      else
        echo "无效的选项。"
        return
      fi
      ;;
    6)
      # 设置网站目录权限
      echo "请选择操作："
      echo "1. 临时更改目录权限为 777"
      echo "2. 恢复目录权限为 755"
      read -p "请输入选项 [1-2]: " perm_choice

      case $perm_choice in
        1)
          echo "正在将 $DOCUMENT_ROOT 及其子目录权限更改为 777..."
          chmod -R 777 "$DOCUMENT_ROOT"
          if [ $? -eq 0 ]; then
            echo "权限更改成功。"
          else
            echo "权限更改失败。"
          fi
          ;;
        2)
          echo "正在将 $DOCUMENT_ROOT 及其子目录权限恢复为 755..."
          chmod -R 755 "$DOCUMENT_ROOT"
          if [ $? -eq 0 ]; then
            echo "权限恢复成功。"
          else
            echo "权限恢复失败。"
          fi
          ;;
        *)
          echo "无效的选项。"
          ;;
      esac
      ;;
    7)
      # 指定网站运行目录
      read -p "请输入新的运行目录子文件夹名称（相对于根目录，例如 'app'）： " SUB_DIR

      NEW_RUNNING_DIR="$DOCUMENT_ROOT/$SUB_DIR"

      mkdir -p "$NEW_RUNNING_DIR"
      chown -R www-data:www-data "$NEW_RUNNING_DIR"

      sed -i "s|^\s*root\s\+.*;|root $NEW_RUNNING_DIR;|" "$CONFIG_PATH"

      echo "运行目录已更新为 $NEW_RUNNING_DIR。"
      echo "测试 Nginx 配置..."
      nginx -t
      if [ $? -ne 0 ]; then
          echo "Nginx 配置测试失败，请检查配置文件。"
          return
      fi

      echo "重新加载 Nginx..."
      systemctl reload nginx
      echo "运行目录指定完成！你的网站现在可以通过 https://$SELECTED_WEBSITE 访问。"
      ;;
    8)
      # 修改允许上传文件的大小
      read -p "请输入新的允许上传文件的最大大小（例如 10M）： " NEW_UPLOAD_SIZE
      if [ -z "$NEW_UPLOAD_SIZE" ]; then
        echo "输入不能为空。"
        return
      fi

      if grep -q '^\s*client_max_body_size\s\+' "$CONFIG_PATH"; then
        sed -i "s|^[[:space:]]*client_max_body_size[[:space:]]\+.*;|    client_max_body_size $NEW_UPLOAD_SIZE;|" "$CONFIG_PATH"
        echo "已将允许上传文件的最大大小修改为 $NEW_UPLOAD_SIZE。"
      else
        sed -i "/server {/a \    client_max_body_size $NEW_UPLOAD_SIZE;" "$CONFIG_PATH"
        echo "已添加允许上传文件的最大大小为 $NEW_UPLOAD_SIZE。"
      fi
      ;;
    9)
      # 删除该网站配置
      read -p "确定要删除网站 $SELECTED_WEBSITE 的配置吗？此操作将删除配置文件和符号链接，但不会删除网站目录及其内容。 (y/n): " del_confirm
      if [[ "$del_confirm" == "y" || "$del_confirm" == "Y" ]]; then
        rm -f "$CONFIG_PATH"
        rm -f "$ENABLED_PATH"
        echo "网站 $SELECTED_WEBSITE 的配置已删除。"
      else
        echo "取消删除操作。"
      fi
      ;;
    0)
      echo "返回主菜单。"
      return
      ;;
    *)
      echo "无效的选项。"
      return
      ;;
  esac

  if [ "$modify_choice" != "9" ]; then
    echo "测试 Nginx 配置..."
    nginx -t
    if [ $? -ne 0 ]; then
        echo "Nginx 配置测试失败，请检查配置文件。"
        return
    fi

    echo "重新加载 Nginx..."
    systemctl reload nginx

    if [ "$modify_choice" -eq 4 ] && [ -n "$NEW_PHP_VERSION" ]; then
      echo "重启 PHP-FPM 服务..."
      systemctl restart php$NEW_PHP_VERSION-fpm
      if [ $? -ne 0 ]; then
        echo "PHP-FPM 服务重启失败。请检查 PHP-FPM 服务状态。"
        return
      fi
      echo "PHP-FPM 服务已重启。"
    fi

    echo "配置修改完成！"
  fi
}

# 卸载Nginx及相关配置
uninstall_nginx() {
  read -p "确定要卸载 Nginx 及所有配置吗？(y/n): " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "取消卸载。"
    return
  fi

  echo "停止并禁用 Nginx 服务..."
  systemctl stop nginx
  systemctl disable nginx

  echo "卸载 Nginx 和 Certbot..."
  apt remove --purge -y nginx certbot python3-certbot-nginx

  echo "删除 Nginx 配置文件..."
  rm -rf /etc/nginx/sites-available/
  rm -rf /etc/nginx/sites-enabled/

  echo "删除 Certbot 自动续期定时任务..."
  systemctl disable certbot.timer
  systemctl stop certbot.timer

  # 检测并移除防火墙规则
  echo "移除防火墙中开放的端口..."

  if command -v ufw >/dev/null 2>&1; then
    for port in "${REQUIRED_PORTS[@]}"; do
      if ufw status | grep -qw "$port"; then
        echo "移除 ufw 端口 $port ..."
        ufw delete allow "$port"
      fi
    done
  elif systemctl is-active --quiet firewalld; then
    for port in "${REQUIRED_PORTS[@]}"; do
      if firewall-cmd --list-ports | grep -qw "${port}/tcp"; then
        echo "移除 firewalld 端口 $port ..."
        firewall-cmd --permanent --remove-port=${port}/tcp
      fi
    done
    firewall-cmd --reload
  elif command -v iptables >/dev/null 2>&1; then
    for port in "${REQUIRED_PORTS[@]}"; do
      if iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
        echo "移除 iptables 端口 $port ..."
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT
      fi
    done
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save
    elif command -v service >/dev/null 2>&1; then
      service iptables save
    fi
  else
    echo "未检测到已知的防火墙工具（ufw、firewalld、iptables），请手动移除端口 ${REQUIRED_PORTS[*]} 的开放规则。"
  fi

  echo "卸载已完成。"

  echo "是否要卸载已安装的PHP版本？ (y/n): "
  read -p "" uninstall_php_choice
  case $uninstall_php_choice in
    y|Y )
      for version in "${SUPPORTED_PHP_VERSIONS[@]}"; do
        if dpkg -l | grep -qw "php$version-fpm"; then
          echo "卸载 PHP $version ..."
          apt remove --purge -y php$version-fpm php$version-cli php$version-common php$version-mysql php$version-xml php$version-mbstring php$version-curl php$version-zip
        fi
      done
      apt autoremove -y
      echo "PHP 已卸载。"
      ;;
    *)
      echo "保留已安装的PHP版本。"
      ;;
  esac
}

# ------------------------------------------------------------------------------
#                   2) 以下为原 php_imges.sh 功能的整合
# ------------------------------------------------------------------------------

# ==========（A）检测操作系统 & 添加 PHP 仓库等 ==========

DEFAULT_DISABLED_FUNCTIONS=("exec" "passthru" "shell_exec" "system" "proc_open" "popen" "pcntl_exec" "putenv" "getenv" "curl_exec" "curl_multi_exec" "parse_ini_file" "show_source" "proc_get_status" "proc_terminate" "proc_nice" "dl")
AUTO_INSTALL_EXTENSIONS=("zip" "mbstring" "gd")
DEFAULT_UPLOAD_MAX_FILESIZE="50M"
DEFAULT_POST_MAX_SIZE="58M"

# 检测操作系统类型
detect_os_for_php() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo "无法检测操作系统，可能无法正确添加 PHP 源。"
        exit 1
    fi
}

# 添加相应的 PHP 仓库
add_repository_for_php() {
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

# 包是否存在判断
package_exists_for_php() {
    local package="$1"
    if apt-cache show "$package" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 初始化（仅用于添加PHP仓库）
initialize_for_php() {
    detect_os_for_php
    add_repository_for_php
}

# ==========（B）PHP 安装、管理、卸载主菜单 及 相关函数 ==========

# 获取可用的 PHP 版本
php_get_available_versions() {
    AVAILABLE_PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")
}

# 获取已安装的 PHP 版本（基于 dpkg）
php_get_installed_versions() {
    INSTALLED_VERSIONS=()
    for ver in "${AVAILABLE_PHP_VERSIONS[@]}"; do
        if dpkg -l | grep -q "php$ver " ; then
            INSTALLED_VERSIONS+=("$ver")
        fi
    done
}

# 安装 PHP 的菜单函数（**已移除默认禁用函数**）
install_php_menu() {
    local version="7.4"
    echo "即将安装 PHP $version（默认）..."
    # 判断是否已安装
    if dpkg -l | grep -q "php$version " ; then
        echo "PHP $version 已经安装，跳过安装。"
    else
        echo "正在安装 PHP $version..."
        apt install -y php$version php$version-cli php$version-fpm
        if [[ $? -eq 0 ]]; then
            echo "PHP $version 安装成功。"
            # 自动安装指定的扩展
            echo "正在安装必要的 PHP 扩展: ${AUTO_INSTALL_EXTENSIONS[*]}..."
            extension_packages=()
            for ext in "${AUTO_INSTALL_EXTENSIONS[@]}"; do
                local pkg="php$version-$ext"
                if package_exists_for_php "$pkg"; then
                    extension_packages+=("$pkg")
                else
                    echo "警告: 扩展 $ext 对应的包 $pkg 不存在，跳过。"
                fi
            done

            if [[ ${#extension_packages[@]} -gt 0 ]]; then
                apt install -y "${extension_packages[@]}"
                if [[ $? -eq 0 ]]; then
                    echo "PHP 扩展安装成功。"
                    # 启用已安装的扩展
                    echo "正在启用 PHP 扩展: ${AUTO_INSTALL_EXTENSIONS[*]}..."
                    for ext in "${AUTO_INSTALL_EXTENSIONS[@]}"; do
                        local pkg="php$version-$ext"
                        if dpkg -l | grep -q "^ii  $pkg " ; then
                            phpenmod -v "$version" "$ext"
                            if [[ $? -eq 0 ]]; then
                                echo "扩展 $ext 已启用。"
                            else
                                echo "启用扩展 $ext 失败。请手动检查。"
                            fi
                        fi
                    done
                else
                    echo "PHP 扩展安装过程中出现错误。请手动检查。"
                fi
            else
                echo "没有可安装的扩展包，跳过扩展安装。"
            fi

            # 设置上传文件大小限制
            set_upload_file_size "$version"

            # 【去掉禁用函数调用】
            # 原本此处会调用 disable_default_functions "$version"
            # 现已移除，不再禁用任何函数。

            # 重启 PHP-FPM
            restart_php_fpm "$version"
        else
            echo "PHP $version 安装失败。"
        fi
    fi
}

# （以下函数仍保留，以便在“管理 PHP”菜单中使用）

# 禁用指定的 PHP 函数
disable_selected_functions() {
    local version="$1"
    shift
    local functions=("$@")
    local php_ini
    php_ini=$(get_php_ini "$version")
    if [[ -z "$php_ini" ]]; then
        echo "未找到 PHP $version 的 php.ini 文件，无法禁用函数。"
        return
    fi

    echo "正在禁用指定函数..."
    current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')

    for func in "${functions[@]}"; do
        local ftrim=$(echo "$func" | xargs)
        if echo "$current_disabled" | grep -qw "$ftrim"; then
            echo "函数 $ftrim 已经被禁用，跳过。"
        else
            if grep -q "^disable_functions" "$php_ini"; then
                sed -i "/^disable_functions\s*=/ s/$/,${ftrim}/" "$php_ini"
            else
                echo "disable_functions = ${ftrim}" >> "$php_ini"
            fi
            echo "函数 $ftrim 已被禁用。"
            current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')
        fi
    done
    restart_php_fpm "$version"
}

# 设置 PHP 上传文件大小限制
set_upload_file_size() {
    local version="$1"
    local php_ini
    php_ini=$(get_php_ini "$version")
    if [[ -z "$php_ini" ]]; then
        echo "未找到 PHP $version 的 php.ini 文件。无法设置上传文件大小限制。"
        return
    fi

    current_upload_size=$(grep -E "^[; ]*upload_max_filesize" "$php_ini" | awk '{print $3}')
    current_post_size=$(grep -E "^[; ]*post_max_size" "$php_ini" | awk '{print $3}')

    echo "当前 upload_max_filesize: ${current_upload_size:-未设置}"
    echo "当前 post_max_size: ${current_post_size:-未设置}"
    echo

    read -p "请输入新的 upload_max_filesize（默认 ${DEFAULT_UPLOAD_MAX_FILESIZE}）: " new_upload_size
    new_upload_size=${new_upload_size:-$DEFAULT_UPLOAD_MAX_FILESIZE}
    if [[ ! "$new_upload_size" =~ [Mm]$ ]]; then
        new_upload_size="${new_upload_size}M"
    fi

    read -p "请输入新的 post_max_size（默认 ${DEFAULT_POST_MAX_SIZE}）: " new_post_size
    new_post_size=${new_post_size:-$DEFAULT_POST_MAX_SIZE}
    if [[ ! "$new_post_size" =~ [Mm]$ ]]; then
        new_post_size="${new_post_size}M"
    fi

    if grep -Eq "^[; ]*upload_max_filesize" "$php_ini"; then
        sed -i "s/^[; ]*upload_max_filesize\s*=.*/upload_max_filesize = $new_upload_size/" "$php_ini"
    else
        echo "upload_max_filesize = $new_upload_size" >> "$php_ini"
    fi

    if grep -Eq "^[; ]*post_max_size" "$php_ini"; then
        sed -i "s/^[; ]*post_max_size\s*=.*/post_max_size = $new_post_size/" "$php_ini"
    else
        echo "post_max_size = $new_post_size" >> "$php_ini"
    fi

    echo "已设置：upload_max_filesize = $new_upload_size, post_max_size = $new_post_size"
    restart_php_fpm "$version"
}

# 获取 PHP.ini 文件路径
get_php_ini() {
    local version="$1"
    local php_ini_path="/etc/php/$version/fpm/php.ini"
    if [[ ! -f "$php_ini_path" ]]; then
        php_ini_path="/etc/php/$version/cli/php.ini"
        if [[ ! -f "$php_ini_path" ]]; then
            echo ""
            return
        fi
    fi
    echo "$php_ini_path"
}

# 重启 PHP-FPM 服务
restart_php_fpm() {
    local version="$1"
    if systemctl list-unit-files | grep -q "php$version-fpm.service"; then
        systemctl restart "php$version-fpm"
        if [[ $? -eq 0 ]]; then
            echo "PHP $version-FPM 服务已重启。"
        else
            echo "重启 PHP $version-FPM 服务失败。"
        fi
    else
        service "php$version-fpm" restart
        if [[ $? -eq 0 ]]; then
            echo "PHP $version-FPM 服务已重启。"
        else
            echo "重启 PHP $version-FPM 服务失败。"
        fi
    fi
}

# 安装 PHP 扩展
install_php_extensions() {
    local version="$1"
    echo "正在为 PHP $version 安装扩展..."
    read -p "请输入要安装的扩展（用逗号分隔）: " exts
    IFS=',' read -ra arr <<< "$exts"
    local installed=()
    local skipped=()
    local to_install=()

    for ext in "${arr[@]}"; do
        local e=$(echo "$ext" | xargs)
        local pkg="php$version-$e"
        if dpkg -l | grep -q "^ii  $pkg "; then
            skipped+=("$e")
        else
            if package_exists_for_php "$pkg"; then
                to_install+=("$pkg")
            else
                echo "警告: 不存在包 $pkg，跳过。"
            fi
        fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        echo "apt install -y ${to_install[*]}"
        apt install -y "${to_install[@]}"
        if [[ $? -eq 0 ]]; then
            for pkg in "${to_install[@]}"; do
                local e_name=${pkg#php$version-}
                installed+=("$e_name")
                phpenmod -v "$version" "$e_name"
            done
        else
            echo "安装扩展过程中出现错误。"
        fi
    fi

    echo "安装完成。"
    if [[ ${#installed[@]} -gt 0 ]]; then
        echo "已安装并启用的扩展: ${installed[*]}"
    fi
    if [[ ${#skipped[@]} -gt 0 ]]; then
        echo "跳过的扩展（已存在）: ${skipped[*]}"
    fi

    restart_php_fpm "$version"
}

# 卸载 PHP 扩展
uninstall_php_extensions() {
    local version="$1"
    echo "正在卸载 PHP $version 扩展..."
    read -p "请输入要卸载的扩展（用逗号分隔）: " exts
    IFS=',' read -ra arr <<< "$exts"
    local uninstalled=()
    local skipped=()

    for ext in "${arr[@]}"; do
        local e=$(echo "$ext" | xargs)
        local pkg="php$version-$e"
        if dpkg -l | grep -q "^ii  $pkg "; then
            apt purge -y "$pkg"
            if [[ $? -eq 0 ]]; then
                uninstalled+=("$e")
            else
                echo "卸载扩展 $e 失败。"
            fi
        else
            skipped+=("$e")
        fi
    done

    echo "卸载完成。"
    if [[ ${#uninstalled[@]} -gt 0 ]]; then
        echo "已卸载的扩展: ${uninstalled[*]}"
    fi
    if [[ ${#skipped[@]} -gt 0 ]]; then
        echo "跳过的扩展（未安装）: ${skipped[*]}"
    fi

    restart_php_fpm "$version"
}

# 禁用 PHP 函数
disable_php_functions() {
    local version="$1"
    echo "禁用 PHP $version 函数"
    local php_ini
    php_ini=$(get_php_ini "$version")
    if [[ -z "$php_ini" ]]; then
        echo "未找到 php.ini。"
        return
    fi
    current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')
    if [[ -n "$current_disabled" ]]; then
        echo "当前已禁用的函数：$current_disabled"
    else
        echo "当前未禁用任何函数。"
    fi

    read -p "请输入要禁用的函数（逗号分隔）: " input_funcs
    IFS=',' read -ra arr <<< "$input_funcs"

    for func in "${arr[@]}"; do
        local f=$(echo "$func" | xargs)
        if echo "$current_disabled" | grep -qw "$f"; then
            echo "函数 $f 已禁用，跳过。"
        else
            if grep -q "^disable_functions" "$php_ini"; then
                if [[ -z "$current_disabled" ]]; then
                    new_disabled="$f"
                else
                    new_disabled="$current_disabled,$f"
                fi
                sed -i "s/^disable_functions\s*=.*/disable_functions = $new_disabled/" "$php_ini"
            else
                echo "disable_functions = $f" >> "$php_ini"
            fi
            echo "函数 $f 已被禁用。"
            current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')
        fi
    done

    restart_php_fpm "$version"
}

# 启用（解除禁用）PHP 函数
enable_php_functions() {
    local version="$1"
    echo "解除禁用 PHP $version 函数"
    local php_ini
    php_ini=$(get_php_ini "$version")
    if [[ -z "$php_ini" ]]; then
        echo "未找到 php.ini。"
        return
    fi
    current_disabled=$(grep -i "^disable_functions" "$php_ini" | cut -d'=' -f2 | tr -d ' ' | tr ',' ' ')
    if [[ -n "$current_disabled" ]]; then
        echo "当前已禁用的函数：$current_disabled"
    else
        echo "当前没有禁用任何函数。"
    fi

    read -p "请输入要启用的函数（逗号分隔）: " input_funcs
    IFS=',' read -ra arr <<< "$input_funcs"

    for func in "${arr[@]}"; do
        local f=$(echo "$func" | xargs)
        if echo "$current_disabled" | grep -qw "$f"; then
            new_disabled=$(echo "$current_disabled" | sed "s/\b$f\b//g" | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')
            if [[ -z "$new_disabled" ]]; then
                sed -i "/^disable_functions\s*=/d" "$php_ini"
                current_disabled=""
            else
                sed -i "s/^disable_functions\s*=.*/disable_functions = $new_disabled/" "$php_ini"
                current_disabled="$new_disabled"
            fi
            echo "函数 $f 已被解除禁用。"
        else
            echo "函数 $f 未禁用，跳过。"
        fi
    done

    restart_php_fpm "$version"
}

# 卸载指定 PHP 版本
uninstall_php_version() {
    php_get_available_versions
    php_get_installed_versions
    if [[ ${#INSTALLED_VERSIONS[@]} -eq 0 ]]; then
        echo "没有已安装的 PHP 版本可卸载。"
        return
    fi

    echo "已安装的 PHP 版本："
    for i in "${!INSTALLED_VERSIONS[@]}"; do
        echo "$((i+1)). PHP ${INSTALLED_VERSIONS[i]}"
    done
    read -p "请选择要卸载的 PHP 版本编号: " sel
    if [[ "$sel" -ge 1 && "$sel" -le "${#INSTALLED_VERSIONS[@]}" ]]; then
        local version="${INSTALLED_VERSIONS[$((sel-1))]}"
        read -p "确定要卸载 PHP $version 吗？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "正在卸载 PHP $version ..."
            apt purge -y "php$version" "php$version-cli" "php$version-fpm"
            # 顺便卸载自动安装的扩展
            for ext in "${AUTO_INSTALL_EXTENSIONS[@]}"; do
                local pkg="php$version-$ext"
                if dpkg -l | grep -q "^ii  $pkg "; then
                    apt purge -y "$pkg"
                fi
            done
            apt autoremove -y
            echo "PHP $version 已卸载。"
        else
            echo "取消卸载。"
        fi
    else
        echo "无效选择。"
    fi
}

# PHP 管理子菜单
php_main_menu() {
  while true; do
    echo "=============================="
    echo "     PHP 管理功能菜单"
    echo "=============================="
    echo "1. 安装 PHP (默认 7.4)"
    echo "2. 管理已安装 PHP"
    echo "3. 卸载 PHP 版本"
    echo "0. 返回主菜单"
    echo "=============================="
    read -p "请输入选项: " choice
    case $choice in
      0)
        echo "返回主菜单。"
        return
        ;;
      1)
        install_php_menu
        ;;
      2)
        manage_installed_php
        ;;
      3)
        uninstall_php_version
        ;;
      *)
        echo "无效的选项。"
        ;;
    esac
  done
}

# 管理已安装 PHP
manage_installed_php() {
    php_get_available_versions
    php_get_installed_versions
    if [[ ${#INSTALLED_VERSIONS[@]} -eq 0 ]]; then
        echo "当前无已安装的 PHP 版本。"
        return
    fi
    echo "已安装 PHP 版本列表："
    for i in "${!INSTALLED_VERSIONS[@]}"; do
        echo "$((i+1)). PHP ${INSTALLED_VERSIONS[i]}"
    done
    echo "$(( ${#INSTALLED_VERSIONS[@]} +1 )). 返回上级菜单"
    read -p "请选择要管理的 PHP 版本: " sel
    if [[ "$sel" -ge 1 && "$sel" -le "${#INSTALLED_VERSIONS[@]}" ]]; then
        local version="${INSTALLED_VERSIONS[$((sel-1))]}"
        php_manage_menu "$version"
    elif [[ "$sel" -eq $(( ${#INSTALLED_VERSIONS[@]} +1 )) ]]; then
        return
    else
        echo "无效选择。"
    fi
}

# 管理单个版本的详细菜单
php_manage_menu() {
    local version="$1"
    while true; do
        echo "=============================="
        echo "   管理 PHP $version"
        echo "=============================="
        echo "1. 安装扩展"
        echo "2. 卸载扩展"
        echo "3. 禁用函数"
        echo "4. 解除禁用函数"
        echo "5. 设置上传文件大小限制"
        echo "0. 返回上一层"
        echo "=============================="
        read -p "请输入选项: " choice
        case $choice in
            0)  return ;;
            1)  install_php_extensions "$version" ;;
            2)  uninstall_php_extensions "$version" ;;
            3)  disable_php_functions "$version" ;;
            4)  enable_php_functions "$version" ;;
            5)  set_upload_file_size "$version" ;;
            *)
                echo "无效的选项。"
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
#                   3) 主循环菜单（综合了原 nginx_images.sh + 新增PHP）
# ------------------------------------------------------------------------------

while true; do
  echo "╔═══════════════════════════════════════════════╗"
  echo "║          一点科技 简单图床 安装脚本           ║"
  echo "╠═══════════════════════════════════════════════╣"
  echo "║ 作者：1点科技                                 ║"
  echo "║ 网站：https://1keji.net                       ║"
  echo "║ YouTube：https://www.youtube.com/@1keji_net   ║"
  echo "╚═══════════════════════════════════════════════╝"
  echo "=================================="
  echo "1. 安装 Nginx + PHP"
  echo "2. 添加网站配置"
  echo "3. 修改网站配置"
  echo "4. 卸载 Nginx 和所有配置"
  echo "5. 管理 PHP"
  echo "0. 退出"
  echo "=================================="
  read -p "请选择一个选项 [0-5]: " choice

  case $choice in
    1)
      install_nginx
      ;;
    2)
      add_website
      ;;
    3)
      modify_website
      ;;
    4)
      uninstall_nginx
      ;;
    5)
      php_main_menu
      ;;
    0)
      echo "退出脚本。"
      exit 0
      ;;
    *)
      echo "无效的选项，请重新选择。"
      ;;
  esac

  echo ""
done
