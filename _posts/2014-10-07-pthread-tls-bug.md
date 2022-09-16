---
layout: post
title: "浅析glibc中thread tls的一处bug"
category: c/c++
tags: [pthread, tls]
comments: true
---

最早的时候是在程序初始化过程中开启了一个timer(`timer_create`)，这个timer第一次触发的时间较短时就会引起程序core掉，core的位置也是不定的。使用valgrind可以发现有错误的内存写入：

    ==31676== Invalid write of size 8
    ==31676==    at 0x37A540F852: _dl_allocate_tls_init (in /lib64/ld-2.5.so)
    ==31676==    by 0x4E26BD3: pthread_create@@GLIBC_2.2.5 (in /lib64/libpthread-2.5.so)
    ==31676==    by 0x76E0B00: timer_helper_thread (in /lib64/librt-2.5.so)
    ==31676==    by 0x4E2673C: start_thread (in /lib64/libpthread-2.5.so)
    ==31676==    by 0x58974BC: clone (in /lib64/libc-2.5.so)
    ==31676==  Address 0xf84dbd0 is 0 bytes after a block of size 336 alloc'd
    ==31676==    at 0x4A05430: calloc (vg_replace_malloc.c:418)
    ==31676==    by 0x37A5410082: _dl_allocate_tls (in /lib64/ld-2.5.so)
    ==31676==    by 0x4E26EB8: pthread_create@@GLIBC_2.2.5 (in /lib64/libpthread-2.5.so)
    ==31676==    by 0x76E0B00: timer_helper_thread (in /lib64/librt-2.5.so)
    ==31676==    by 0x4E2673C: start_thread (in /lib64/libpthread-2.5.so)
    ==31676==    by 0x58974BC: clone (in /lib64/libc-2.5.so)

