# ansible_redis_sentinel
This document explains how to quickly set up a one-master, two-slave redis, three-Sentinel cluster using ansible+docker-compose for three machines.
# 1.Example server list

![img](https://i-blog.csdnimg.cn/direct/7d22a7a3ef7d4e4a9ed3bc100541db73.png)

# 2.General architecture logic

![img](https://i-blog.csdnimg.cn/direct/5046d57775684d5d8a9b6e92e3e6afa6.png)

# 3.Before installation

## Modify the variable file group_vars/all.yml

```yaml
vim group_vars/all.yml
 
docker_data_dir: /app/docker_data   #Installed docker data directory
data_dir: /app     #Data directory to store redis files
redis_sentinel_port: 26379    #sentinel port
redis_pass: "sulibao"     #redis authenticates passwords
image_redis: "registry.cn-chengdu.aliyuncs.com/su03/redis:7.2.7"   #Image used by redis and sentinel
```

## Modify the host manifest file

```yaml
[root@test1 redis_data]# cat hosts 
[redis_master]    #Address of the initial master
192.168.2.190
[redis_slave1]    #The address of the initial slave1
192.168.2.191 
[redis_slave2]    #The address of the initial slave2
192.168.2.192
 
[redis_slave:children]
redis_slave1
redis_slave2
 
[redis:children]
redis_master
redis_slave1
redis_slave2
```

# 4.Installation

```sh
bash setup.sh
```

# 5.Verify the redis-master failover

```sh
#Initial cluster information, test1 is the master, test2 and test3 are the slaves
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
 
 
#Simulate master (test1) hanging up, a new master (test2) appears, test3 is still a slave
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
 
#The old master (test1) is restored to the slave role. In this case, the master is test2, and test1 and test3 are slaves
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