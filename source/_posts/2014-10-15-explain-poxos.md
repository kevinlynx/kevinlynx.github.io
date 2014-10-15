---
layout: post
title: "图解分布式一致性协议Paxos"
category: network
tags: [paxos]
comments: true
---

Paxos协议/算法是分布式系统中比较重要的协议，它有多重要呢？

[<分布式系统的事务处理>](http://coolshell.cn/articles/10910.html)：

> Google Chubby的作者Mike Burrows说过这个世界上只有一种一致性算法，那就是Paxos，其它的算法都是残次品。

[<大规模分布式存储系统>](http://book.douban.com/subject/25723658/)：

> 理解了这两个分布式协议之后(Paxos/2PC)，学习其他分布式协议会变得相当容易。

学习Paxos算法有两部分：a) 算法的原理/证明；b) 算法的理解/运作。

理解这个算法的运作过程其实基本就可以用于工程实践。而且理解这个过程相对来说也容易得多。

网上我觉得讲Paxos讲的好的属于这篇：[paxos图解](http://coderxy.com/archives/121)及[Paxos算法详解](http://coderxy.com/archives/136)，我这里就结合[wiki上的实例](http://zh.wikipedia.org/zh-cn/Paxos%E7%AE%97%E6%B3%95#.E5.AE.9E.E4.BE.8B)进一步阐述。一些paxos基础通过这里提到的两篇文章，以及wiki上的内容基本可以理解。
<!-- more -->
## 算法内容

Paxos在原作者的《Paxos Made Simple》中内容是比较精简的：

> Phase  1

>   (a) A proposer selects a proposal number n  and sends a prepare request with number  n to a majority of acceptors.

>   (b)  If  an  acceptor  receives  a prepare  request  with  number  n  greater than  that  of  any  prepare  request  to  which  it  has  already  responded, then it responds to the request with a promise not to accept any more proposals numbered less than  n  and with the highest-numbered pro-posal (if any) that it has accepted.

>   Phase  2

>   (a)  If  the  proposer  receives  a  response  to  its  prepare requests (numbered  n)  from  a  majority  of  acceptors,  then  it  sends  an  accept request to each of those acceptors for a proposal numbered  n  with a value v , where v is the value of the highest-numbered proposal among the responses, or is any value if the responses reported no proposals.

>   (b) If an acceptor receives an accept request for a proposal numbered n, it accepts the proposal unless it has already responded to a prepare request having a number greater than  n.

借用[paxos图解](http://coderxy.com/archives/121)文中的流程图可概括为：

![](/assets/res/paxos/paxos-flow.png)

## 实例及详解

Paxos中有三类角色`Proposer`、`Acceptor`及`Learner`，主要交互过程在`Proposer`和`Acceptor`之间。

`Proposer`与`Acceptor`之间的交互主要有4类消息通信，如下图：

![](/assets/res/paxos/paxos-messages.png)

这4类消息对应于paxos算法的两个阶段4个过程：

* phase 1 
    * a) proposer向网络内超过半数的acceptor发送prepare消息
    * b) acceptor正常情况下回复promise消息
* phase 2
    * a) 在有足够多acceptor回复promise消息时，proposer发送accept消息
    * b) 正常情况下acceptor回复accepted消息

因为在整个过程中可能有其他proposer针对同一件事情发出以上请求，所以在每个过程中都会有些特殊情况处理，这也是为了达成一致性所做的事情。如果在整个过程中没有其他proposer来竞争，那么这个操作的结果就是确定无异议的。但是如果有其他proposer的话，情况就不一样了。

以[paxos中文wiki上的例子](http://zh.wikipedia.org/zh-cn/Paxos%E7%AE%97%E6%B3%95#.E5.AE.9E.E4.BE.8B)为例。简单来说该例子以若干个议员提议税收，确定最终通过的法案税收比例。

以下图中基本只画出proposer与一个acceptor的交互。时间标志T2总是在T1后面。propose number简称N。

情况之一如下图：

![](/assets/res/paxos/paxos-e1.png)

A3在T1发出accepted给A1，然后在T2收到A5的prepare，在T3的时候A1才通知A5最终结果(税率10%)。这里会有两种情况：

* A5发来的N5小于A1发出去的N1，那么A3直接拒绝(reject)A5
* A5发来的N5大于A1发出去的N1，那么A3回复promise，但带上A1的(N1, 10%)

这里可以与paxos流程图对应起来，更好理解。**acceptor会记录(MaxN, AcceptN, AcceptV)**。

A5在收到promise后，后续的流程可以顺利进行。但是发出accept时，因为收到了(AcceptN, AcceptV)，所以会取最大的AcceptN对应的AcceptV，例子中也就是A1的10%作为AcceptV。如果在收到promise时没有发现有其他已记录的AcceptV，则其值可以由自己决定。

针对以上A1和A5冲突的情况，最终A1和A5都会广播接受的值为10%。

其实4个过程中对于acceptor而言，在回复promise和accepted时由于都可能因为其他proposer的介入而导致特殊处理。所以基本上看在这两个时间点收到其他proposer的请求时就可以了解整个算法了。例如在回复promise时则可能因为proposer发来的N不够大而reject：

![](/assets/res/paxos/paxos-e2.png)

如果在发accepted消息时，对其他更大N的proposer发出过promise，那么也会reject该proposer发出的accept，如图：

![](/assets/res/paxos/paxos-e3.png)

这个对应于Phase 2 b)：

> it accepts the proposal unless it has already responded to a prepare request having a number greater than  n.

## 总结

Leslie Lamport没有用数学描述Paxos，但是他用英文阐述得很清晰。将Paxos的两个Phase的内容理解清楚，整个算法过程还是不复杂的。

至于Paxos中一直提到的一个全局唯一且递增的proposer number，其如何实现，引用如下：

> 如何产生唯一的编号呢？在《Paxos made simple》中提到的是让所有的Proposer都从不相交的数据集合中进行选择，例如系统有5个Proposer，则可为每一个Proposer分配一个标识j(0~4)，则每一个proposer每次提出决议的编号可以为5*i + j(i可以用来表示提出议案的次数)

## 参考文档

* paxos图解, http://coderxy.com/archives/121
* Paxos算法详解, http://coderxy.com/archives/136
* Paxos算法 wiki, http://zh.wikipedia.org/zh-cn/Paxos%E7%AE%97%E6%B3%95#.E5.AE.9E.E4.BE.8B


