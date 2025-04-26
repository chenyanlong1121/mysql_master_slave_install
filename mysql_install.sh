#!/bin/sh

if [ $# -ne 2 ] ; then
echo -e "\e[31m 当前配置参数有误，以下是示例： \e[0m"
echo -e  "\e[33m  USAGE: sh mysql_install.sh  角色   mysql的数据路径（大磁盘路径）\e[0m"
echo -e  "\e[33m  e.g.: sh mysql_install.sh   master  /home \e[0m"
echo -e  "\e[33m  e.g.: 角色分为master、slave这两种 \e[0m"
exit 1;
fi
echo -e "\e[32m 请确认mysql安装配置信息 \e[0m  "

MYSQL_ROLE=$1
MASTER_DATA_PATH=$2

#一、设置服务器
#关闭防火墙
systemctl  stop firewalld
systemctl disable firewalld
#设置程序打开文件/socket连接数
ulimit -n 655350
cat >> /etc/security/limits.conf << EOF
* soft nofile 655350
* hard nofile 655350
EOF

#安装时间同步
rpm -q chrony
if [ $(echo $?) -gt 0 ];then
  echo "开始安装时钟同步服务"
  rpm -ivh  ./chrony-pkg/*.rpm --force --nodeps
  #时间同步配置 使用阿里云校时服务器，若无外网可设置其它服务校时
  sed -i "s/^server/#server/g" /etc/chrony.conf
  echo "server ntp1.aliyun.com iburst" >> /etc/chrony.conf
  systemctl enable chronyd
  systemctl restart chronyd
  echo "成功安装时钟同步服务"
else
  echo "已安装时钟同步服务，跳过安装"
fi

#二、安装mysql
echo -e "\e[32m 开始安装mysql \e[0m"
#创建mysql安装路径
mkdir -p /usr/local/mysql-8.0.20
#创建mysql数据目录
mkdir -p $MASTER_DATA_PATH/mysql_data
#解压安装包
tar -xvf mysql-8.0.20-linux-glibc2.12-x86_64.tar.xz
#拷贝到/usr/local/mysql-8.0.20
mv mysql-8.0.20-linux-glibc2.12-x86_64/*  /usr/local/mysql-8.0.20
# 创建用户及用户组
groupadd mysql
useradd -g mysql mysql
# 授权
chown -R mysql.mysql /usr/local/mysql-8.0.20
chown -R mysql.mysql $MASTER_DATA_PATH
/usr/local/mysql-8.0.20/bin/mysqld --user=mysql --lower-case-table-names=1 --basedir=/usr/local/mysql-8.0.20/ --datadir=$MASTER_DATA_PATH/mysql_data/ --initialize-insecure

cat > /etc/my.cnf << EOF
[mysqld]
basedir=/usr/local/mysql-8.0.20
datadir=$MASTER_DATA_PATH/mysql_data
character-set-server=utf8
default_authentication_plugin=mysql_native_password
skip-host-cache
skip-name-resolve
max_connections=2000
lower_case_table_names=1
default-time-zone='+08:00'
sql_mode='STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'
log_timestamps='SYSTEM'
slow_query_log=ON
expire_logs_days=7
# todo：调整设置为所分配内存的70%~80% innodb_buffer_pool_size=10G
#innodb_force_recovery=0

# 主从复制-主机配置
# 主服务器唯一ID
server-id=1
# 启用二进制日志
log-bin=mysql-bin
# 设置logbin格式
binlog_format=STATEMENT
skip-grant-tables
EOF

if [ "$MYSQL_ROLE" = "slave" ];then
  sed -i "s/server-id=1/server-id=2/g" /etc/my.cnf
  cat >> /etc/my.cnf << EOF
# 启用中继日志
relay-log=mysql-relay
EOF
fi

# 建立Mysql服务
cp -a /usr/local/mysql-8.0.20/support-files/mysql.server /etc/init.d/mysql
chmod +x /etc/init.d/mysql
chkconfig --add mysql
# 检查服务是否生效
echo -e "\e[32m 检查mysql服务是否生效 \e[0m"
systemctl list-dependencies mysql |grep mysql
#启动mysql并设置开机启动
systemctl start mysql 
systemctl enable mysql

#等待mysql服务启动
echo "等待20s"
for ((i=0;$i<=100;i++))
do
let jinshu=$i*1
printf "[%-100s]%d%%\r" $b $jinshu
sleep 0.2
b=#$b
done

#创建mysql的软连接并设置密码
echo -e "\e[32m 创建mysql的软连接并设置密码 \e[0m"
ln -s /usr/local/mysql-8.0.20/bin/mysql /usr/bin

#替换/etc/my.cnf配置的skip-grant-tables并重启服务器
sed -i "s/skip-grant-tables//g" /etc/my.cnf
echo "设置root账户密码"
mysql  <<EOF

use mysql;

update user set host ='%' where user='root';
flush privileges;

alter user 'root'@'%' identified with mysql_native_password by 'supconit';
flush privileges;
EOF
echo "设置root账户密码完成"
systemctl daemon-reload
systemctl stop mysql
systemctl start mysql

#若是master 为mysql创建slave用户:用于数据同步
if [ "$MYSQL_ROLE" = "master" ];then
echo -e "\e[32m master数据库为slave创建用户：用于数据同步\e[0m"
mysql -u root -psupconit <<EOF
use mysql;
create user 'slave'@'%' identified with mysql_native_password by 'supconit';
grant replication slave on *.* to 'slave'@'%';
flush privileges;
EOF
fi

echo -e "\e[34m ********************  \e[0m"
echo -e "\e[32m mysql常见命令  \e[0m"
echo -e "\e[32m 启动命令：systemctl start mysql  \e[0m"
echo -e "\e[32m 停止命令：systemctl stop mysql  \e[0m"
echo -e "\e[32m 重启命令：systemctl restart mysql  \e[0m"
echo -e "\e[32m 状态命令：systemctl status  mysql  \e[0m"
echo -e "\e[32m 日志命令：journalctl -u mysql --no-pager  \e[0m"
echo -e "\e[31m 说    明：mysql默认root密码是supconit  \e[0m"
echo -e "\e[34m ********************  \e[0m"
