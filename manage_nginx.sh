#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root用户运行此脚本。"
  exit 1
fi

# 定义需要打开的端口
REQUIRED_PORTS=(80 443)

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

# 检测已安装的PHP版本
detect_installed_php_versions() {
  echo "检测已安装的PHP版本..."
  INSTALLED_PHP_VERSIONS=()
  for version in $(ls /etc/init.d/ | grep php | awk -F 'php' '{print $2}' | awk -F '-fpm' '{print $1}'); do
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

# 安装指定的PHP版本
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

# 安装Nginx
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
}

# 配置反向代理
configure_reverse_proxy() {
  read -p "请输入你的邮箱地址（用于 Let's Encrypt 通知）： " EMAIL
  read -p "请输入你的域名（例如 example.com 或 sub.example.com）： " DOMAIN
  echo "请选择反向代理的目标地址类型："
  echo "1. HTTP"
  echo "2. HTTPS"
  read -p "请输入选项 [1-2]: " proxy_type

  read -p "请输入反向代理的目标地址（例如 http://localhost:3000 或 https://localhost:3000）： " TARGET

  CONFIG_PATH="/etc/nginx/sites-available/$DOMAIN"
  ENABLED_PATH="/etc/nginx/sites-enabled/$DOMAIN"

  echo "配置 Nginx 反向代理..."
  cat > "$CONFIG_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location / {
        proxy_pass $TARGET;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 可选：设置 WebSocket 的超时时间
        proxy_read_timeout 86400;
    }
}
EOF

  echo "创建符号链接到 sites-enabled..."
  ln -s "$CONFIG_PATH" "$ENABLED_PATH"

  echo "测试 Nginx 配置..."
  nginx -t

  if [ $? -ne 0 ]; then
      echo "Nginx 配置测试失败，请检查配置文件。"
      rm "$ENABLED_PATH"
      return
  fi

  echo "重新加载 Nginx..."
  systemctl reload nginx

  echo "申请 Let's Encrypt TLS 证书..."
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect

  if [ $? -ne 0 ]; then
      echo "Certbot 申请证书失败。请检查域名的 DNS 设置是否正确。"
      exit 1
  fi

  echo "设置自动续期..."
  systemctl enable certbot.timer
  systemctl start certbot.timer

  echo "反向代理配置完成！你的网站现在可以通过 https://$DOMAIN 访问。"
}

# 添加网站配置
add_website() {
  read -p "请输入要添加的域名（例如 example.com 或 sub.example.com）： " DOMAIN
  if [ -f "/etc/nginx/sites-available/$DOMAIN" ]; then
    echo "配置文件 $DOMAIN 已存在。"
    return
  fi

  read -p "请输入用于 TLS 证书的邮箱地址： " EMAIL

  read -p "请输入网站的根目录路径（默认 /var/www/$DOMAIN/html）： " DOCUMENT_ROOT
  DOCUMENT_ROOT=${DOCUMENT_ROOT:-"/var/www/$DOMAIN/html"}

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

  echo "网站配置完成！你的网站现在可以通过 https://$DOMAIN 访问。"
}

