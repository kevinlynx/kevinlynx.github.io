---
layout: post
title: "XNIO源码阅读"
category: [java,network]
tags: xnio
comments: true
---


[XNIO](http://xnio.jboss.org/)是JBoss的一个IO框架。最开始我想找个lightweight servlet container库，于是看到了[undertow](http://undertow.io/)，发现其网络部分使用的就是XNIO。所以干脆就先把XNIO的源码读下。

XNIO文档非常匮乏，能找到都是[3.0的版本](https://docs.jboss.org/author/display/XNIO/About+XNIO)，而且描述也不完全。Git上已经出到3.5.0。我读的是3.3.6.Final。

## 使用方式

可以参考[SimpleEchoServer.java](https://github.com/ecki/xnio-samples/blob/master/src/main/java/org/xnio/samples/SimpleEchoServer.java)，不过这个例子使用的API已经被deprecated，仅供参考。使用方式大致为：

* 创建服务，提供acceptListener
* 在acceptListener中accept新的连接，并注册连接listener
* 在连接listener回调中完成IO读写
<!-- more -->
## 主要概念

* Channel，基本上同Java NIO中的Channel一致，一个server socket是一个channel，accept出来的连接也是channel
* ChannelListener，监听Channel上的IO事件，应用代码与XNIO交互的地方
* XnioWorker，维护IO线程池及应用任务线程池

## 项目结构

源码分为两个项目: xnio-api及nio-impl。xnio-api属于API层；nio-impl是基于NIO的实现。通过Java service provider动态地找到nio-impl这个实现。可见XNIO还可以用其他方式来实现。

`org.xnio.channels`这个包里包含了大量的Channel接口定义，这个是非常恶心的一个地方，读代码的时候很容易被绕进去。这个包主要的实现后面提。`org.xnio.conduits`，我理解为比Channel更底层的传输通道，channel依赖于conduit实现，总之也是个恶心的概念。

## 线程模型

可以通过连接如何建立以及建立连接后如何管理连接来了解XNIO的线程模型。通过这个过程我简单画了下主要类关系以及连接建立过程：

![](http://i.imgur.com/HoL99Wz.png)

*用的Dia绘图，UML图支持得不够好*

XNIO的线程模型是一个典型的one loop per thread的Reactor模型。`WorkerThread`类就是这个线程，其有一个主循环，不断地检测其关心的IO设备是否有IO事件发生。当有事件发生时，就将事件通知给关心的listener。站在上层模块的角度，这个线程就是一个Reactor，事件产生器。整个系统有固定数量的`WorkerThread`，也就是IO线程数。这个模型基本上凡是基于epoll/select模型实现的网络库都会用，例如[muduo](http://codemacro.com/2014/05/04/muduo-source/)。可以回看下这个模型：

![](http://codemacro.com/assets/res/muduo-model.png)

XNIO中接收到一个新连接时，会根据这个连接的地址(remote&local address)算出一个哈希值，然后根据哈希值分配到某一个IO线程，然后该连接以后的IO事件都由该线程处理。`WorkerThread`会始终回调`NioHandle`。`QueuedNioTcpServerHandle`是一个accept socket，监听accept事件。而`NioSocketStreamConnection`则是一个建立好的连接，每次新连接进来就会创建，被哈希到某个`WorkerThread`处理。`NioSocketConduit`是一个连接具体关心IO事件的类，正是前面提到的，是一个Channel的底层实现。

`NioXnioWorker`继承于`XnioWorker`，`XnioWorker`内部包含了一个应用任务的线程池。应用代码通过channel listener获取到IO事件通知，channel listener是在IO线程中回调的，所以不适合做耗时操作，否则会导致IO线程中其他IO设备饿死。所以对于这类任务就可以放到这个线程池中做。


## Channel架构

前面提到的XNIO例子使用了一个deprecated的接口，那如何不使用这个接口呢？这就需要更具体地了解channel。XNIO中抽象的channel有很多类型，有些是只读的，有些是只写的，有些则是全双工的。channel还能被组合 (`AssembledChannel`)。可以看下3.1里channel包的大图：[channel package summary](http://docs.jboss.org/xnio/3.1/api/org/xnio/channels/package-summary.png)

这里我只关注基于TCP服务中的channel。如图：


![](http://i.imgur.com/BjmU3BJ.png)

重点关注 `QueuedNioTcpServer` 及 `NioSocketStreamConnection`。`QueuedNioTcpServer`实现`AcceptingChannel` 没什么好说的，就是表示一个可以接收连接的channel。`NioSocketStreamConnection`表示一个网络连接。`StreamConnection`是一个可读可写的channel，但是其内部是通过另外两个channel来实现的，分别是`ConduitStreamSourceChannel`及`ConduitStreamSinkChannel`，分别用读和写。这两个channel内部其实是分别通过两个conduit 来实现，分别为`ConduitStreamSourceChannel` 及 `ConduitStreamSinkChannel` 。

`NioSocketStreamConnection` 内部包含`NioSocketConduit`，这个类实现了 `ConduitStreamSourceChannel` 及 `ConduitStreamSinkChannel` 。在TCP场景下，`StreamConnection`中的读写channel正是指向了`NioSocketConduit`。这个层次包装得有点绕，需要慢慢梳理。

在accept的时候，得到的可以是`StreamConnection`，其实也就是得到了一个可读可写的channel，设计得也没问题。可以基于这个channel设置读写listener。但是如果想在读listener里发起写操作，由于在读listener里看到的是一个只读的channel，所以就没办法写。所以才会有其他包装的channel。

理清了以上关系，就可以不用那个deprecated的API来实现一个echo server：

{% highlight java %}
class ReadListener implements ChannelListener<StreamSourceChannel> {
  // 保存一个可写的channel，才能在读listener里做写操作
  private StreamSinkChannel sinkChannel;

  public ReadListener(StreamSinkChannel sinkChannel) {
    this.sinkChannel = sinkChannel;
  }

  public void handleEvent(StreamSourceChannel channel) {
    final ByteBuffer buffer = ByteBuffer.allocate(512);
    int res;
    try {
      while ((res = channel.read(buffer)) > 0) {
        buffer.flip();
        Channels.writeBlocking(sinkChannel, buffer);
      }
      Channels.flushBlocking(sinkChannel);
      if (res == -1) {
        channel.close();
      } else {
        channel.resumeReads();
      }
    } catch (IOException e) {
      e.printStackTrace();
      IoUtils.safeClose(channel);
    }
  }
}
final ChannelListener<AcceptingChannel<StreamConnection>> acceptListener = new ChannelListener<AcceptingChannel<StreamConnection>>() {
  public void handleEvent(AcceptingChannel<StreamConnection> channel) {
    try {
      StreamConnection accepted;
      // channel is ready to accept zero or more connections
      while ((accepted = channel.accept()) != null) {
        System.out.println("accepted "
            + accepted.getPeerAddress());
        // stream channel has been accepted at this stage.
        // read listener is set; start it up
        accepted.getSourceChannel().setReadListener(new ReadListener(accepted.getSinkChannel()));
        accepted.getSourceChannel().resumeReads();
      }
    } catch (IOException ignored) {
    }
  }
};
final XnioWorker worker = Xnio.getInstance().createWorker(
    OptionMap.EMPTY);
// Create the server.
AcceptingChannel<? extends StreamConnection> server = worker
    .createStreamConnectionServer(new InetSocketAddress(12345),
        acceptListener, OptionMap.EMPTY);
// lets start accepting connections
server.resumeAccepts();
{% endhighlight %}

完。

