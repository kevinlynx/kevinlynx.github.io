---
layout: post
title: "分布式程序开发平台ICE概览"
categories: [c/c++, ICE]
tags: ice
comments: true
keywords: ICE
description: 本文基于ICE Manual及相关文档就ICE的一些主要特性做一个概览
---

本文基于ICE Manual及相关文档就ICE的一些主要特性做一个概览，它不是一个tutorial，不是一个guid，更不是manual。

## 概览

[ICE](http://www.zeroc.com/index.html)，Internet Communications Engine，按照官方介绍，是一个支持C++、.Net、Java、Python、Objective-C、Ruby、PHP及ActionScript等语言的分布式程序开发平台。按照我的理解，简单来说它是一个核心功能包装RPC的库。要把这个RPC包装得漂亮，自然而然，对于使用者而言，调用一个远端的接口和调用一个本地的接口没有什么区别，例如：

{% highlight c++ %}
    Object *obj = xxx
    obj->sayHello(); 
{% endhighlight %}

ICE包装`sayHello`接口，当应用层调用该接口时，ICE发送调用请求到远端服务器，接收返回结果并返回给应用层。ICE在接口提供方面，做到了这一点。

以下，我将逐个给出ICE中的一些工具、组件、特性说明，以展示它作为一个分布式程序开发平台所拥有的能力。到目前为止，所有这些信息均来自于ICE相关文档，总结出来权当为自己服务。
<!-- more -->
## Slice

Slice(Specification Language for Ice)是ICE定义的一种中间语言，其语法类似于C++。对于一个RPC过程而言，例如上面调用远端的`sayHello`接口，其主要涉及到调用这个接口的参数和返回值传递，当然接口本身的传递不在话下，ICE为了包装这个过程，其使用了这样一种方式：使用者使用Slice语言描述RPC过程中调用的接口，例如该接口属于哪个类，该接口有哪些参数哪些返回值；然后使用者使用ICE提供的Slice编译器（实际上是一个语言翻译程序）将Slice源码翻译成目标语言。而这个目标语言，则是使用者开发应用程序的开发语言，即上文提到的C++、.Net、Java等。

这些翻译出来的目标代码，就封装了`sayHello`底层实现的一切细节。当然事情没有这么简单，但我们目前只需关注简单的这一部分。ICE之所以支持那么多种开发语言，正是Slice立下的功劳。Slice语言本身的语言特性，实际上受限于目标语言的语言特性，例如Slice支持异常，恰是因为Slice转换的所有语言都包含异常这个语法特性。

Slice还有一个重要特性，在于一份Slice源码被翻译出来的目标代码，一般情况是被服务器和客户端同时使用。

## 开发步骤

使用ICE开发应用程序，其步骤遵循：

1. 编写Slice，说明整个RPC中涉及到的接口调用，编译它
2. 基于Slice目标代码和ICE库编写Server
3. 基于Slice目标带啊和ICE库编写Client

## 一个例子

有必要展示一个例子，以获得使用ICE开发应用程序的感性认识。这个例子是一个简单的hello world程序，客户端让服务器打印一个字符串。

* 编写Slice

{% highlight c++ %}
    // Printer.ice，Slice源码后缀为ice
    module Demo {
        interface Printer {
            void printString(string s);
        };
    };

{% endhighlight %}

使用ICE提供的程序翻译为C++代码：

{% highlight c++ %}
    $ slice2cpp Printer.ice
{% endhighlight %}

得到Printer.cpp和Printer.h。Slice翻译出来的目标代码除了封装RPC交互的一些细节外，最重要的，因为本身Slice文件其实是定义接口，但接口的实现，则需要应用层来做。

* 服务器端使用生成的Printer.cpp/.h，并实现Printer接口

{% highlight c++ %}
    // 翻译出来的Printer.h中有对应于Slice中定义的Printer类，及需要实现的printString接口
    class PrinterI : public Printer {
    public:
        virtual void printString(const string& s, const Ice::Current&) {
            count << s << endl;
        }
    };
{% endhighlight %}

* 客户端使用生成的Printer.cpp/.h，通过ICE获得一个`Printer`对象，然后调用其`printString`接口

{% highlight c++ %}
    // don't care about this
    PrinterPrx printer = PrinterPrx::checkedCast(base);
    printer->printString("Hello World!");
{% endhighlight %}

使用ICE开发应用程序，整体过程即为以上展示。

## 概念

ICE包含了很多概念，作为一个开发平台而言，有其专有术语一点不过分，熟悉这些概念可以更容易学习ICE。这里罗列一些关键概念。

### 服务器端和客户端

ICE中的服务器端和客户端和一般网络程序中的概念不太一样。在若干个交互的网络程序中，我们都很好理解这样一种现象：某个程序有多个角色，它可能是作为A程序的服务器端，也可能是作为B程序的客户端。ICE中的服务器和客户端角色更容易变换。

以Printer例子为例，如果我们的`printString`接口有一个回调函数参数（这在ICE中很常见），服务器实现`printString`时，当其打印出字符串后，需通过该回调函数通知客户端。这样的回调机制在ICE的实现中，会创建一个新的网络连接，而此时，这个原有的服务器端就变成了原有客户端的客户。当然，你也可以避免这样的情况出现。

### ICE Objects/Object Adapter/Facet

对于`Printer`例子，一个`Printer`对象可以被看作是一个ICE Objects。Object可以说是服务器端提供给客户端的接口。所以在服务器端通常会创建出很多个Object。服务器端使用Object Adapter对象去保存这些Object。例如，一个典型的ICE对象在初始化时可能包含以下代码：

{% highlight c++ %}
    // 创建一个Object Adapter
    Ice::ObjectAdapterPtr adapter = communicator()->createObjectAdapter("Hello");
    // 创建一个Object，形如Printer
    Demo::HelloPtr hello = new HelloI;
    // 将Object加入到Object Adapter
    adapter->add(hello, communicator()->stringToIdentity("hello"));
{% endhighlight %}

Facet是Object的一部分，或者说Object是Facet的一个集合，摘Ice manual中的一句话：

> An Ice object is actually a collection of sub-objects known as facets whose types are not necessarily related.

### Proxy

Proxy是ICE客户端里的概念。客户端通过Proxy访问服务器端上的Object，通过Proxy调用服务器端Object上提供的接口。在客户端上一般有类似以下代码：

{% highlight c++ %}
    Ice::ObjectPrx base = ic->stringToProxy("SimplePrinter:default -p 10000");
    // Printer Proxy
    PrinterPrx printer = PrinterPrx::checkedCast(base);
    printer->printString("Hello World!");
{% endhighlight %}

Proxy又分为几种，包括：

#### Direct Proxy

Direct Proxy，这里的`direct`意指这个proxy访问的object时，是否携带了地址(EndPoint)信息，例如上面例子中`SimplePrinter:default -p 10000`就是一个地址。

#### Indirect Proxy

Indirect Proxy相对Direct Proxy而言，其没有具体的地址，仅仅是一个符号。通常包含两种形式：

* SimplePrinter
* SimplePrinter@PrinterAdapter

为了获取真正的地址，客户端需要一个定位服务（location service）来获取这个符号对应的地址。ICE中提供了一些默认的服务程序，IceGrid就是其中之一，而IceGrid的作用就包括定位具体的地址，即翻译符号地址到具体的地址。

这里Indirect Proxy可以看作一个域名，而Direct Proxy可以看作是IP地址。Indirect Proxy使用时，就需要借助DNS翻译得到域名对应的IP地址。

#### Fixed Proxy

由于Proxy是用于与服务器端的Object通信的，客户端借助Proxy来访问服务器端的Object，所以Proxy通常都会对应一个真实的网络连接。在ICE中，一般的Proxy于网络连接(Connection)实际上是没有太大关联的。一个Proxy可以没有Connection，也可以在建立这个Connection后又断开之。但是，ICE提供了一种特殊的Proxy，Fixed Proxy，这种Proxy紧密地与一个Connection绑定在一起，其生命周期被强制关联起来。

关于Fixed Proxy可以参看ICE Manual [Connection Management](http://doc.zeroc.com/display/Doc/Connection+Management+in+Ice)。

### 其他 

* AMI

Asynchronous Method Invocation，对于客户端而言，用于表示某个服务器端接口是异步操作，需在Slice中使用metadata来修饰这个接口，例如：

{% highlight c++ %}
    ["ami"]  void sayHello(int delay)
{% endhighlight %}

* AMD

Asynchronous method dispatch，这个针对于服务器端，同样表示这个接口是异步操作，需在Slice中使用metadata来修饰这个接口：

{% highlight c++ %}
    ["ami", "amd"]  void sayHello(int delay)
{% endhighlight %}

通常对于这种异步接口而言，都需要使用Slice metadata `ami`和`amd`同时修饰。

* idempotent

idempotent是Slice中的概念，同const一样用于修饰某个接口的特性。idempotent表示该接口无论调用多少次，其执行结果都是相同的，例如一般的`get`类接口。

* batched invocation

客户端调用服务器端的接口这个动作称为`invocation`。就像网络层的数据缓存一样，ICE对于接口调用也可能暂时缓存，当多个提交请求缓存起来后，然后调用刷新接口全部刷新到服务器端，则称为`batched invocation`。

## 服务

ICE除了提供一个库之外，还提供了一些应用程序。这些应用程序本身也是一些服务器，提供了一些方便的功能方便我们开发分布式程序。

### Freeze

Freeze用于将Slice对象持久化到数据库中，按照Manual里的说法，它应该是一个编译器，可以生成一些持久化操作的代码。Freeze持久化对象时使用的数据库是Berkeley DB。

> Ice has a built-in object persistence service, known as Freeze. Freeze makes it easy to store object state in a database: you define the state stored by your objects in Slice, and the Freeze compiler generates code that stores and retrieves object state to and from a database. Freeze uses Berkeley DB as its database.

FreezeScript有点类似于Rails中的数据库操作工具，可用于操作持久化到数据库中的对象数据。

> Ice also offers a tool set collectively called FreezeScript that makes it easier to maintain databases and to migrate the contents of existing databases to a new schema if the type definitions of objects change.

### IceBox

IceBox可用于管理服务器中的动态组件。这些动态组件本质上也是提供服务的ICE程序。在形式上，这些组件可以是动态连接库。

> IceBox is a simple application server that can orchestrate the starting and stopping of a number of application components. Application components can be deployed as a dynamic library instead of as a process.

### IceGrid

IceGrid相当于一个DNS解析服务，可以让服务器不用配置EndPoint，客户端也不用指定服务器的EndPoint，以方便大量的服务器部署。在一般的应用中，我们需要为ICE服务器指定绑定的网络地址（IP和端口），同时也需要为客户端指定服务器端的地址信息。当服务增加到一定数量时，就会存在管理上和配置上的麻烦。而IceGrid则是用于避免这种麻烦，将服务器端和客户端上的地址信息通过一个符号代替，就像我们把Internet上的服务器使用域名来标识一样。

但IceGrid的作用不仅如此，通过配合部署一系列称为IceGrid Node的程序，IceGrid还可以管理各个服务器的启动、关闭、宕机重启等，其中甚至包括负载均衡。

> IceGrid provides a facility to activate servers on demand, when a client first invokes an operation.
> Server activation is taken care of by IceGrid nodes. You must run an IceGrid node on each machine on which you want IceGrid to start servers on demand.

简要介绍可以参看ICE Manual [Teach Yourself IceGrid in 10 minutes](http://doc.zeroc.com/display/Doc/Teach+Yourself+IceGrid+in+10+Minutes)

### Glacier2

> Glacier2 is a lightweight firewall traversal solution for Ice applications.

按我的理解，Glacier2就像一个网关服务器。它被部署在服务器和客户端之间，我们的服务器群部署在内网，外网不可访问，然后通过Glacier2，外部网络的客户端就可以访问内网的服务器群提供的服务。

对于服务器的开发而言，使用Glacier2，服务器端不需要做任何改动。客户端需要配置Glacier2服务的地址信息，也需要配置要使用服务器的地址信息。Glacier2通过客户端欲访问的服务器地址，在内网定位到真实的服务器，并转发请求提供服务。

Glacier2支持验证客户端，从这一点看来，它又有点像一个验证服务器。通过验证客户端，以提供被正确授权的客户端以完整服务。

Glacier2的工作过程可以描述为：

> When a client invokes an operation on a routed proxy, the client connects to one of Glacier2's client endpoints and sends the request as if Glacier2 is the server. Glacier2 then establishes an outgoing connection to the client's intended server in the private network, forwards the request to that server, and returns the reply (if any) to the client. Glacier2 is essentially acting as a local client on behalf of the remote client.

一个Glacier2可服务于若干个客户端和服务器。

详细参看ICE Manual [Glacier2](http://doc.zeroc.com/display/Ice/Glacier2)

## 管理

ICE服务器可以提供给外部一定的管理功能，包括：关闭服务器、读取服务器配置。这个功能是通过操作Ice.Admin这个Ice Object来实现的。这个Object包含两个Facet：Process和Property，分别对应于关闭服务器和读取服务器配置功能。

对于需要管理服务器的客户端而言，可以大致通过如下代码来完成：

{% highlight c++ %}
    // 可以通过communicator来获取这个admin object
    Ice::ObjectPrx adminObj = ...;
    // 获取admin object里的property facet
    Ice::PropertiesAdminPrx propAdmin = Ice::PropertiesAdminPrx::checkedCast(adminObj, "Properties");
    Ice::PropertyDict props = propAdmin->getPropertiesForPrefix("");
{% endhighlight %}

详细参看ICE Manual [Administrative Facility](http://doc.zeroc.com/display/Ice/Administrative+Facility)

## 连接管理

前已述及，ICE中的网络连接隐藏于Proxy之下。Proxy有两个接口可以获取这个连接对象：

{% highlight c++ %}
    ice_getConnection
    ice_getCachedConnection
{% endhighlight %}

例如：

{% highlight c++ %}
    HelloPrx hello = HelloPrx::uncheckedCast(communicator->stringToProxy("hello:tcp -h remote.host.com -p 10000"));
    ConnectionPtr conn = hello->ice_getConnection();
{% endhighlight %}

ICE隐藏了网络连接的细节。当ICE发现需要建立连接时才会去建立，例如以上例子中当获得一个Proxy时（这里是HelloPrx），ICE并不建立网络连接，当某个时刻通过该Proxy调用服务器端的某个接口时，ICE发现对应的网络连接没有建立，则发起网络连接。

以上例子在获取Proxy时，使用了`uncheckCast`，关于`checkedCast`和`uncheckedCast`，也影响着网络连接的建立逻辑：

> On the other hand, if the code were to use a checkedCast instead, then connection establishment would take place as part of the checkedCast, because a checked cast requires a remote call to determine whether the target object supports the specified interface. 

关于连接管理，ICE使用了一个称为ACM的机制，即Active connection management。当某个连接非active一段时间后，ICE就会主动关闭此连接。应用层当然可以控制这个行为。

详细参看ICE Manual [Connection Management](http://doc.zeroc.com/display/Doc/Connection+Management+in+Ice)


