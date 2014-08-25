---
layout: post
title: "select真的有限制吗"
categories: [network]
tags: [network, select, FD_SET, fd_set]
comments: true
keywords: [network, select, FD_SET, fd_set]
description: 
---

在刚开始学习网络编程时，似乎莫名其妙地就会被某人/某资料告诉`select`函数是有fd(file descriptor)数量限制的。在最近的一次记忆里还有个人笑说`select`只支持64个fd。我甚至还写过一篇不负责任甚至错误的博客([突破select的FD_SETSIZE限制](http://www.cppblog.com/kevinlynx/archive/2008/05/20/50500.html))。有人说，直接重新定义`FD_SETSIZE`就可以突破这个`select`的限制，也有人说除了重定义这个宏之外还的重新编译内核。

事实具体是怎样的？实际上，造成这些混乱的原因恰好是不同平台对`select`的实现不一样。

## Windows的实现

[MSDN](http://msdn.microsoft.com/en-us/library/windows/desktop/ms740141(v=vs.85).aspx)上对`select`的说明：

    int select(
      _In_     int nfds,
      _Inout_  fd_set *readfds,
      _Inout_  fd_set *writefds,
      _Inout_  fd_set *exceptfds,
      _In_     const struct timeval *timeout
    );

    nfds [in] Ignored. The nfds parameter is included only for compatibility with Berkeley sockets.

第一个参数MSDN只说没有使用，其存在仅仅是为了保持与Berkeley Socket的兼容。

> The variable FD_SETSIZE determines the maximum number of descriptors in a set. (The default value of FD_SETSIZE is 64, which can be modified by defining FD_SETSIZE to another value before including Winsock2.h.) Internally, socket handles in an fd_set structure are not represented as bit flags as in Berkeley Unix.

Windows上`select`的实现不同于Berkeley Unix，**后者使用位标志来表示socket**。
<!-- more -->
在MSDN的评论中有人提到：

> Unlike the Linux versions of these macros which use a single calculation to set/check the fd, the Winsock versions use a loop which goes through the entire set of fds each time you call FD_SET or FD_ISSET (check out winsock2.h and you'll see). So you might want to consider an alternative if you have thousands of sockets!

不同于Linux下处理`fd_set`的那些宏(FD_CLR/FD_SET之类)，Windows上这些宏的实现都使用了一个循环，看看这些宏的大致实现(Winsock2.h)：

    #define FD_SET(fd, set) do { \
        u_int __i; \
        for (__i = 0; __i < ((fd_set FAR *)(set))->fd_count; __i++) { \
            if (((fd_set FAR *)(set))->fd_array[__i] == (fd)) { \
                break; \
            } \
        } \
        if (__i == ((fd_set FAR *)(set))->fd_count) { \
            if (((fd_set FAR *)(set))->fd_count < FD_SETSIZE) { \
                ((fd_set FAR *)(set))->fd_array[__i] = (fd); \
                ((fd_set FAR *)(set))->fd_count++; \
            } \
        } \
    } while(0)

看下Winsock2.h中关于`fd_set`的定义：

    typedef struct fd_set {
        u_int fd_count;
        SOCKET fd_array[FD_SETSIZE];
    } fd_set;

再看一篇更重要的MSDN [Maximum Number of Sockets Supported](http://msdn.microsoft.com/en-us/library/windows/desktop/ms739169(v=vs.85).aspx)：

> The Microsoft Winsock provider limits the maximum number of sockets supported only by available memory on the local computer.
> The maximum number of sockets that a Windows Sockets application can use is not affected by the manifest constant FD_SETSIZE.
> If an application is designed to be capable of working with more than 64 sockets using the select and WSAPoll functions, the implementor should define the manifest FD_SETSIZE in every source file before including the Winsock2.h header file.

Windows上`select`支持的socket数量并不受宏`FD_SETSIZE`的影响，而仅仅受内存的影响。如果应用程序想使用超过`FD_SETSIZE`的socket，仅需要重新定义`FD_SETSIZE`即可。

实际上稍微想想就可以明白，既然`fd_set`里面已经有一个socket的数量计数，那么`select`的实现完全可以使用这个计数，而不是`FD_SETSIZE`这个宏。那么结论是，**`select`至少在Windows上并没有socket支持数量的限制。**当然效率问题这里不谈。

这看起来推翻了我们一直以来没有深究的一个事实。

## Linux的实现

在上面提到的MSDN中，其实已经提到了Windows与Berkeley Unix实现的不同。在`select`的API文档中也看到了第一个参数并没有说明其作用。看下Linux的[man](http://linux.die.net/man/2/select)：

> nfds is the highest-numbered file descriptor in any of the three sets, plus 1.

第一个参数简单来说就是最大描述符+1。

> An fd_set is a fixed size buffer. Executing FD_CLR() or FD_SET() with a value of fd that is negative or is equal to or larger than FD_SETSIZE will result in undefined behavior. 

明确说了，如果调用`FD_SET`之类的宏fd超过了`FD_SETSIZE`将导致`undefined behavior`。也有人专门做了测试：[select system call limitation in Linux](http://www.moythreads.com/wordpress/2009/12/22/select-system-call-limitation/)。也有现实遇到的问题：[socket file descriptor (1063) is larger than FD_SETSIZE (1024), you probably need to rebuild Apache with a larger FD_SETSIZE](http://serverfault.com/questions/497086/socket-file-descriptor-1063-is-larger-than-fd-setsize-1024-you-probably-nee)

看起来在Linux上使用`select`确实有`FD_SETSIZE`的限制。有必要看下相关的实现 [fd_set.h](http://fxr.watson.org/fxr/source/sys/fd_set.h?v=NETBSD)：

    typedef __uint32_t      __fd_mask;
    
    /* 32 = 2 ^ 5 */
    #define __NFDBITS       (32)
    #define __NFDSHIFT      (5)
    #define __NFDMASK       (__NFDBITS - 1)
   
    /*
     * Select uses bit fields of file descriptors.  These macros manipulate
     * such bit fields.  Note: FD_SETSIZE may be defined by the user.
     */
   
    #ifndef FD_SETSIZE
    #define FD_SETSIZE      256
    #endif
   
    #define __NFD_SIZE      (((FD_SETSIZE) + (__NFDBITS - 1)) / __NFDBITS)

    typedef struct fd_set {
        __fd_mask       fds_bits[__NFD_SIZE];
    } fd_set;


在这份实现中不同于Windows实现，它使用了位来表示fd。看下`FD_SET`系列宏的大致实现：


    #define FD_SET(n, p)    \
       ((p)->fds_bits[(unsigned)(n) >> __NFDSHIFT] |= (1 << ((n) & __NFDMASK)))

添加一个fd到`fd_set`中也不是Windows的遍历，而是直接位运算。这里也有人对另一份类似实现做了剖析：[linux的I/O多路转接select的fd_set数据结构和相应FD_宏的实现分析](http://my.oschina.net/u/870054/blog/212063)。在APUE中也提到`fd_set`：

> 这种数据类型(fd_set)为每一可能的描述符保持了一位。

既然`fd_set`中不包含其保存了多少个fd的计数，那么`select`的实现里要知道自己要处理多少个fd，那只能使用FD_SETSIZE宏去做判定，但Linux的实现选用了更好的方式，即通过第一个参数让应用层告诉`select`需要处理的最大fd（这里不是数量）。那么其实现大概为：

    for (int i = 0; i < nfds; ++i) {
        if (FD_ISSET...
           ...
    }

如此看来，**Linux的`select`实现则是受限于`FD_SETSIZE`的大小**。这里也看到，`fd_set`使用位数组来保存fd，那么fd本身作为一个int数，其值就不能超过`FD_SETSIZE`。**这不仅仅是数量的限制，还是其取值的限制**。实际上，Linux上fd的取值是保证了小于`FD_SETSIZE`的（但不是不变的）[Is the value of a Linux file descriptor always smaller than the open file limits?](http://stackoverflow.com/questions/12583927/is-the-value-of-a-linux-file-descriptor-always-smaller-than-the-open-file-limits)：

> Each process is further limited via the setrlimit(2) RLIMIT_NOFILE per-process limit on the number of open files. 1024 is a common RLIMIT_NOFILE limit. (It's very easy to change this limit via /etc/security/limits.conf.)

fd的取值会小于`RLIMIT_NOFILE`，有很多方法可以改变这个值。这个值默认情况下和`FD_SETSIZE`应该是一样的。这个信息告诉我们，**Linux下fd的取值应该是从0开始递增的**（理论上，实际上还有stdin/stdout/stderr之类的fd）。这才能保证`select`的那些宏可以工作。


## 应用层使用

标准的`select`用法应该大致如下：

    while (true) {
        ...
        select(...)
        for-each socket {
            if (FD_ISSET(fd, set))
                ...
        }
            
        ...
    }

即遍历目前管理的fd，通过`FD_ISSET`去判定当前fd是否有IO事件。因为Windows的实现`FD_ISSET`都是一个循环，所以有了另一种不跨平台的用法：


    while (true) {
        ...
        select(. &read_sockets, &write_sockets..)
        for-each read_socket {
            use fd.fd_array[i)
        }
        ...
    }

## 总结

* Windows上`select`没有fd数量的限制，但因为使用了循环来检查，所以效率相对较低
* Linux上`select`有`FD_SETSIZE`的限制，但其相对效率较高

