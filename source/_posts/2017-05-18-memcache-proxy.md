---
layout: post
title: "实现一个memcache proxy"
category: java
tags: memcache
comments: true
---


通常我们会使用多台memcached构成一个集群，通过客户端库来实现缓存数据的分片(replica)。这会带来2个主要问题：

* memcached机器连接数过多
* 不利于做整体的服务化；缺少可运维性。例如想对接入的客户端做应用级隔离；或者对缓存数据做多区域(机房)的冗余

实现一个memcache proxy，相对于减少连接数来说，主要可以提供更多的扩展性。目前已经存在一些不错的memcache proxy，例如twitter的[twemproxy](https://github.com/twitter/twemproxy)，facebook的[mcrouter](https://github.com/facebook/mcrouter)。稍微调研了下，发现twemproxy虽然轻量，但功能较弱；mcrouter功能齐全，类似多区域多写的需求也满足。处于好玩的目的，之前又读过网络库[xnio](http://codemacro.com/2017/04/09/xnio-source/)源码，我还是决定自己实现一个。
<!-- more -->
这个项目简单取名为[kvproxy](https://github.com/kevinlynx/kvproxy)，通过简单的抽象可以实现为memcache或redis等key-value形式的服务proxy。 这是一些预想中的[feature](https://github.com/kevinlynx/kvproxy/blob/master/design.md)。

在目前的阶段，主要关注于其性能。因为memcached本身的RT非常小，所以这个proxy的性能就要求比较高。这里主要先关注下核心功能的实现。

## 架构

如下图：

![](http://i.imgur.com/VxrSdKT.png)

* `Service`，用于抽象key-value服务，如memcache；`MemcacheService`是其实现之一
* `ServerLocator`，用于定位memcached机器列表，例如`ConstantLocator`则是从配置文件中读取。可以实现一个从名字服务读取列表的locator。
* `Connection`，配合`KVProxy`，基于xnio，表示一个与客户端的连接
* `ConnectionListener`，用于处理网络连接上的请求，例如`RequestHandler`则是`MemcaheService`中的listener，用于处理从客户端发过来的memcache协议请求
* `MemClient`，包装memcache客户端，用于proxy将请求转发到后端的memcache服务
* `GroupClient`，包装`MemClient`，可以用于多区域数据的同时写入，目前实现为单个primary及多个slave。写数据同步写入primary异步写入slave；读取数据则只从primary读。

本身要抽象的东西不复杂，所以结构其实是很简单的，也没有花太多心思。接下来关注下性能方面的问题。

## 异步性

作为一个proxy，异步基本是必然选择的方案，指的是，proxy在收到memcache的请求时，不阻塞当前的IO线程，形成一个请求context，在收到回应时拿到这个context来回应客户端。这样通过增加消耗的内存，来释放CPU资源，可以让IO模块尽可能多地接收从客户端来的请求。当然，如果请求过多，可能就会耗尽内存。

为了简单，我没有自己实现memcache client。网络上有很多开源的memcache client。我试了几个，例如[xmemcached](http://codemacro.com/2017/04/23/xmemcached/)(为此还读过它的源码)，但由于这些客户端都是同步的，虽然可以自己起线程池来把同步包装为异步，但始终不是最优方案。最后无意发现了[folsom](https://github.com/spotify/folsom)，集成到kvproxy后性能表现还不错。当然，真正要做到性能最优，最好还是自己实现memcache client，这样可以使用同一个xnio reactor，不用开那么多IO线程，拿到数据后就可以直接得到ByteBuffer，应该可以减少内存拷贝操作(能提高多少也不确定)。

## 性能测试

我使用了[memtier_benchmark](https://github.com/RedisLabs/memtier_benchmark)来做压力测试。测试环境是16core的虚拟机(宿主机不同)，benchmark工具同目标测试服务部署在不同的机器，proxy同memcache部署在相同机器。目标服务基于OS centos7，测试命令为：

```
./memtier_benchmark -s 127.0.0.1 -p 22122 -P memcache_text --test-time 60 -d 4096 --hide-histogram
```

默认开启4个压测线程，每个线程建立50个连接，测试60秒，默认设置是1:10的set/get。

首先是直接压测memcached：

```
ALL STATS
========================================================================
Type        Ops/sec     Hits/sec   Misses/sec      Latency       KB/sec
------------------------------------------------------------------------
Sets        5729.65          ---          ---      3.27500     23141.85
Gets       57279.42        80.33     57199.09      3.16000      1771.99
Waits          0.00          ---          ---      0.00000          ---
Totals     63009.07        80.33     57199.09      3.17000     24913.84
```

然后我压测了twitter的twemproxy，RT差不多增加70%。

```
ALL STATS
========================================================================
Type        Ops/sec     Hits/sec   Misses/sec      Latency       KB/sec
------------------------------------------------------------------------
Sets        3344.58          ---          ---      5.58400     13508.68
Gets       33430.28        40.00     33390.28      5.41900      1006.32
Waits          0.00          ---          ---      0.00000          ---
Totals     36774.85        40.00     33390.28      5.43400     14515.00

```

最后是压测kvproxy (jdk8)，只与memcache建立一个连接，RT增加95%，基本上翻倍。不过由于是Java实现，相对于twemproxy的C实现感觉也不差。当然，机器资源消耗更大(主要是内存)。

```
ALL STATS
========================================================================
Type        Ops/sec     Hits/sec   Misses/sec      Latency       KB/sec
------------------------------------------------------------------------
Sets        2959.41          ---          ---      6.62400     11953.00
Gets       29578.47        33.90     29544.57      6.20800       884.38
Waits          0.00          ---          ---      0.00000          ---
Totals     32537.88        33.90     29544.57      6.24600     12837.37

```

压测中IO线程CPU并没有跑满，推测是虚拟机之间的网络带宽还是不够。


