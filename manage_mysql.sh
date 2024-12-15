#!/usr/bin/env python3
import os
import subprocess
import sys
import mysql.connector
from mysql.connector import errorcode

def clear_screen():
    os.system('clear' if os.name == 'posix' else 'cls')

def pause():
    input("按 Enter 键继续...")

def install_mysql():
    clear_screen()
    print("=== 安装 MySQL ===")
    print("可用版本:")
    versions = ['5.7', '8.0']
    for idx, ver in enumerate(versions, start=1):
        print(f"{idx}. MySQL {ver}")
    choice = input("请选择要安装的MySQL版本 (数字): ")
    try:
        choice = int(choice)
        if choice < 1 or choice > len(versions):
            print("无效的选择。")
            pause()
            return
        selected_version = versions[choice - 1]
    except ValueError:
        print("请输入有效的数字。")
        pause()
        return

    # 更新包列表
    print("更新包列表...")
    subprocess.run(['sudo', 'apt', 'update'], check=True)

    # 安装MySQL
    print(f"正在安装 MySQL {selected_version}...")
    try:
        subprocess.run(['sudo', 'apt', 'install', f'mysql-server-{selected_version}', '-y'], check=True)
        print(f"MySQL {selected_version} 安装成功。")
    except subprocess.CalledProcessError:
        print("安装过程中出现错误。")
    pause()

def connect_mysql():
    try:
        conn = mysql.connector.connect(
            host='localhost',
            user='root',
            password=''  # 根据需要修改密码
        )
        return conn
    except mysql.connector.Error as err:
        if err.errno == errorcode.ER_ACCESS_DENIED_ERROR:
            print("用户名或密码错误。")
        elif err.errno == errorcode.ER_BAD_DB_ERROR:
            print("数据库不存在。")
        else:
            print(err)
        return None

def add_database():
    clear_screen()
    print("=== 添加数据库 ===")
    db_name = input("请输入要创建的数据库名称: ").strip()
    if not db_name:
        print("数据库名称不能为空。")
        pause()
        return

    conn = connect_mysql()
    if conn:
        cursor = conn.cursor()
        try:
            cursor.execute(f"CREATE DATABASE `{db_name}`;")
            print(f"数据库 `{db_name}` 创建成功。")
        except mysql.connector.Error as err:
            print(f"创建数据库时出错: {err}")
        finally:
            cursor.close()
            conn.close()
    pause()

def list_databases():
    conn = connect_mysql()
    if conn:
        cursor = conn.cursor()
        cursor.execute("SHOW DATABASES;")
        databases = cursor.fetchall()
        print("已存在的数据库:")
        for db in databases:
            print(f"- {db[0]}")
        cursor.close()
        conn.close()
    else:
        print("无法连接到MySQL服务器。")
    pause()

def manage_database():
    clear_screen()
    print("=== 管理数据库 ===")
    print("1. 查看数据库列表")
    print("2. 删除数据库")
    print("3. 重命名数据库")
    print("0. 返回主菜单")
    choice = input("请选择操作 (数字): ")
    if choice == '1':
        list_databases()
    elif choice == '2':
        delete_database()
    elif choice == '3':
        rename_database()
    elif choice == '0':
        return
    else:
        print("无效的选择。")
        pause()

def delete_database():
    db_name = input("请输入要删除的数据库名称: ").strip()
    if not db_name:
        print("数据库名称不能为空。")
        pause()
        return
    confirmation = input(f"确认要删除数据库 `{db_name}` 吗？请输入 'DELETE': ")
    if confirmation != 'DELETE':
        print("未确认删除。")
        pause()
        return

    conn = connect_mysql()
    if conn:
        cursor = conn.cursor()
        try:
            cursor.execute(f"DROP DATABASE `{db_name}`;")
            print(f"数据库 `{db_name}` 已删除。")
        except mysql.connector.Error as err:
            print(f"删除数据库时出错: {err}")
        finally:
            cursor.close()
            conn.close()
    pause()

def rename_database():
    old_name = input("请输入要重命名的数据库名称: ").strip()
    new_name = input("请输入新的数据库名称: ").strip()
    if not old_name or not new_name:
        print("数据库名称不能为空。")
        pause()
        return

    # MySQL不直接支持重命名数据库，需要通过备份和恢复
    conn = connect_mysql()
    if conn:
        cursor = conn.cursor()
        try:
            # 导出旧数据库
            dump_file = f"/tmp/{old_name}.sql"
            subprocess.run(['mysqldump', '-u', 'root', old_name, '-r', dump_file], check=True)
            # 创建新数据库
            cursor.execute(f"CREATE DATABASE `{new_name}`;")
            # 导入到新数据库
            subprocess.run(['mysql', '-u', 'root', new_name, '-e', f"source {dump_file}"], check=True)
            # 删除旧数据库
            cursor.execute(f"DROP DATABASE `{old_name}`;")
            # 删除临时文件
            os.remove(dump_file)
            print(f"数据库 `{old_name}` 已重命名为 `{new_name}`。")
        except subprocess.CalledProcessError as e:
            print(f"重命名数据库时出现错误: {e}")
        except mysql.connector.Error as err:
            print(f"数据库操作时出错: {err}")
        finally:
            cursor.close()
            conn.close()
    pause()

def uninstall_mysql():
    clear_screen()
    print("=== 卸载 MySQL ===")
    confirmation = input("请输入 '确认卸载MySQL数据库' 以继续: ")
    if confirmation != '确认卸载MySQL数据库':
        print("未确认卸载。")
        pause()
        return

    try:
        print("停止 MySQL 服务...")
        subprocess.run(['sudo', 'systemctl', 'stop', 'mysql'], check=True)
        print("卸载 MySQL 包...")
        subprocess.run(['sudo', 'apt', 'remove', '--purge', 'mysql-server', '-y'], check=True)
        print("自动删除不需要的包...")
        subprocess.run(['sudo', 'apt', 'autoremove', '-y'], check=True)
        print("删除MySQL配置和数据文件...")
        subprocess.run(['sudo', 'rm', '-rf', '/etc/mysql/', '/var/lib/mysql/', '/var/log/mysql/'], check=True)
        print("MySQL 已成功卸载。")
    except subprocess.CalledProcessError:
        print("卸载过程中出现错误。")
    pause()

def main_menu():
    while True:
        clear_screen()
        print("=== MySQL 安装与管理脚本 ===")
        print("1. 安装 MySQL")
        print("2. 添加数据库")
        print("3. 管理数据库")
        print("4. 卸载 MySQL")
        print("0. 退出脚本")
        choice = input("请选择操作 (数字): ")

        if choice == '1':
            install_mysql()
        elif choice == '2':
            add_database()
        elif choice == '3':
            manage_database()
        elif choice == '4':
            uninstall_mysql()
        elif choice == '0':
            print("退出脚本。")
            sys.exit(0)
        else:
            print("无效的选择。")
            pause()

if __name__ == "__main__":
    try:
        main_menu()
    except KeyboardInterrupt:
        print("\n脚本被用户中断。")
        sys.exit(0)
