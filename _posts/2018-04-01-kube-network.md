---
layout: post
title: "kubernetes网络相关总结"
category: 弹性调度
tags: [kubernetes]
comments: true
---

要理解kubernetes的网络模型涉及到的技术点比较多，网络上各个知识点讲得细的有很多，这里我就大概梳理下整个架构，方便顺着这个脉络深入。本文主要假设kubernetes使用docker+flannel实现。

整体上，了解kubernetes的网络模型，涉及到以下知识：

* linux网络及网络基础
* docker网络模型
* kubernetes网络需求，及flannel网络实现

最后大家就可以结合实例对照着学习。

## Linux网络

先看几个概念，引用自[Kubernetes网络原理及方案](https://www.kubernetes.org.cn/2059.html):

* 网络命名空间

> Linux在网络栈中引入网络命名空间，将独立的网络协议栈隔离到不同的命令空间中，彼此间无法通信；docker利用这一特性，实现不同容器间的网络隔离

* 网桥

> 网桥是一个二层网络设备,通过网桥可以将linux支持的不同的端口连接起来,并实现类似交换机那样的多对多的通信

* Veth设备对

> Veth设备对的引入是为了实现在不同网络命名空间的通信

* 路由

> Linux系统包含一个完整的路由功能，当IP层在处理数据发送或转发的时候，会使用路由表来决定发往哪里

借图以关联上面的概念：

![dnet.png](/assets/res/kubenet/dnet.png)
<!-- more -->
安装docker后，系统中就会有一个docker0网桥。通过`ifconfig` 或`ip link`可以查看(准确的说是查看网络设备？)：

```
$ip link
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP mode DEFAULT qlen 1000
    link/ether 00:16:3e:00:03:9a brd ff:ff:ff:ff:ff:ff
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN mode DEFAULT
    link/ether 02:42:c0:a8:05:01 brd ff:ff:ff:ff:ff:ff
```

一个docker POD中，多个容器间是共享网络的。在POD中，有一个默认的网络设备，就像物理机上一样，名为`eth0`。POD中的`eth0`通过`Veth设备对`，借由docker0网桥与外部网络通信。veth设备对同样可以用`ip link`查看，系统中有多少POD就会有多少veth对：

```
$ip link
...
219: veth367a306c@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master cni0 state UP mode DEFAULT 
    link/ether 62:de:88:30:86:fa brd ff:ff:ff:ff:ff:ff link-netnsid 19
220: veth684956fd@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master cni0 state UP mode DEFAULT 
    link/ether fe:b8:33:8c:25:b0 brd ff:ff:ff:ff:ff:ff link-netnsid 20
222: veth9e23eff7@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master cni0 state UP mode DEFAULT 
    link/ether 7e:e9:2d:f2:28:e5 brd ff:ff:ff:ff:ff:ff link-netnsid 22
```

veth对只是不同网络命名空间通信的一种解决方案，还有其他方案，借图：

![veth.png](/assets/res/kubenet/veth.png)

最后，“路由”表可以通过`ip route`查看，这块内容我理解就是根据网络地址交给不同的设备做处理：

```
$ip route
default via 10.101.95.247 dev eth0 
...
# 匹配前24bits的地址交由flannel.1设备处理
10.244.0.0/24 via 10.244.0.0 dev flannel.1 onlink 
```

## docker网络模型

docker网络模型用于解决容器间及容器与宿主机间的网络通信，主要分为以下模型：

* Bridge，默认模式，也就是上面通过`docker0`做通信的模式
* Host，容器内的网络配置同宿主机，没有网络隔离
* None，容器内仅有loopback

不同的模式通常在启动容器时，可以通过`--net=xx`参数指定。可以通过`docker network inspect [host|bridge]`查看本机某种网络模型下启动的容器列表，例如：

```
$sudo docker network inspect host
[
    {
        "Name": "host",
        "Id": "19958f2d93e0bf428c685c12b084fc5e6a7bd499627d90ae9ae1ca4b11a8f437",
        "Scope": "local",
        "Driver": "host",
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": null,
            "Config": []
        },
        "Internal": false,
        "Containers": {
            "03d2b6e1faa3763fefd5528cce29ca454a13220dab693f242ff808051d7fd34b": {
                "Name": "k8s_POD_kube-proxy-69rl4_kube-system_b793f549-22a0-11e8-9ce1-00163e00039a_0",
                "EndpointID": "4380fab27d237e21f7fa6f84cf23b8a6d605f4e612968a3377f853abf987f6a4",
                "MacAddress": "",
                "IPv4Address": "",
                "IPv6Address": ""
            },
            "9140fdf7a3ea0b19fec3a922e998ba3c544d328c1bd372525dfef816c620a431": {
                "Name": "k8s_POD_kube-flannel-ds-m88p6_kube-system_b793f466-22a0-11e8-9ce1-00163e00039a_0",
                "EndpointID": "01024d8050167cd88c11220375f89217116b5c929575a45695fe5d759038f320",
                "MacAddress": "",
                "IPv4Address": "",
                "IPv6Address": ""
            }
        },
        "Options": {},
        "Labels": {}
    }
]

```

docker解决了单机容器网络隔离与网络通信，但没有解决多机间的通信。


## Kubernetes网络模型及Flannel实现

kubernetes为了简单，它要求的网络模型里，整个集群中所有的POD都有独立唯一的IP。POD间互相看到的IP是稳定的，是直接可达的，是一个平铺网络。如何实现kubernetes的这个网络需求，CNI插件是一种解决方案，而Flannel项目则是CNI插件的一种实现。

Flannel的实现，本质上主要是两方面内容：

* 一个proxy做流量转发，也就是flanneld进程，可以自行ps查看
* 通过中心化存储etcd来对整个集群做POD的IP分配

借图，了解flannel网络原理：

![service.png](/assets/res/kubenet/flannel.png)

flannel网络上已经有很多资料，例如[一篇文章带你了解Flannel](http://dockone.io/article/618)。flannel的网络通信可以配置不同的backend，例如，配置UDP为backend时，那么交由flanneld进程转发网络包时，就会以UDP包的形式包装起来做转发，到达对端的flanneld进程时再解包。当然，实际使用时是不会使用这种方式的，通常会使用由内核支持的vxLan。参考[flannel backend配置](https://github.com/coreos/flannel/blob/master/Documentation/backends.md)。

在安装kubernetes时，基于kube-flannel.yml文件配置flannel就使用的vxLan：

```
net-conf.json: |
{
  "Network": "10.244.0.0/16",
  "Backend": {
	"Type": "vxlan"
  }
}
```

docker在创建容器时，会给容器分配IP，flannel的安装里会hack docker daemon的启动方式，增加`--bip`参数，用于限定docker分配的IP范围，这也是网络上很多文章提到的。在我的环境里，docker容器全部以host方式设置网络，所以有没有设置bip也无所谓。

安装了flannel后，在kubernetes网络中就可以直接ping一个POD容器。到这里，可以小结一下，基于以上的技术，在一个集群中，每一个POD都可以有一个独立唯一的IP，其他宿主机的POD可以直接访问这个POD。但是，一个分布式服务通常处于性能和稳定性考虑会有多个实例，所以kubernetes还要解决负载均衡问题。

## Kubernetes中的负载均衡

kubernetes中通过service概念来对应用做多POD间的负载均衡。service是一个虚拟概念，service都会被分配一个`clusterIP`，其实就是service对外暴露的地址。你可以为一个redis服务暴露一个service，然后将这个service的clusterIP传给一个PHP应用，以让PHP应用访问redis。那么，这个PHP应用具体是如何通过这个service clusterIP负载均衡到redis的多个容器呢？在kubernetees中，目前主要是通过iptable来实现。借图：

![service.png](/assets/res/kubenet/service.png)

要理解上图，首先大概要有一个iptable的知识，大概就是在整个包收发处理过程中可以配置很多链，当一个链的条件被满足时，就可以执行一个动作。这里，我们主要关注上图中的左边分支部分。本质上，拿到一个service的clusterIP，到发送到目的POD，整个过程主要涉及到内容：

* service clusterIP是虚拟的，是一个iptable规则，这个规则最终会映射到一个POD的IP
* 一个应用有多少POD，那么在集群中的每台机器上，就会有多少iptable链

在kubernetes集群中，可以实际追踪看看。例如上面提到的redis service clusterIP为`10.99.136.250`：

```
$sudo iptables-save | grep 10.99.136.250
# -d 10.99.136.250/32 地址完全匹配，然后执行 -j KUBE-SVC-AGR3D4D4FQNH4O33 规则
-A KUBE-SERVICES -d 10.99.136.250/32 -p tcp -m comment --comment "default/redis-slave: cluster IP" -m tcp --dport 6379 -j KUBE-SVC-AGR3D4D4FQNH4O33
# 这条规则对应到上图中`source!=podIP`，主要用于配合SNAT处理，简单理解为改写封包源IP
-A KUBE-SERVICES ! -s 10.244.0.0/16 -d 10.99.136.250/32 -p tcp -m comment --comment "default/redis-slave: cluster IP" -m tcp --dport 6379 -j KUBE-MARK-MASQ

```

追`KUBE-SVC-AGR3D4D4FQNH4O33`规则：

```
$sudo iptables-save | grep KUBE-SVC-AGR3D4D4FQNH4O33
:KUBE-SVC-AGR3D4D4FQNH4O33 - [0:0]
-A KUBE-SVC-AGR3D4D4FQNH4O33 -m comment --comment "default/redis-slave:" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-GDIX2RIKQIYS7RMI
-A KUBE-SVC-AGR3D4D4FQNH4O33 -m comment --comment "default/redis-slave:" -j KUBE-SEP-J5QZN63T7ON4OKV7
...
```

因为`redis-slave`有2个POD，所以上面通过`--probability 0.50`实现了50%的流量负载均衡。`KUBE-SEP-XX`就是各个POD的地址，可以继续追，例如：

```
$sudo iptables-save | grep KUBE-SEP-GDIX2RIKQIYS7RMI
:KUBE-SEP-GDIX2RIKQIYS7RMI - [0:0]
-A KUBE-SEP-GDIX2RIKQIYS7RMI -s 10.244.1.56/32 -m comment --comment "default/redis-slave:" -j KUBE-MARK-MASQ
-A KUBE-SEP-GDIX2RIKQIYS7RMI -p tcp -m comment --comment "default/redis-slave:" -m tcp -j DNAT --to-destination 10.244.1.56:6379
```

最终，封包发送到POD之一`10.244.1.56`。上面的过程，对着前面图的左半部分很容易理解。

kubernetes中还提供了kube-dns，主要是为service clusterIP提供一个域名。每个service都可以按固定格式拼出一个域名，而kube-dns则负责解析这个域名，解析为service的clusterIP，实际网络数据传输流程还是同上。

## 总结

熟悉kubernetes，几大组件的工作原理其实不难理解。而kubernetes网络模型显得更难，尤其是要结合各种工具、命令去实践时，很容易与理论脱节。一旦梳理通彻整个链路，回头看时就会发现也就那么回事。当然，上面提到的各个技术点，深入下去了解还是有很多内容的。

