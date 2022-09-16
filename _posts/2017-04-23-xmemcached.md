---
layout: post
title: "Xmemcached源码阅读"
category: java
tags: xmemcached
comments: true
---

[Xmemcached](https://github.com/killme2008/xmemcached) 是一个memcached客户端库。由于它提供的是同步API，而我想看下如何增加异步接口。所以就大致浏览了下它的源码。

## 主要结构

针对memcache客户端的实现，主要结构如下：

![](http://i.imgur.com/7r4Y35O.jpg)

* `XMemcachedClient` 是应用主要使用的类，所有针对memcache的接口都在这里
* `Command` 用于抽象二进制协议或文本协议下各个操作，这里称为Command。`CommandFactory` 用于创建这些command
* `MemcachedSessionLocator` 用于抽象不同的负载均衡策略，或者说数据分布策略。在一个memcached集群中，数据具体存放在哪个replica中，主要就是由这个类的实现具体的，例如`KetamaMemcachedSessionLocator` 实现了一致性哈希策略
* `MemcachedConnector` 包装了网络部分，与每一个memcached建立连接后，就得到一个`Session`。command的发送都在`MemcachedConnector`中实现
* 各个Session类/接口，则涉及到Xmemcached使用的网络库yanf4j。这个库也是Xmemcached作者的。
<!-- more -->
Command 类的实现中有个关键的`CountDownLatch`。在将Command通过session发送出去之后，就利用这个latch同步等待，等到网络模块收到数据后回调。Command会和session绑定，在这个session上收到数据后，就认为是这个command的回应。

由于本身memcached库核心东西比较少，上面的结构也就很好理解。协议的抽象和数据分布策略的抽象是必须的。接下来看看网络实现部分。

## 网络实现

Xmemcached的网络实现主要结构如下：

![](http://i.imgur.com/pwGjcgQ.jpg)

* `SocketChannelController`，主要的类，将IO事件通知转交给session
* `NioController`，主要关注其成员`SelectorManagrer`
* `SelectorManager` 内置若干个`Reactor`，数量由CPU核数决定
* `Reactor`，IO事件的产生器，一个Reactor对应一个线程，线程循环中不断轮询NIO selector是否产生了IO事件
* `CodecFactory`，编解码网络消息接口
* `PoolDispatcher` ，Dispatcher 用于调度一个IO事件的具体处理过程，而`PoolDispatcher`则是放到一个单独的线程池中处理
* `DispatcherFactory` ，用于创建具体的dispatcher

这个网络实现还是比较典型的Reactor模式。其中，产生IO事件后，IO事件的具体处理，默认交给了一个独立的线程池。一般网络库都会提供类似的机制，以使得IO线程不至于被业务逻辑阻塞住，导致IO处理效率下降。

写数据时，数据都会写到一个队列中，在设备可写时才具体写入。看下具体的读数据过程：

![](http://i.imgur.com/N7XqVS7.jpg)

从Reactor中最终调用到Xmemcached的command，用于具体解析回应数据。要调整为异步的话，则可以修改Command的实现，增加异步回调。同时注意控制dispatcher使用的线程池。

完。


