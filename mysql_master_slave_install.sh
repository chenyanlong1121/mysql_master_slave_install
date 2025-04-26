#!/bin/sh
echo -e "\e[32m mysql的安装分为主从复制（双机热备）、单机安装，配置一个节点信息为单机mysql安装，配置两个节点为主从复制。"
MOD_NUM=$(($# % 3))
if [ $# -lt 3 -o $MOD_NUM  != 0 ] ; then
echo -e "\e[31m 当前配置参数有误，以下是示例： \e[0m"
echo -e  "\e[33m  USAGE: sh mysql_master_slave_install.sh  mysql的master节点IP地址(本机)  master节点root密码(请记住就是本机的)  mysql的master存储数据路径（大磁盘路径）   mysql的slave节点2IP地址  mysql的slave节点root密码  mysql的slave存储数据路径（大磁盘路径）  \e[0m"
echo -e "\e[33m  e.g.: sh mysql_master_slave_install.sh  172.20.41.32  supconit /home/mysql-data  172.20.41.36  supconit  /home/mysql-data \e[0m"
echo -e "\e[33m  注意slave要开放22端口或者替换脚本sshpass命令里的22端口 \e[0m"
exit 1;
fi
echo -e "\e[32m 请确认mysql安装配置信息 \e[0m  "

MASTER_IP=$1
MASTER_PASSWD=$2
MASTER_DATA_PATH=$3
SLAVE_IP=$4
SLAVE_PASSWD=$5
SLAVE_DATA_PATH=$6

NODE_NUM=$((($#) / 3))

if [ $NODE_NUM -eq 1 ];then
echo -e "\e[34m ********************  \e[0m"
echo -e "\e[32m mysql安装为单机安装 \e[0m"
echo -e "\e[32m mysql的master节点IP地址(本机)：$MASTER_IP \e[0m"
echo -e "\e[32m master节点root密码：$MASTER_PASSWD \e[0m"
echo -e "\e[32m mysql的master存储数据路径：$MASTER_DATA_PATH \e[0m"
echo -e "\e[34m ********************  \e[0m"
fi
if [ $NODE_NUM -eq 2 ];then
echo -e "\e[34m ********************  \e[0m"
echo -e "\e[32m mysql安装为主从复制（双机热备）安装 \e[0m"
echo -e "\e[32m mysql的master节点IP地址(本机)：$MASTER_IP \e[0m"
echo -e "\e[32m master节点root密码：$MASTER_PASSWD \e[0m"
echo -e "\e[32m mysql的master存储数据路径：$MASTER_DATA_PATH \e[0m"
echo -e "\e[32m mysql的slave节点2IP地址：$SLAVE_IP \e[0m"
echo -e "\e[32m mysql的slave节点root密码:$SLAVE_PASSWD \e[0m"
echo -e "\e[32m mysql的slave存储数据路径:$SLAVE_DATA_PATH \e[0m"
echo -e "\e[34m ********************  \e[0m"
fi

if [ $NODE_NUM -lt 1 -o $NODE_NUM -gt 2 ];then
echo -e "\e[32m 当前配置参数有误且仅支持单机安装或双机热备安装，请确认输入参数 \e[0m"
exit 1
fi

read -r -p "请确认上述配置,是否继续? [Y/n] " input
case $input in
    [yY][eE][sS]|[yY])
        
        if [ $NODE_NUM -eq 2 ];then
	 #安装sshpass
	 echo "安装sshpass"
 	 rpm -q sshpass
	 if [ $(echo $?) -gt 0 ];then
  	   echo "开始安装sshpass"
 	   rpm -vih sshpass-1.05-1.el7.rf.x86_64.rpm  --force --nodeps
  	   echo "成功安装sshpass命令"
	 else
           echo "已安装sshpass命令，跳过安装"
	 fi	        
	 #往slave创建文件夹及文件发送
	 echo -e "\e[32m 正在往slave服务器发送文件，需要等待1-2分钟 \e[0m"
	 sshpass -p $SLAVE_PASSWD ssh -o StrictHostKeyChecking=no -p 22  root@$SLAVE_IP "mkdir -p /root/mysql_install/chrony-pkg"
	 sshpass -p $SLAVE_PASSWD scp  -P 22 chrony-pkg/*   root@$SLAVE_IP:/root/mysql_install/chrony-pkg
         sshpass -p $SLAVE_PASSWD scp  -P 22 mysql-8.0.20-linux-glibc2.12-x86_64.tar.xz   root@$SLAVE_IP:/root/mysql_install
	 sshpass -p $SLAVE_PASSWD scp  -P 22 mysql_install.sh  root@$SLAVE_IP:/root/mysql_install
	 echo -e "\e[32m 双机热备开始安装mysql的master \e[0m"
         sh mysql_install.sh master $MASTER_DATA_PATH
         echo -e "\e[32m 双机热备安装mysql的master完成 \e[0m"

	 echo -e "\e[32m 双机热备开始安装mysql的slave \e[0m"
	 sshpass -p $SLAVE_PASSWD ssh -o StrictHostKeyChecking=no -p 22  root@$SLAVE_IP "cd /root/mysql_install && sh /root/mysql_install/mysql_install.sh slave $SLAVE_DATA_PATH"
         echo -e "\e[32m 双机热备安装mysql的slave完成 \e[0m"
	 sshpass -p $SLAVE_PASSWD ssh -o StrictHostKeyChecking=no -p 22 root@$SLAVE_IP "mysql -u root -psupconit <<EOF
use mysql;
change master to master_host='$MASTER_IP',master_port=3306,master_user='slave',master_password='supconit',master_log_file='mysql-bin.000002',master_log_pos=156;
start slave;
show slave status;
EOF"
         else
         #单机安装mysql
	 echo -e "\e[32m 单机安装mysql开始 \e[0m"
 	 sh mysql_install.sh master $MASTER_DATA_PATH
         echo -e "\e[32m 单机安装mysql完成 \e[0m"
        fi
        ;;

    [nN][oO]|[nN])
        echo -e "\e[33m 退出安装 \e[0m"
        ;;

    *)
        echo -e "\e[31m 无效选项 \e[0m"
        exit 1
        ;;
esac
