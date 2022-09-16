---
layout: post
title: "Java GC总结"
category: java
tags: GC
comments: true
---

Java GC相关的文章有很多，本文只做概要性总结，主要内容来源于<深入理解Java虚拟机>。

## 对象存活性判定

对象存活性判定用于确定一个对象是死是活，死掉的对象则需要被垃圾回收。主要包括的方法：

* 引用计数
* 可达性分析

可达性分析的基本思想是：

> 通过一系列的称为"GC Roots"的对象作为起始点，从这些节点开始向下搜索，搜索所走过的路径称为引用链，当一个对象到GC Roots没有任何引用链项链时，则证明此对象是不可用的。

在Java中有很多种类的对象可以作为GC Roots，例如类静态属性引用的对象。

## 垃圾收集算法

确定了哪些对象是需要回收之后，就可以运用各种垃圾收集算法收集这些对象，例如直接回收内存，或者回收并移动整理内存。

主要包括：

* 标记清除(Mark-Sweep)算法：首先标记出需要回收的对象，然后统一回收被标记的对象
* 复制(Copying)算法：将可用内存分块，当一块内存用完后将存活对象复制到其他块，并统一回收不使用的块。Java中新生代对象一般使用该方法
* 标记整理(Mark-Compact)算法：基本同标记清除，不同的是回收时是把可用对象进行移动，以避免内存碎片问题
* 分代收集，将内存分区域，不同区域采用不同的算法，例如Java中的新生代及老年代
<!-- more -->
![](/assets/res/heap-structure.png)

如上，Java Hotspot虚拟机实现中将堆内存分为3大区域，即新生代、老年代、永久代。新生代中又分了eden、survivor0及survivor1，采用复制算法；老年代则采用标记清除及标记整理；永久代存放加载的类，类似于代码段，但同样会发生GC。

## 垃圾收集器

垃圾收集算法在实现时会略有不同，不同的实现称为垃圾收集器。不同的垃圾收集器适用的范围还不一样，有些收集器仅能用于新生代，有些用于老年代，有些新生代老年代都可以被使用。垃圾收集器可通过JVM启动参数指定。

![](/assets/res/hotspot-gc-collectors.png)

上图中展示了新生代（年轻代）和老年代可用的各种垃圾收集器，图中的连线表示两种收集器可以配合使用。

* Serial收集器，单线程收集，复制算法
* ParNew收集器，Serial收集器的多线程版本
* Parallel Scavenge收集器，复制算法，吞吐量优先的收集器，更高效率地利用CPU时间，适合用于服务器程序
* Serial Old收集器，单线程收集，标记整理算法
* Parallel Old收集器，标记整理算法，Parallel Scavenge收集器的老年代版本
* CMS(Concurrent Mark Sweep)收集器，标记清除算法，以获取最短停顿时间为目标的收集器
* G1收集器，较新的收集器实现

JVM有些参数组合了各种收集器，例如：

* `UseConcMarkSweepGC`：使用ParNew + CMS + Serial Old收集器
* `UseParallelGC`，运行在server模式下的默认值，使用Parallel Scavenge + Serial Old 收集器

## GC日志

生产服务器一般会配置GC日志，以在故障时能够分析问题所在，一般的应用可配置以下JVM参数：

    -XX:+UseParallelGC -XX:+DisableExplicitGC -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -Xloggc:./logs/gc.log 

输出日志类似：

    1456772.057: [GC [PSYoungGen: 33824K->96K(33920K)] 53841K->20113K(102208K), 0.0025050 secs] [Times: user=0.00 sys=0.00, real=0.00 secs]
    1456863.534: [GC [PSYoungGen: 33824K->96K(33920K)] 53841K->20113K(102208K), 0.0020050 secs] [Times: user=0.00 sys=0.00, real=0.00 secs]
    1456962.061: [GC [PSYoungGen: 33824K->128K(33920K)] 53841K->20145K(102208K), 0.0014150 secs] [Times: user=0.01 sys=0.00, real=0.00 secs]

* `1456772.057`，自JVM启动后的时间值
* `GC` 表示本次进行的是一次minor GC，即年轻代中的GC
* `PSYoungGen` 垃圾收集器类型，这里是Parallel Scavenge
* `33824K->96K(33920K)`，收集前后新生代大小，`33920K`为新生代总大小(eden+ 1 survivor)
* `53841K->20113K(102208K)`，堆总大小及GC前后大小
* `0.0025050 secs`，GC时停顿时间

## 常见策略

JVM GC相关的有一些策略值得注意：

* 对象优先在eden分配，当回收时（Eden区可用内存不够），将Eden和当前Survivor还存活着的对象一次性复制到另外一块Survivor，最后清理Eden和刚才用过的Survivor。这个过程称为一次MinorGC，每次MinorGC就会增加活着对象的年龄，当年龄超过某值(-XX:MaxTenuringThreashold)时，就会被转移到老年代(Tenured)。老年代发生GC时被称为FullGC
* 每一次发生MinorGC而存活下来的对象其年龄都会加1，较老的对象会进入老年代
* 当分配大对象(> PretenureSizeThreshold)时，其就会直接进入老年代
* 当年轻代(Eden+Survivor)不足以容纳存活对象时，这些对象会被全部放入老年代(分配担保机制)


