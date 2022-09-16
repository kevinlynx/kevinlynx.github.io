---
layout: post
title: "记一次线程局部存储与动态库引起的core"
category: c/c++
tags: TLS
comments: true
---

线上的服务退出时coredump，显示堆栈为：

![](/assets/res/tls_so_core/core.JPG)

google一下发现[有人遇到过](http://www.tuicool.com/articles/YJ3A7f)，产生这个core的条件为：

* 使用TLS时注册了destructor (`pthread_key_create`)，这个回调函数会在线程退出时被调用
* 这个destructor符号位于.so中
* 在线程退出时，这个.so已经被dlclose

我们的程序模型中，类似于一个Web App server，有一个线程池包装了IO处理，将请求派发给应用插件，处理完后回应给客户端。应用插件是一个.so，被动态载入(dlopen)，该.so由于实现需要引入了较多的第三方.so(隐式载入)。初步排查时，整个实现是没有问题的，线程池是在.so close前关闭的。

没有线索，于是尝试找到该TLS是哪个模块引入的。通过gdb断`pthread_key_create`，以及不为空的destructor回调可以确定几个模块，但范围不够小，这些模块基本还是些基础模块，如zookeeper/mxml以及网络模块。

多看了几个core，发现这个回调的偏移地址都是固定的960，如上图中的`0x7f0f26c9f960`。.so被载入时，基址是会变的，但偏移是不会变的，例如通过nm查看.so中的符号时：

```
$nm lib/libsp_kit.so | grep loadConfig
00000000002de170 T _ZN8sp_basic14SortRailConfig10loadConfigEPKc
```
<!-- more -->
其中`2de170`中`170`是确定不变的。所以范围可以进一步缩小，destructor是`pthread_key_create`第二个参数，每次断点触发时查看`rsi`寄存器的值就可以确定，然后发现落在了mxml库里的符号：

![](/assets/res/tls_so_core/mxml.JPG)

程序在启动时载入配置，触发了mxml在当前线程创建了TLS，这个线程是程序主线程。主线程当然是在.so被close后才退出的。如果这是问题，那应该很早前就会暴露。这是一个问题，后面会解释。但是问题排查到这个地方，又陷入了僵局。

回头再看下core环境，可以从线程环境确定是哪个模块： 


![](/assets/res/tls_so_core/arpc-threads.JPG)

core的线程31956和线程31955靠近，查看31955堆栈，发现是我们内部的rpc库(arpc)线程。那可以确定core的线程有可能和arpc有关系。函数在调用时，返回地址留在堆栈中，堆栈不一定会被其他内容覆盖，所以可以查看线程堆栈里的符号地址，大概确定是什么模块。`x/200a $rsp-0x300`查看core线程堆栈：

![](/assets/res/tls_so_core/arpc-stack.JPG)

可以看到其中确实有arpc库里的符号信息，综合线程号关系，基本可以确定core的线程是arpc线程。这个时候就突然灵关一闪，想起我们程序中有热切换机制。该机制会在收到arpc请求时，重新载入所有配置，而这个动作是发生在arpc开的线程里。查看相关代码，发现arpc资源释放确实是晚于.so的close的。于是做了下实验，程序开启后进行一次热切换，退出后果然必core。程序在生产环境时，只在业务上线时进行一次热切换，而每天又会被自动重启，重启后并不进行热切换，所以线上基本上没有暴露出来，只在部分灰度环境偶尔触发(连续两次业务上线)。

回过头来，主线程问题怎么解释？google一圈发现，**主线程退出，是不会调用TLS destructor的**。参考[这里](https://github.com/rust-lang/rust/issues/28129)，[这里](http://stackoverflow.com/questions/6357154/destruction-order-of-the-main-thread-and-the-use-of-pthread-key-create)，以及[这里](https://github.com/rust-lang/rust/issues/19776)。但是可以在主线程中显示调用`pthread_exit`来触发，普通线程会默认调用`pthread_exit`。

完。


