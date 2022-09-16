---
layout: post
title: "写了一个棋牌游戏服务器框架"
category: game develop
tags: [skynet, pigy]
comments: true
---

最近业余时间写了一个棋牌游戏服务端框架：[pigy](https://github.com/kevinlynx/pigy)。对于棋牌游戏服务端框架，我的定义是：

* 分布式的
* 包含网络棋牌游戏中包括登陆、大厅、游戏框架、数据持久化等基础组件
* 提供具体游戏框架，游戏逻辑程序员可以基于这个框架focus在游戏的开发上

写得差不多的时候，我在网上搜索了下，发现棋牌游戏源码已经烂大街，自己精力有限，也没有心思和动力去研究现有实现的优缺点而做出一个更好的替代。所以我这份实现仅作为一个demo放出来让大家开心下好了。

[pigy](https://github.com/kevinlynx/pigy)基于[skynet](https://github.com/cloudwu/skynet)实现。之所以选择skynet是看中其中已经有不少网络游戏基础组件可以使用，结合开发下来稍微花点业余时间就可以完成雏形。除此之外，部分源码也参考/复制了[metoo](https://github.com/fztcjjl/metoo)项目。
<!-- more -->
## 架构

![](https://i.imgur.com/7RLkaWm.png)

服务器主要有3类角色：

* Login，登陆/账号服务器，负责玩家账号相关
* Hall，大厅服务器，职责包括：
    * 获取玩家信息及公告推送等独立于具体游戏的逻辑
    * 房间相关管理，分配玩家到游戏服务器
* Game，游戏服务器，包装具体的游戏，提供游戏运行框架

我希望除了Game之外，Login和Hall都具备高可用性，例如可水平扩展，在挂掉后对玩家无影响。要做到这一点就要对服务器的状态数据做较好的管理，以实现挂掉后要么玩家被自动迁移到其他服务，要么挂掉的服务重启后可以快速恢复之前的数据。对于Login/Hall而言最主要的状态数据就是玩家的登陆数据，由于数据简单，可以选择直接持久化到redis并且不需要落盘。redis就可以作为单点，保存全服的数据。这样，Login/Hall还可以水平扩展，动态根据实例数分摊全服玩家数据。

但是我只是实现了一个阉割版。我暂时不希望太过依赖redis，所以我让Login/Hall互相作为数据备份。Login和Hall本身就持有玩家的登陆数据，可以在对方挂掉重启后，自动恢复数据。为了恢复数据时简单可靠，我让Login作为单点存在。毕竟，Login并不与Client保持长连接，也没有除了登陆外其他更复杂的逻辑，加上skynet多线程的特性，性能上单点就足够支撑。

Hall是支持水平扩展的。Login可以按玩家uid一致性哈希地选择一个Hall，其实按普通取模哈希也没有什么问题。1个Hall实例挂掉后，Client启动重连定时器，预期能在短时间内重新启动完成这个挂掉的Hall。

Game (server)肯定是支持水平扩展的。我在Game中抽象了Gamelet概念，本质上就是一个具体的游戏。Gamelet可以部署到任意一个Game内，Game单实例可以跑多个Gamelet。Hall会定期查询所有Game的Gamelet实时情况。Gamelet的实时情况主要包括某具体游戏关联的所有房间信息。Hall聚合这些信息，主要确定两方面信息：

* 哪些Game加载了哪些Gamelet，主要用于在Hall上创建房间
* 某具体的Game有哪些房间，一般用于Client展示游戏房间信息

各个Server角色之间通信全部依靠skynet Cluster机制，节省了不少工作。

## 账号处理

Login最开始是完全基于skynet [Login Server](https://github.com/cloudwu/skynet/wiki/loginServer)实现。但是涉及到账号相关的功能还包括：

* 游客账号及自有注册账号
* 账号绑定

所以扩展了LoginServer，在原有协议上增加了扩展命令，搞得类似HTTP协议的URI。

## 消息及RPC

除了Login使用文本协议外，Hall/Game都使用基于skynet [Gate Server](https://github.com/cloudwu/skynet/wiki/GateServer)的长度+消息体的格式，而消息体又使用protobuf格式。为了支持消息的派发，将消息值映射到skynet service method上，类似于简单的RPC：

```
消息code值 -> 消息code到service.method字符串映射 -> 找到对应的service，调用其method
```

这里也可以使用云风提供的[sproto](https://github.com/cloudwu/skynet/wiki/Sproto)。本质上都是解决消息格式编码及消息dispatch问题。

## 断线重连

断线重连主要牵涉到几个问题：

* 玩家的状态数据不能依赖socket的状态
* server间对于玩家数据一般有鉴权处理，Client断线重连时可以直接携带token直连某个server，而不用走重新登陆逻辑
* server对client数据做重连补发

其中，重连补发根据实现又分为两种情况：

* 基于断线协议，在server框架层，或者整个游戏服务器组的统一接入层自动解决。例如[goscon](https://github.com/ejoy/goscon)
* 在应用层解决，一般就是游戏内根据具体游戏重发全量游戏数据到Client

在pigy中，我认为更简单可靠的做法是在应用层解决。当然，一些前提还是得实现的。例如玩家在线状态不基于socket、server间传递token以支持Client直连server。

## 数据持久化及缓存

持久化及缓存是基于三层结构：本地内存、redis缓存、mysql。mysql作为关系型数据库，其表里的每一行记录，都会映射为redis中的一个哈希表。哈希表自身由db table name 及该行关键值确定，id可以作为关键值。而为了获取该数据库表里所有行，又将所有行的index字段(配置)作为redis一个有序集合关联起来。这样，通过获取redis有序集合所有元素，就可以获取该数据库表所有行记录。

例如，有玩家表：

```
id | name | age |
---|------|-----|
1  | kev  | 18  |
---|------|-----|
2  | john | 20  |

```

映射到redis中，就会得到2个哈希表，对应2行；另外得到一个有序集合，根据配置，集合中存储了所有`id`字段值。

然后，基于以上结构，可以配置有些数据库表，是需要在启动时全部载入内存，而有些数据，例如玩家数据，由于数据会很多，并且很多数据并不需要，所以就只载入一部分。整个游戏的数据会根据玩家uid进行分区(partition)，redis可以以独立集群的模式启动多个集群，然后玩家数据根据uid分区存储到这些redis中。

## 游戏框架

网络棋牌游戏中有很多子游戏，所以游戏框架是肯定需要的。游戏框架主要用来抽象/隔离各种底层细节，包括网络数据发送、同房间玩家数据获取、数据持久化等等。设计上主要就是包装，但是目前的实现还不完整。pigy将子游戏抽象为gamelet，类似于servlet。这个抽象本质上就是与框架交互协议的包装，以及框架对一些数据的接口化透出。

例如：

```
function init(source) -- 将房间service传入
    room = source
end

function accept.enter(user) -- 某个玩家进入该房间
end
```

pigy中某个Game (server)是可以载入多个gamelet的。所以在Hall端会聚合出来某个游戏(gamelet)在哪些Game上部署，以在其上创建房间。

## 网关

网关服务器主要用于隔离内部服务器与外网，避免受到恶意攻击。在早期我并不想花精力去重写一个Gate (server)，同时我希望Gate的加入应该尽可能少地对其他服务造成侵入。所以这造成了一种困境，因为在Game上的通信不太方便实现为Req/Resp的模式，所以现成的类似nginx TCP的网关也用不上，自己写优先级也不高，所以直到目前我也没有花时间去实现一个出来。

## 如何运行

准备好skynet，然后参考doc/guide.md。

## 总结

网络游戏服务器毕竟是分布式系统，在框架层面，稳定性及可扩展性是比较有趣的问题。在移动网络游戏方面，断线重连又是无法逃避的问题。这些问题要做得完美还是很不容易。


