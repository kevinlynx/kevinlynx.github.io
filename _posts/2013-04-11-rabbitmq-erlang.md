---
layout: post
title: "erlang和RabbitMQ学习总结"
categories: [erlang]
tags: [erlang, rabbitmq]
comments: true
keywords: erlang, rabbitmq, AMQP
description: AMQP中有一些概念，用于定义与应用层的交互。这些概念包括：message、queue、exchange、channel, connection, broker、vhost。
---

## AMQP和RabbitMQ概述

[AMQP](http://www.amqp.org/)(Advanced Message Queue Protocol)定义了一种消息系统规范。这个规范描述了在一个分布式的系统中各个子系统如何通过消息交互。而[RabbitMQ](http://www.rabbitmq.com/)则是AMQP的一种基于erlang的实现。

AMQP将分布式系统中各个子系统隔离开来，子系统之间不再有依赖。子系统仅依赖于消息。子系统不关心消息的发送者，也不关心消息的接受者。

AMQP中有一些概念，用于定义与应用层的交互。这些概念包括：message、queue、exchange、channel, connection, broker、vhost。

*注：到目前为止我并没有打算使用AMQP，所以没有做更深入的学习，仅为了找个机会写写erlang代码，以下信息仅供参考。*

* message，即消息，简单来说就是应用层需要发送的数据
* queue，即队列，用于存储消息
* exchange，有翻译为“路由”，它用于投递消息，**应用程序在发送消息时并不是指定消息被发送到哪个队列，而是将消息投递给路由，由路由投递到队列**
* channel，几乎所有操作都在channel中进行，有点类似一个沟通通道
* connection，应用程序与broker的网络连接
* broker，可简单理解为实现AMQP的服务，例如RabbitMQ服务

关于AMQP可以通过一篇很有名的文章了解更多：[RabbitMQ+Python入门经典 兔子和兔子窝](http://blog.ftofficer.com/2010/03/translation-rabbitmq-python-rabbits-and-warrens/)

RabbitMQ的运行需要erlang的支持，erlang和RabbitMQ在windows下都可以直接使用安装程序，非常简单。RabbitMQ还支持网页端的管理，这需要开启一些RabbitMQ的插件，可以参考[官方文档](http://www.rabbitmq.com/management.html)。

RabbitMQ本质上其实是一个服务器，与这个服务器做交互则是通过AMQP定义的协议，应用可以使用一个实现了AMQP协议的库来与服务器交互。这里我使用erlang的一个客户端，对应着RabbitMQ的tutorial，使用erlang实现了一遍。基于这个过程我将一些关键实现罗列出来以供记忆：
<!-- more -->
## 主要功能使用

关于RabbitMQ erlang client的使用说明可以参考[官方文档](http://www.rabbitmq.com/erlang-client-user-guide.html)。这个client library下载下来后是两个ez文件，其实就是zip文件，本身是erlang支持的库打包格式，但据说这个feature还不成熟。总之我是直接解压，然后在环境变量中指定`ERL_LIBS`到解压目录。使用时使用`include_lib`包含库文件（类似C语言里的头文件）：

{% highlight erlang %}
    -include_lib("amqp_client/include/amqp_client.hrl").
{% endhighlight %}

### Connection/Channel

对于连接到本地的RabbitMQ服务：

{% highlight erlang %}
    {ok, Connection} = amqp_connection:start(#amqp_params_network{}),
    {ok, Channel} = amqp_connection:open_channel(Connection),
{% endhighlight %}

### 创建Queue

每个Queue都有名字，这个名字可以人为指定，也可以由系统分配。Queue创建后如果不显示删除，断开网络连接是不会自动删除这个Queue的，这个可以在RabbitMQ的web管理端看到。

{% highlight erlang %}
    #'queue.declare_ok'{queue = Q}
        = amqp_channel:call(Channel, #'queue.declare'{queue = <<"rpc_queue">>}),
{% endhighlight %}

但也可以指定Queue会在程序退出后被自动删除，需要指定`exclusive`参数：

{% highlight erlang %}
    QDecl = #'queue.declare'{queue = <<>>, exclusive = true},
    #'queue.declare_ok'{queue = Q} = amqp_channel:call(Channel, QDecl),
{% endhighlight %}
    
上例中queue的名字未指定，由系统分配。

### 发送消息

一般情况下，消息其实是发送给exchange的：

{% highlight erlang %}
    Payload = <<"hello">>
    Publish = #'basic.publish'{exchange = <<"log_exchange">>},
    amqp_channel:cast(Channel, Publish, #amqp_msg{payload = Payload}),
{% endhighlight %}

exchange有一系列规则，决定某个消息将被投递到哪个队列。

发送消息时也可以不指定exchange，这个时候消息的投递将依赖于`routing_key`，`routing_key`在这种场景下就对应着目标queue的名字：

{% highlight erlang %}
    #'queue.declare_ok'{queue = Q}
        = amqp_channel:call(Channel, #'queue.declare'{queue = <<"rpc_queue">>}),
    Payload = <<"hello">>,
    Publish = #'basic.publish'{exchange = <<>>, routing_key = Q},
    amqp_channel:cast(Channel, Publish, #amqp_msg{payload = Payload}),
{% endhighlight %}

### 接收消息

可以通过注册一个消息consumer来完成消息的异步接收：

{% highlight erlang %}
    Sub = #'basic.consume' {queue = Q},
    #'basic.consume_ok'{consumer_tag = Tag} = amqp_channel:subscribe(Channel, Sub, self()),
{% endhighlight %}

以上注册了了一个consumer，监听变量`Q`指定的队列。当有消息到达该队列时，系统就会向consumer进程对应的mailbox投递一个通知，我们可以使用`receive`来接收该通知：

{% highlight erlang %}
    loop(Channel) ->
        receive 
            % This is the first message received (from RabbitMQ)
            #'basic.consume_ok'{} -> 
                loop(Channel);
            % a delivery
            {#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}} ->
                echo(Payload),
                % ack the message
                amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag}),
                loop(Channel);
        ...
{% endhighlight %}

### 绑定exchange和queue

绑定(binding)其实也算AMQP里的一个关键概念，它用于建立exchange和queue之间的联系，以方便exchange在收到消息后将消息投递到队列。我们不一定需要将队列和exchange绑定起来。

{% highlight erlang %}
    Binding = #'queue.bind'{queue = Queue, exchange = Exchange, routing_key = RoutingKey},
    #'queue.bind_ok'{} = amqp_channel:call(Channel, Binding)
{% endhighlight %}

在绑定的时候需要填入一个`routing_key`的参数，不同类型的exchange对该值的处理方式不一样，例如后面提到`fanout`类型的exchange时，就不需要该值。

## 更多细节

通过阅读[RabbitMQ tutorial](http://www.rabbitmq.com/getstarted.html)，我们还会获得很多细节信息。例如exchange的种类、binding等。

### exchange分类

exchange有四种类型，不同类型决定了其在收到消息后，该如何处理这条消息（投递规则），这四种类型为：

* fanout
* direct
* topic
* headers

**fanout**类型的exchange是一个广播exchange，它在收到消息后会将消息广播给所有绑定到它上面的队列。绑定(binding)用于将队列和exchange关联起来。我们可以在创建exchange的时候指定exchange的类型：

{% highlight erlang %}
    Declare = #'exchange.declare'{exchange = <<"my_exchange">>, type = <<"fanout">>}
    #'exchange.declare_ok'{} = amqp_channel:call(Channel, Declare)
{% endhighlight %}

**direct**类型的exchange在收到消息后，会将此消息投递到发送消息时指定的`routing_key`和绑定队列到exchange上时的`routing_key`相同的队列里。可以多次绑定一个队列到一个exchange上，每次指定不同的`routing_key`，就可以接收多种`routing_key`类型的消息。**注意，绑定队列时我们可以填入一个`routing_key`，发送消息时也可以指定一个`routing_key`。**


**topic**类型的exchange相当于是direct exchange的扩展，direct exchange在投递消息到队列时，是单纯的对`routing_key`做相等判定，而topic exchange则是一个`routing_key`的字符串匹配，就像正则表达式一样。在`routing_key`中可以填入一种字符串匹配符号：

    * (star) can substitute for exactly one word.
    # (hash) can substitute for zero or more words.

*header exchange tutorial中未提到，我也不深究*

### 消息投递及回应

每个消息都可以提供回应，以使RabbitMQ确定该消息确实被收到。RabbitMQ重新投递消息仅依靠与consumer的网络连接情况，所以只要网络连接正常，consumer卡死也不会导致RabbitMQ重投消息。如下回应消息：

{% highlight erlang %}
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag}),
{% endhighlight %}

其中`Tag`来源于接收到消息时里的`Tag`。

如果有多个consumer监听了一个队列，RabbitMQ会依次把消息投递到这些consumer上。这里的投递原则使用了`round robin`方法，也就是轮流方式。如前所述，如果某个consumer的处理逻辑耗时严重，则将导致多个consumer出现负载不均衡的情况，而RabbitMQ并不关心consumer的负载。可以通过消息回应机制来避免RabbitMQ使用这种消息数平均的投递原则：

{% highlight erlang %}
    Prefetch = 1,
    amqp_channel:call(Channel, #'basic.qos'{prefetch_count = Prefetch})
{% endhighlight %}

### 消息可靠性

RabbitMQ可以保证消息的可靠性，这需要设置消息和队列都为durable的：

{% highlight erlang %}
    #'queue.declare_ok'{queue = Q} = amqp_channel:call(Channel, #'queue.declare'{queue = <<"hello_queue">>, durable = true}),

    Payload = <<"foobar">>,
    Publish = #'basic.publish'{exchange = "", routing_key = Queue},
    Props = #'P_basic'{delivery_mode = 2}, %% persistent message
    Msg = #amqp_msg{props = Props, payload = Payload},
    amqp_channel:cast(Channel, Publish, Msg)
{% endhighlight %}


## 参考

除了参考RabbitMQ tutorial外，还可以看看别人使用erlang是如何实现这些tutorial的，github上有一个这样的项目：[rabbitmq-tutorials](https://github.com/rabbitmq/rabbitmq-tutorials/tree/master/erlang)。我自己也实现了一份，包括rabbitmq-tutorials中没实现的RPC。后来我发现原来[rabbitmq erlang client](https://github.com/kevinlynx/rabbitmq-erlang-client)的实现里已经包含了一个RPC模块。

* [RabbitMQ源码解析前奏--AMQP协议](http://blog.chinaunix.net/uid-22312037-id-3458208.html)
* [RabbitMQ+Python入门经典 兔子和兔子窝](http://blog.ftofficer.com/2010/03/translation-rabbitmq-python-rabbits-and-warrens/)
* [Erlang AMQP Client library](http://www.rabbitmq.com/erlang-client-user-guide.html)
* [Manage RabbitMQ by WebUI](http://www.rabbitmq.com/management.html)

