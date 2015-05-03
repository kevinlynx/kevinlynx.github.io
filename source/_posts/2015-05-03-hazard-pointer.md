---
layout: post
title: "并行编程中的内存回收Hazard Pointer"
category: c/c++
tags: hazard pointer
comments: true
---

接上篇[使用RCU技术实现读写线程无锁](http://codemacro.com/2015/04/19/rw_thread_gc/)，在没有GC机制的语言中，要实现Lock free的算法，就免不了要自己处理内存回收的问题。

Hazard Pointer是另一种处理这个问题的算法，而且相比起来不但简单，功能也很强大。[锁无关的数据结构与Hazard指针](http://blog.csdn.net/pongba/article/details/589864)中讲得很好，[Wikipedia Hazard pointer](http://en.wikipedia.org/wiki/Hazard_pointer)也描述得比较清楚，所以我这里就不讲那么细了。

一个简单的实现可以参考[我的github haz_ptr.c](https://github.com/kevinlynx/lockfree-list/blob/master/haz_ptr.c)

## 原理

基本原理无非也是读线程对指针进行标识，指针(指向的内存)要释放时都会缓存起来延迟到确认没有读线程了才对其真正释放。

`<Lock-Free Data Structures with Hazard Pointers>`中的描述：

> Each reader thread owns a single-writer/multi-reader shared pointer called "hazard pointer." When a reader thread assigns the address of a map to its hazard pointer, it is basically announcing to other threads (writers), "I am reading this map. You can replace it if you want, but don't change its contents and certainly keep your deleteing hands off it."

关键的结构包括：`Hazard pointer`、`Thread Free list`

`Hazard pointer`：一个读线程要使用一个指针时，就会创建一个Hazard pointer包装这个指针。一个Hazard pointer会被一个线程写，多个线程读。
<!-- more -->
{% highlight c++ %}
    struct HazardPointer {
        void *real_ptr; // 包装的指针
        ... // 不同的实现有不同的成员
    };

    void func() {
        HazardPointer *hp = accquire(_real_ptr);
        ... // use _real_ptr
        release(hp);
    }
{% endhighlight %}

`Thread Free List`：每个线程都有一个这样的列表，保存着将要释放的指针列表，这个列表仅对应的线程读写

{% highlight c++ %}
    void defer_free(void *ptr) {
        _free_list.push_back(ptr);
    }
{% endhighlight %}

当某个线程要尝试释放Free List中的指针时，例如指针`ptr`，就检查所有其他线程使用的Hazard pointer，检查是否存在包装了`ptr`的Hazard pointer，如果没有则说明没有读线程正在使用`ptr`，可以安全释放`ptr`。

{% highlight c++ %}
    void gc() {
        for(ptr in _free_list) {
            conflict = false
            for (hp in _all_hazard_pointers) {
                if (hp->_real_ptr == ptr) {
                    confilict = true
                    break
                }
            }
            if (!conflict)
                delete ptr
        }
    }
{% endhighlight %}

以上，其实就是`Hazard Pointer`的主要内容。

## Hazard Pointer的管理

上面的代码中没有提到`_all_hazard_pointers`及`accquire`的具体实现，这就是Hazard Pointer的管理问题。

《锁无关的数据结构与Hazard指针》文中创建了一个Lock free的链表来表示这个全局的Hazard Pointer List。每个Hazard Pointer有一个成员标识其是否可用。这个List中也就保存了已经被使用的Hazard Pointer集合和未被使用的Hazard Pointer集合，当所有Hazard Pointer都被使用时，就会新分配一个加进这个List。当读线程不使用指针时，需要归还Hazard Pointer，直接设置可用成员标识即可。要`gc()`时，就直接遍历这个List。

要实现一个Lock free的链表，并且仅需要实现头插入，还是非常简单的。本身Hazard Pointer标识某个指针时，都是用了后立即标识，所以这个实现直接支持了动态线程，支持线程的挂起等。

在[nbds](https://code.google.com/p/nbds/)项目中也有一个Hazard Pointer的实现，相对要弱一点。它为每个线程都设置了自己的Hazard Pointer池，写线程要释放指针时，就访问所有其他线程的Hazard Pointer池。

{% highlight c++ %}
    typedef struct haz_local {
        // Free List
        pending_t *pending; // to be freed
        int pending_size;
        int pending_count;

        // Hazard Pointer 池，动态和静态两种
        haz_t static_haz[STATIC_HAZ_PER_THREAD];

        haz_t **dynamic;
        int dynamic_size;
        int dynamic_count;

    } __attribute__ ((aligned(CACHE_LINE_SIZE))) haz_local_t;

    static haz_local_t haz_local_[MAX_NUM_THREADS] = {};
{% endhighlight %}

每个线程当然就涉及到`haz_local_`索引(ID)的分配，就像[使用RCU技术实现读写线程无锁](http://codemacro.com/2015/04/19/rw_thread_gc/)中的一样。这个实现为了支持线程动态创建，就需要一套线程ID的重用机制，相对复杂多了。

## 附录

最后，附上一些并行编程中的一些概念。

### Lock Free & Wait Free

常常看到`Lock Free`和`Wait Free`的概念，这些概念用于衡量一个系统或者说一段代码的并行级别，并行级别可参考[并行编程——并发级别](http://www.cnblogs.com/jiayy/p/3246167.html)。总之Wait Free是一个比Lock Free更牛逼的级别。

我自己的理解，例如《锁无关的数据结构与Hazard指针》中实现的Hazard Pointer链表就可以说是Lock Free的，注意它在插入新元素到链表头时，因为使用`CAS`，总免不了一个busy loop，有这个特征的情况下就算是`Lock Free`，虽然没锁，但某个线程的执行情况也受其他线程的影响。

相对而言，`Wait Free`则是每个线程的执行都是独立的，例如《锁无关的数据结构与Hazard指针》中的`Scan`函数。`“每个线程的执行时间都不依赖于其它任何线程的行为”`

> 锁无关(Lock-Free)意味着系统中总存在某个线程能够得以继续执行；而等待无关(Wait-Free)则是一个更强的条件，它意味着所有线程都能往下进行。

### ABA问题

在实现`Lock Free`算法的过程中，总是要使用`CAS`原语的，而`CAS`就会带来`ABA`问题。

> 在进行CAS操作的时候，因为在更改V之前，CAS主要询问“V的值是否仍然为A”，所以在第一次读取V之后以及对V执行CAS操作之前，如果将值从A改为B，然后再改回A，会使基于CAS的算法混乱。在这种情况下，CAS操作会成功。这类问题称为ABA问题。

[Wiki Hazard Pointer](http://en.wikipedia.org/wiki/Hazard_pointer)提到了一个ABA问题的好例子：在一个Lock free的栈实现中，现在要出栈，栈里的元素是`[A, B, C]`，`head`指向栈顶，那么就有`compare_and_swap(target=&head, newvalue=B, expected=A)`。但是在这个操作中，其他线程把`A` `B`都出栈，且删除了`B`，又把`A`压入栈中，即`[A, C]`。那么前一个线程的`compare_and_swap`能够成功，此时`head`指向了一个已经被删除的`B`。stackoverflow上也有个例子 [Real-world examples for ABA in multithreading](http://stackoverflow.com/questions/14535948/real-world-examples-for-aba-in-multithreading)

> 对于CAS产生的这个ABA问题，通常的解决方案是采用CAS的一个变种DCAS。DCAS，是对于每一个V增加一个引用的表示修改次数的标记符。对于每个V，如果引用修改了一次，这个计数器就加1。然后再这个变量需要update的时候，就同时检查变量的值和计数器的值。

但也早有人提出`DCAS`也不是[ABA problem 的银弹](http://people.csail.mit.edu/shanir/publications/DCAS.pdf)。