google `_dl_allocate_tls_init` 相关发现一个glibc的bug [Bug 13862](https://sourceware.org/bugzilla/show_bug.cgi?id=13862) 和我的情况有点类似。本文就此bug及tls相关实现做一定阐述。

需要查看glibc的源码，如何确认使用的glibc的版本，可以这样：

    $ /lib/libc.so.6
    GNU C Library stable release version 2.5, by Roland McGrath et al.
    ...

为了方便，还可以直接在(glibc Cross Reference)[http://osxr.org/glibc/source/?v=glibc-2.17]网页上进行查看，版本不同，但影响不大。
<!-- more -->
## BUG描述

要重现13862 BUG作者提到要满足以下条件：

> The use of a relatively large number of dynamic libraries, loaded at runtime using dlopen.

> The use of thread-local-storage within those libraries.

> A thread exiting prior to the number of loaded libraries increasing a significant amount, followed by a new thread being created after the number of libraries has increased.

简单来说，就是在加载一大堆包含TLS变量的动态库的过程中，开启了一个线程，这个线程退出后又开启了另一个线程。

这和我们的问题场景很相似。不同的是我们使用的是timer，但timer在触发时也是开启新的线程，并且这个线程会立刻退出：

`/nptl/sysdeps/unix/sysv/linux/timer_routines.c`

{% highlight c++ %}
timer_helper_thread(...)  // 用于检测定时器触发的辅助线程
{
    ...
      pthread_t th;
      (void) pthread_create (&th, &tk->attr, timer_sigev_thread, // 开启一个新线程调用用户注册的定时器函数
                 td);
    ...
} 
{% endhighlight %}

要重现此BUG可以使用我的实验代码 [thread-tls](https://gist.github.com/kevinlynx/69435e718785a0ad12c4)，或者使用[Bug 13862 中的附件](https://sourceware.org/bugzilla/attachment.cgi?id=6290)

## TLS相关实现

可以顺着`_dl_allocate_tls_init`函数的实现查看相关联的部分代码。该函数遍历所有加载的包含TLS变量的模块，初始化一个线程的TLS数据结构。

每一个线程都有自己的堆栈空间，其中单独存储了各个模块的TLS变量，从而实现TLS变量在每一个线程中都有单独的拷贝。TLS与线程的关联关系可以查看下图：

![](/assets/res/pthread-tls.png)

应用层使用的`pthread_t`实际是个`pthread`对象的地址。创建线程时线程的堆栈空间和`pthread`结构是一块连续的内存。但这个地址并不指向这块内存的首地址。相关代码：/nptl/allocatestack.c `allocate_stack`，该函数分配线程的堆栈内存。

`pthread`第一个成员是`tcbhead_t`，`tcbhead_t`中`dtv`指向了一个`dtv_t`数组，该数组的大小随着当前程序载入的模块多少而动态变化。每一个模块被载入时，都有一个`l_tls_modid`，其直接作为`dtv_t`数组的下标索引。`tcbhead_t`中的`dtv`实际指向的是`dtv_t`第二个元素，第一个元素用于记录整个`dtv_t`数组有多少元素，第二个元素也做特殊使用，从第三个元素开始，才是用于存储TLS变量。

一个`dtv_t`存储的是一个模块中所有TLS变量的地址，当然这些TLS变量都会被放在连续的内存空间里。`dtv_t::pointer::val`正是用于指向这块内存的指针。对于非动态加载的模块它指向的是线程堆栈的位置；否则指向动态分配的内存位置。

以上结构用代码描述为，

{% highlight c++ %}
union dtv_t {
    size_t counter;
    struct {
        void *val; /* point to tls variable memory */
        bool is_static;
    } pointer;
};
 
struct tcbhead_t {
    void *tcb;
    dtv_t *dtv; /* point to a dtv_t array */
    void *padding[22]; /* other members i don't care */
};

struct pthread {
    tcbhead_t tcb;
    /* more members i don't care */
};
{% endhighlight %}

**dtv是一个用于以模块为单位存储TLS变量的数组**。

实际代码参看 /nptl/descr.h 及 nptl/sysdeps/x86_64/tls.h。

### 实验

使用`g++ -o thread -g -Wall -lpthread -ldl thread.cpp`编译[代码](https://gist.github.com/kevinlynx/69435e718785a0ad12c4)，即在创建线程前加载了一个.so：

    Breakpoint 1, dump_pthread (id=1084229952) at thread.cpp:40
    40          printf("pthread %p, dtv %p\n", pd, dtv);
    (gdb) set $dtv=pd->tcb.dtv
    (gdb) p $dtv[-1]
    $1 = {counter = 17, pointer = {val = 0x11, is_static = false}}
    (gdb) p $dtv[3]
    $2 = {counter = 18446744073709551615, pointer = {val = 0xffffffffffffffff, is_static = false}}

`dtv[3]`对应着动态加载的模块，`is_static=false`，`val`被初始化为-1：

/elf/dl-tls.c `_dl_allocate_tls_init`

{% highlight c++ %}
if (map->l_tls_offset == NO_TLS_OFFSET
   || map->l_tls_offset == FORCED_DYNAMIC_TLS_OFFSET)
 {
   /* For dynamically loaded modules we simply store
      the value indicating deferred allocation.  */
   dtv[map->l_tls_modid].pointer.val = TLS_DTV_UNALLOCATED;
   dtv[map->l_tls_modid].pointer.is_static = false;
   continue;
 }
{% endhighlight %}

`dtv`数组大小之所以为17，可以参看代码 /elf/dl-tls.c `allocate_dtv`：

{% highlight c++ %}
// dl_tls_max_dtv_idx 随着载入模块的增加而增加，载入1个.so则是1 

dtv_length = GL(dl_tls_max_dtv_idx) + DTV_SURPLUS; // DTV_SURPLUS 14
dtv = calloc (dtv_length + 2, sizeof (dtv_t));
if (dtv != NULL)
 {
   /* This is the initial length of the dtv.  */
   dtv[0].counter = dtv_length;
{% endhighlight %}

继续上面的实验，当调用到.so中的`function`时，其TLS被初始化，此时`dtv[3]`中`val`指向初始化后的TLS变量地址：

    68          fn();
    (gdb)
    0x601808, 0x601804, 0x601800
    72          return 0;
    (gdb) p $dtv[3]
    $3 = {counter = 6297600, pointer = {val = 0x601800, is_static = false}}
    (gdb) x/3xw 0x601800
    0x601800:       0x55667788      0xaabbccdd      0x11223344

这个时候还可以看看`dtv[1]`中的内容，正是指向了`pthread`前面的内存位置：

    (gdb) p $dtv[1]
    $5 = {counter = 1084229936, pointer = {val = 0x40a00930, is_static = true}}
    (gdb) p/x tid
    $7 = 0x40a00940

**结论**:

* 线程中TLS变量的存储是以模块为单位的

## so模块加载

这里也并不太需要查看`dlopen`等具体实现，由于使用`__thread`来定义TLS变量，整个实现涉及到ELF加载器的一些细节，深入下去内容较多。这里直接通过实验的手段来了解一些实现即可。

上文已经看到，**在创建线程前如果动态加载了.so，dtv数组的大小是会随之增加的**。如果是在线程创建后再载入.so呢？


使用`g++ -o thread -g -Wall -lpthread -ldl thread.cpp -DTEST_DTV_EXPAND -DSO_CNT=1`编译程序，调试得到：

    73          load_sos();
    (gdb)
    0x601e78, 0x601e74, 0x601e70

    Breakpoint 1, dump_pthread (id=1084229952) at thread.cpp:44
    44          printf("pthread %p, dtv %p\n", pd, dtv);
    (gdb) p $dtv[-1]
    $3 = {counter = 17, pointer = {val = 0x11, is_static = false}}
    (gdb) p $dtv[4]
    $4 = {counter = 6299248, pointer = {val = 0x601e70, is_static = false}}

在新载入了.so时，`dtv`数组大小并没有新增，`dtv[4]`直接被拿来使用。

因为`dtv`初始大小为16，那么当载入的.so超过这个数字的时候会怎样？

使用`g++ -o thread -g -Wall -lpthread -ldl thread.cpp -DTEST_DTV_EXPAND`编译程序：

    ...
    pthread 0x40a00940, dtv 0x6016a0
    ...
    Breakpoint 1, dump_pthread (id=1084229952) at thread.cpp:44
    44          printf("pthread %p, dtv %p\n", pd, dtv);
    (gdb) p dtv
    $2 = (dtv_t *) 0x6078a0
    (gdb) p dtv[-1]
    $3 = {counter = 32, pointer = {val = 0x20, is_static = false}}
    (gdb) p dtv[5]
    $4 = {counter = 6300896, pointer = {val = 0x6024e0, is_static = false}}
    
   
可以看出，`dtv`被重新分配了内存(0x6016a0 -> 0x6078a0)并做了扩大。

以上得出结论：

* 创建线程前dtv的大小会根据载入模块数量决定
* 创建线程后新载入的模块会动态扩展dtv的大小(必要的时候)


## pthread堆栈重用

在`allocate_stack`中分配线程堆栈时，有一个从缓存中取的操作：

{% highlight c++ %}
allocate_stack(..) {
    ...
    pd = get_cached_stack (&size, &mem);
    ...
}
/* Get a stack frame from the cache.  We have to match by size since
   some blocks might be too small or far too large.  */
get_cached_stack(...) {
    ...
    list_for_each (entry, &stack_cache) // 根据size从stack_cache中取
    { ... }
    ...
    /* Clear the DTV.  */
    dtv_t *dtv = GET_DTV (TLS_TPADJ (result));
    for (size_t cnt = 0; cnt < dtv[-1].counter; ++cnt)
        if (! dtv[1 + cnt].pointer.is_static
                && dtv[1 + cnt].pointer.val != TLS_DTV_UNALLOCATED)
            free (dtv[1 + cnt].pointer.val);
    memset (dtv, '\0', (dtv[-1].counter + 1) * sizeof (dtv_t));

    /* Re-initialize the TLS.  */
    _dl_allocate_tls_init (TLS_TPADJ (result));
}
{% endhighlight %}

`get_cached_stack`会把取出的`pthread`中的dtv重新初始化。**注意 `_dl_allocate_tls_init` 中是根据模块列表来初始化dtv数组的。**

### 实验

当一个线程退出后，它就可能被当做cache被`get_cached_stack`取出复用。

使用`g++ -o thread -g -Wall -lpthread -ldl thread.cpp -DTEST_CACHE_STACK`编译程序，运行：

    $ ./thread
    ..
    pthread 0x413c9940, dtv 0x1be46a0
    ... 
    pthread 0x413c9940, dtv 0x1be46a0


## 回顾BUG

当新创建的线程复用了之前退出的线程堆栈时，由于在`_dl_allocate_tls_init`中初始化dtv数组时是根据当前载入的模块数量而定。如果在这个时候模块数已经超过了这个复用的dtv数组大小，那么就会出现写入非法的内存。使用valgrind检测就会得到本文开头提到的结果。

由于dtv数组大小通常会稍微大点，所以在新加载的模块数量不够多时程序还不会有问题。可以通过控制测试程序中`SO_CNT`的大小看看dtv中内容的变化。

另外，我查看了下glibc的更新历史，到目前为止(2.20)这个BUG还没有修复。

## 参考文档

* [glibc Bug 13862 - Reuse of cached stack can cause bounds overrun of thread DTV](https://sourceware.org/bugzilla/show_bug.cgi?id=13862)
* [gLibc TLS实现](http://tsecer.blog.163.com/blog/static/1501817201172883556743/)
* [Linux线程之线程栈](http://blog.chinaunix.net/uid-24774106-id-3651266.html)
* [Linux用户空间线程管理介绍之二：创建线程堆栈](http://www.longene.org/forum/viewtopic.php?f=17&t=429)


