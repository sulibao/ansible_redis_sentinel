# ansible_redis_sentinel
本文解释了如何使用ansible+docker-compose为三台机器快速部署一个单主、双从、三哨兵的redis集群。
# 1.示例服务器列表

| IP                     | 用途       |
| ---------------------- | ---------- |
| 192.168.2.190（test1） | 初始master |
| 192.168.2.191（test2） | 初始slave1 |
| 192.168.2.192（test3） | 初始slave2 |

# 2.大致架构逻辑

![](https://i-blog.csdnimg.cn/direct/5046d57775684d5d8a9b6e92e3e6afa6.png)

# 3.安装前

## 修改变量文件group_vars/all.yml

```yaml
vim group_vars/all.yml
 
docker_data_dir: /app/docker_data   #docker数据目录
data_dir: /app     #redis数据目录
redis_sentinel_port: 26379    #sentinel端口
redis_pass: "sulibao"     #redis认证密码
image_redis: "registry.cn-chengdu.aliyuncs.com/su03/redis:7.2.7"   #redis和sentinel的镜像
```

## 修改主机清单

```yaml
[root@test1 redis_data]# cat hosts 
[redis_master]    #初始redis-master的地址
192.168.2.190
[redis_slave1]    #初始redis-slave1的地址
192.168.2.191 
[redis_slave2]    #初始redis-slave2的地址
192.168.2.192
 
[redis_slave:children]
redis_slave1
redis_slave2
 
[redis:children]
redis_master
redis_slave1
redis_slave2
```

## 修改setup.sh安装脚本

```sh

export ssh_pass="sulibao"  #服务器root密码，这里要求三台服务器密码一致

```

# 4.安装

```sh
bash setup.sh
```

# 5.验证redis-master故障转移

```sh
#初始集群信息，test1是主，test2和test3是从
docker exec -it redis-master bash
root@test1:/data# redis-cli -a sulibao role
Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe.
1) "master"
2) (integer) 35726
3) 1) 1) "192.168.2.191"
      2) "6379"
      3) "35726"
   2) 1) "192.168.2.192"
      2) "6379"
      3) "35585"
 
 
#模拟主服务器（test1）挂起，出现一个新的主（test2）， test3仍然是从服务器
[root@test1 redis_data]# docker stop redis-master
redis-master
[root@test2 ~]# docker exec -it redis-slave1 bash
root@test2:/data# redis-cli -a sulibao role
Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe.
1) "master"
2) (integer) 68953
3) 1) 1) "192.168.2.192"
      2) "6379"
      3) "68953"
 
#将原来的master （test1）恢复为slave角色。现在，主是test2，而test1和test3是从
[root@test1 redis_data]# docker start redis-master
redis-master
root@test2:/data# redis-cli -a sulibao role
Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe.
1) "master"
2) (integer) 87291
3) 1) 1) "192.168.2.192"
      2) "6379"
      3) "87291"
   2) 1) "192.168.2.190"
      2) "6379"
      3) "87291"
```