---
layout: post
title: "muduo源码阅读"
description: ""
categories: [c/c++, network]
tags: [muduo, c/c++]
keywords: c/c++, muduo, reactor
comments: true
---

最近简单读了下[muduo](http://blog.csdn.net/solstice/article/details/5848547)的源码，本文对其主要实现/结构简单总结下。

muduo的主要源码位于net文件夹下，base文件夹是一些基础代码，不影响理解网络部分的实现。muduo主要类包括：

* EventLoop
* Channel
* Poller
* TcpConnection
* TcpClient
* TcpServer
* Connector
* Acceptor
* EventLoopThread
* EventLoopThreadPool

其中，Poller（及其实现类）包装了Poll/EPoll，封装了OS针对设备(fd)的操作；Channel是设备fd的包装，在muduo中主要包装socket；TcpConnection抽象一个TCP连接，无论是客户端还是服务器只要建立了网络连接就会使用TcpConnection；TcpClient/TcpServer分别抽象TCP客户端和服务器；Connector/Acceptor分别包装TCP客户端和服务器的建立连接/接受连接；EventLoop是一个主控类，是一个事件发生器，它驱动Poller产生/发现事件，然后将事件派发到Channel处理；EventLoopThread是一个带有EventLoop的线程；EventLoopThreadPool自然是一个EventLoopThread的资源池，维护一堆EventLoopThread。

阅读库源码时可以从库的接口层着手，看看关键功能是如何实现的。对于muduo而言，可以从TcpServer/TcpClient/EventLoop/TcpConnection这几个类着手。接下来看看主要功能的实现：
<!-- more -->
## 建立连接

{% highlight c++ %}
    TcpClient::connect 
        -> Connector::start 
            -> EventLoop::runInLoop(Connector::startInLoop...
            -> Connector::connect             
{% endhighlight %}

EventLoop::runInLoop接口用于在this所在的线程运行某个函数，这个后面看下EventLoop的实现就可以了解。 网络连接的最终建立是在Connector::connect中实现，建立连接之后会创建一个Channel来代表这个socket，并且绑定事件监听接口。最后最重要的是，调用`Channel::enableWriting`。`Channel`有一系列的enableXX接口，这些接口用于标识自己关心某IO事件。后面会看到他们的实现。

Connector监听的主要事件无非就是连接已建立，用它监听读数据/写数据事件也不符合设计。TcpConnection才是做这种事的。

## 客户端收发数据

当Connector发现连接真正建立好后，会回调到`TcpClient::newConnection`，在TcpClient构造函数中：

{% highlight c++ %}
    connector_->setNewConnectionCallback(
      boost::bind(&TcpClient::newConnection, this, _1));
{% endhighlight %}
   
`TcpClient::newConnection`中创建一个TcpConnection来代表这个连接：

{% highlight c++ %}
    TcpConnectionPtr conn(new TcpConnection(loop_,
                                            connName,
                                            sockfd,
                                            localAddr,
                                            peerAddr));

    conn->setConnectionCallback(connectionCallback_);
    conn->setMessageCallback(messageCallback_);
    conn->setWriteCompleteCallback(writeCompleteCallback_);
    ...
    conn->connectEstablished();
{% endhighlight %}

并同时设置事件回调，以上设置的回调都是应用层（即库的使用者）的接口。每一个TcpConnection都有一个Channel，毕竟每一个网络连接都对应了一个socket fd。在TcpConnection构造函数中创建了一个Channel，并设置事件回调函数。

`TcpConnection::connectEstablished`函数最主要的是通知Channel自己开始关心IO读取事件：

{% highlight c++ %}
    void TcpConnection::connectEstablished()
    {
        ...
        channel_->enableReading();
{% endhighlight %}
   
这是自此我们看到的第二个`Channel::enableXXX`接口，这些接口是如何实现关心IO事件的呢？这个后面讲到。

muduo的数据发送都是通过`TcpConnection::send`完成，这个就是一般网络库中在不使用OS的异步IO情况下的实现：缓存应用层传递过来的数据，在IO设备可写的情况下尽量写入数据。这个主要实现在`TcpConnection::sendInLoop`中。

{% highlight c++ %}
    TcpConnection::sendInLoop(....) {
        ...
        // if no thing in output queue, try writing directly
        if (!channel_->isWriting() && outputBuffer_.readableBytes() == 0)  // 设备可写且没有缓存时立即写入
        { 
            nwrote = sockets::write(channel_->fd(), data, len);
        }
        ...
        // 否则加入数据到缓存，等待IO可写时再写
        outputBuffer_.append(static_cast<const char*>(data)+nwrote, remaining);
        if (!channel_->isWriting())
        {
            // 注册关心IO写事件，Poller就会对写做检测
            channel_->enableWriting();
        }
        ...     
    }
{% endhighlight %}

当IO可写时，Channel就会回调`TcpConnection::handleWrite`（构造函数中注册）

{% highlight c++ %}
    void TcpConnection::handleWrite()
    {
        ...
        if (channel_->isWriting())
        {
            ssize_t n = sockets::write(channel_->fd(),
                               outputBuffer_.peek(),
                               outputBuffer_.readableBytes());
{% endhighlight %}
       
服务器端的数据收发同客户端机制一致，不同的是连接(TcpConnection)的建立方式不同。

## 服务器接收连接

服务器接收连接的实现在一个网络库中比较重要。muduo中通过Acceptor类来接收连接。在TcpClient中，其Connector通过一个关心Channel可写的事件来通过连接已建立；在Acceptor中则是通过一个Channel可读的事件来表示有新的连接到来：

{% highlight c++ %}
    Acceptor::Acceptor(....) {
        ...
        acceptChannel_.setReadCallback(
            boost::bind(&Acceptor::handleRead, this));
        ... 
    }

    void Acceptor::handleRead()
    {
        ...
        int connfd = acceptSocket_.accept(&peerAddr); // 接收连接获得一个新的socket
        if (connfd >= 0)
        {
            ...
            newConnectionCallback_(connfd, peerAddr); // 回调到TcpServer::newConnection
{% endhighlight %}

`TcpServer::newConnection`中建立一个TcpConnection，并将其附加到一个EventLoopThread中，简单来说就是给其配置一个线程：

{% highlight c++ %}
    void TcpServer::newConnection(int sockfd, const InetAddress& peerAddr)
    {
        ...
        EventLoop* ioLoop = threadPool_->getNextLoop();
        TcpConnectionPtr conn(new TcpConnection(ioLoop,
                                                connName,
                                                sockfd,
                                                localAddr,
                                                peerAddr));
        connections_[connName] = conn;
        ...
        ioLoop->runInLoop(boost::bind(&TcpConnection::connectEstablished, conn));
{% endhighlight %}
   
## IO的驱动

之前提到，一旦要关心某IO事件了，就调用`Channel::enableXXX`，这个如何实现的呢？

{% highlight c++ %}
    class Channel {
        ...
        void enableReading() { events_ |= kReadEvent; update(); }
        void enableWriting() { events_ |= kWriteEvent; update(); }
       
    void Channel::update()
    {
        loop_->updateChannel(this);
    }

    void EventLoop::updateChannel(Channel* channel)
    {
        ...
        poller_->updateChannel(channel);
    }
{% endhighlight %}

最终调用到`Poller::upateChannel`。muduo中有两个Poller的实现，分别是Poll和EPoll，可以选择简单的Poll来看：

{% highlight c++ %}
    void PollPoller::updateChannel(Channel* channel)
    {
      ...
      if (channel->index() < 0)
      {
        // a new one, add to pollfds_
        assert(channels_.find(channel->fd()) == channels_.end());
        struct pollfd pfd;
        pfd.fd = channel->fd();
        pfd.events = static_cast<short>(channel->events()); // 也就是Channel::enableXXX操作的那个events_
        pfd.revents = 0;
        pollfds_.push_back(pfd); // 加入一个新的pollfd
        int idx = static_cast<int>(pollfds_.size())-1;
        channel->set_index(idx);
        channels_[pfd.fd] = channel;
{% endhighlight %}

可见Poller就是把Channel关心的IO事件转换为OS提供的IO模型数据结构上。通过查看关键的`pollfds_`的使用，可以发现其主要是在Poller::poll接口里。这个接口会在EventLoop的主循环中不断调用：

{% highlight c++ %}
    void EventLoop::loop()
    {
      ...
      while (!quit_)
      {
        activeChannels_.clear();
        pollReturnTime_ = poller_->poll(kPollTimeMs, &activeChannels_);
        ...
        for (ChannelList::iterator it = activeChannels_.begin();
            it != activeChannels_.end(); ++it)
        {
          currentActiveChannel_ = *it;
          currentActiveChannel_->handleEvent(pollReturnTime_); // 获得IO事件，通知各注册回调
        }
{% endhighlight %}
            
整个流程可总结为：各Channel内部会把自己关心的事件告诉给Poller，Poller由EventLoop驱动检测IO，然后返回哪些Channel发生了事件，EventLoop再驱动这些Channel调用各注册回调。

从这个过程中可以看出，EventLoop就是一个事件产生器。

## 线程模型

在muduo的服务器中，muduo的线程模型是怎样的呢？它如何通过线程来支撑高并发呢？其实很简单，它为每一个线程配置了一个EventLoop，这个线程同时被附加了若干个网络连接，这个EventLoop服务于这些网络连接，为这些连接收集并派发IO事件。

回到`TcpServer::newConnection`中：

{% highlight c++ %}
    void TcpServer::newConnection(int sockfd, const InetAddress& peerAddr)
    {
      ...
      EventLoop* ioLoop = threadPool_->getNextLoop();
      ...
      TcpConnectionPtr conn(new TcpConnection(ioLoop, // 使用这个选择到的线程中的EventLoop
                                              connName,
                                              sockfd,
                                              localAddr,
                                              peerAddr));
      ...
      ioLoop->runInLoop(boost::bind(&TcpConnection::connectEstablished, conn));
{% endhighlight %}
          
注意`TcpConnection::connectEstablished`是如何通过Channel注册关心的IO事件到`ioLoop`的。

极端来说，muduo的每一个连接线程可以只为一个网络连接服务，这就有点类似于thread per connection模型了。

## 网络模型

传说中的Reactor模式，以及one loop per thread，基于EventLoop的作用，以及线程池与TcpConnection的关系，可以醍醐灌顶般理解以下这张muduo的网络模型图了：

![muduo-model](/assets/res/muduo-model.png)

## 总结

本文主要对muduo的主要结构及主要机制的实现做了描述，其他如Buffer的实现、定时器的实现大家都可以自行研究。muduo的源码很清晰，通过源码及配合[陈硕博客](http://blog.csdn.net/solstice)上的内容可以学到一些网络编程方面的经验。