# 修改网站配置
modify_website() {
  echo "当前配置列表："
  ls /etc/nginx/sites-available/
  read -p "请输入要修改的域名（配置文件名）： " DOMAIN

  CONFIG_PATH="/etc/nginx/sites-available/$DOMAIN"
  ENABLED_PATH="/etc/nginx/sites-enabled/$DOMAIN"

  if [ ! -f "$CONFIG_PATH" ]; then
    echo "配置文件 $DOMAIN 不存在。"
    return
  fi

  # 询问修改类型
  echo "请选择要修改的内容："
  echo "1. 网站类型（反向代理或目录服务）"
  echo "2. 反向代理目标地址"
  echo "3. 目录服务的根目录路径"
  echo "4. PHP版本"
  echo "5. TLS设置"
  read -p "请输入选项 [1-5]: " modify_choice

  case $modify_choice in
    1)
      echo "当前网站类型："
      if grep -q "proxy_pass" "$CONFIG_PATH"; then
        current_type="反向代理"
      else
        current_type="目录服务"
      fi
      echo "$current_type"
      echo "请选择新的网站类型："
      echo "1. 反向代理"
      echo "2. 目录服务（带PHP支持）"
      read -p "请输入选项 [1-2]: " new_site_type

      case $new_site_type in
        1)
          read -p "请输入新的反向代理的目标地址（例如 http://localhost:3000）： " NEW_TARGET
          read -p "请输入用于 TLS 证书的邮箱地址： " EMAIL

          # 重写配置
          cat > "$CONFIG_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location / {
        proxy_pass $NEW_TARGET;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 可选：设置 WebSocket 的超时时间
        proxy_read_timeout 86400;
    }
}
EOF
          ;;
        2)
          read -p "请输入新的网站根目录路径（例如 /var/www/example.com/html）： " NEW_DOCUMENT_ROOT
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
    server_name $DOMAIN;

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
    server_name $DOMAIN;

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
          ;;
        *)
          echo "无效的选项。"
          return
          ;;
      esac
      ;;
    2)
      # 修改反向代理目标地址
      if grep -q "proxy_pass" "$CONFIG_PATH"; then
        read -p "请输入新的反向代理的目标地址（例如 http://localhost:3000）： " NEW_TARGET
        sed -i "s|proxy_pass .*;|proxy_pass $NEW_TARGET;|" "$CONFIG_PATH"
      else
        echo "当前不是反向代理配置。"
        return
      fi
      ;;
    3)
      # 修改目录服务的根目录路径
      if grep -q "root " "$CONFIG_PATH"; then
        read -p "请输入新的网站根目录路径（例如 /var/www/example.com/html）： " NEW_DOCUMENT_ROOT
        sed -i "s|root .*;|root $NEW_DOCUMENT_ROOT;|" "$CONFIG_PATH"
      else
        echo "当前不是目录服务配置。"
        return
      fi
      ;;
    4)
      # 修改PHP版本
      if grep -q "fastcgi_pass" "$CONFIG_PATH"; then
        echo "当前使用的PHP版本："
        current_php=$(grep "fastcgi_pass" "$CONFIG_PATH" | awk -F'php' '{print $2}' | awk -F'-fpm' '{print $1}')
        echo "$current_php"
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
        sed -i "s|fastcgi_pass unix:/var/run/php/php.*-fpm.sock;|fastcgi_pass unix:/var/run/php/php$NEW_PHP_VERSION-fpm.sock;|" "$CONFIG_PATH"
      else
        echo "当前配置不使用PHP。"
        return
      fi
      ;;
    5)
      # 修改TLS设置
      read -p "是否要更新TLS证书？ (y/n): " tls_choice
      if [[ "$tls_choice" == "y" || "$tls_choice" == "Y" ]]; then
        read -p "请输入用于 TLS 证书的邮箱地址： " EMAIL
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
        if [ $? -ne 0 ]; then
            echo "Certbot 申请证书失败。请检查域名的 DNS 设置是否正确。"
            return
        fi
        echo "TLS证书更新完成。"
      else
        echo "跳过TLS证书更新。"
      fi
      ;;
    *)
      echo "无效的选项。"
      return
      ;;
  esac

  echo "测试 Nginx 配置..."
  nginx -t

  if [ $? -ne 0 ]; then
      echo "Nginx 配置测试失败，请检查配置文件。"
      return
  fi

  echo "重新加载 Nginx..."
  systemctl reload nginx

  echo "配置修改完成！你的网站现在可以通过 https://$DOMAIN 访问。"
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
    # 保存 iptables 规则（根据系统不同，可能需要调整）
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save
    elif command -v service >/dev/null 2>&1; then
      service iptables save
    fi
  else
    echo "未检测到已知的防火墙工具（ufw、firewalld、iptables），请手动移除端口 ${REQUIRED_PORTS[*]} 的开放规则。"
  fi

  echo "卸载已完成。"

  # 可选：卸载已安装的PHP版本
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

# 显示菜单
while true; do
  echo "======**一点科技**================"
  echo "      Nginx 管理脚本"
  echo "  博  客： https://1keji.net"
  echo "  YouTube：https://www.youtube.com/@1keji_net"
  echo "  GitHub： https://github.com/1keji"
  echo "==============================="
  echo "1. 安装 Nginx"
  echo "2. 添加网站配置"
  echo "3. 修改网站配置"
  echo "4. 配置反向代理"
  echo "5. 卸载 Nginx 和所有配置"
  echo "0. 退出"
  echo "==============================="
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
      configure_reverse_proxy
      ;;
    5)
      uninstall_nginx
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
