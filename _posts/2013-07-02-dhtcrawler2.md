---
layout: post
title: "磁力搜索第二版-dhtcrawler2"
categories: [erlang, network]
tags: [erlang, dht, p2p, magnet, dhtcrawler]
comments: true
keywords: [erlang, dht, p2p, magnet, dhtcrawler]
description: 
---

接[上篇](http://codemacro.com/2013/06/21/magnet-search-impl/)。

## 下载使用

目前为止dhtcrawler2相对dhtcrawler而言，数据库部分调整很大，DHT部分基本沿用之前。但单纯作为一个爬资源的程序而言，DHT部分可以进行大幅削减，这个以后再说。这个版本更快、更稳定。为了方便，我将编译好的erlang二进制文件作为git的主分支，我还添加了一些Windows下的批处理脚本，总之基本上下载源码以后即可运行。

项目地址：[https://github.com/kevinlynx/dhtcrawler2](https://github.com/kevinlynx/dhtcrawler2)

### 使用方法

* 下载erlang，我测试的是R16B版本，确保erl等程序被加入`Path`环境变量
* 下载mongodb，解压即用：

        mongod --dbpath xxx --setParameter textSearchEnabled=true

* 下载dhtcrawler2

        git clone https://github.com/kevinlynx/dhtcrawler2.git

* 运行`win_start_crawler.bat`
* 运行`win_start_hash.bat`
* 运行`win_start_http.bat`
* 打开`localhost:8000`查看`stats`

爬虫每次运行都会保存DHT节点状态，早期运行的时候收集速度会不够。dhtcrawler2将程序分为3部分：

* crawler，即DHT爬虫部分，仅负责收集hash
* hash，准确来讲叫`hash reader`，处理爬虫收集的hash，处理过程主要涉及到下载种子文件
* http，使用hash处理出来的数据库，以作为Web端接口

我没有服务器，但程序有被部署在别人的服务器上：[bt.cm](http://bt.cm)，[http://222.175.114.126:8000/](http://222.175.114.126:8000/)。
<!-- more -->
### 其他工具

为了提高资源索引速度，我陆续写了一些工具，包括：

* import_tors，用于导入本地种子文件到数据库
* tor_cache，用于下载种子到本地，仅仅提供下载的功能，hash_reader在需要种子文件时，可以先从本地取
* cache_indexer，目前hash_reader取种子都是从torrage.com之类的种子缓存站点取，这些站点提供了种子列表，cache_indexer将这些列表导入数据库，hash_reader在请求种子文件前可以通过该数据库检查torrage.com上有无此种子，从而减少多余的http请求

这些工具的代码都被放在dhtcrawler2中，可以查看对应的启动脚本来查看具体如何启动。

### OS/Database

根据实际的测试效果来看，当收集的资源量过百万时（目前bt.cm录入近160万资源），4G内存的Windows平台，mongodb很容易就会挂掉。挂掉的原因全是1455，页面文件太小。有人建议不要在Windows下使用mongodb，Linux下我自己没做过测试。

mongodb可以部署为集群形式(replica-set)，当初我想把http部分的查询放在一个只读的mongodb实例上，但因为建立集群时，要同步已有的10G数据库，而每次同步都以mongodb挂掉结束，遂放弃。在目前bt.cm的配置中，数据库torrent的锁比例（db lock）很容易上50%，这也让http在搜索时，经常出现搜索超时的情况。

## 技术信息

dhtcrawler最早的版本有很多问题，修复过的最大的一个问题是关于erlang定时器的，在DHT实现中，需要对每个节点每个peer做超时处理，在erlang中的做法直接是针对每个节点注册了一个定时器。这不是问题，问题在于定时器资源就像没有GC的内存资源一样，是会由于程序员的代码问题而出现资源泄漏。所以，dhtcrawler第一个版本在节点数配置在100以上的情况下，用不了多久就会内存耗尽，最终导致erlang虚拟机core dump。

除了这个问题以外，dhtcrawler的资源收录速度也不是很快。这当然跟数据库和获取种子的速度有直接关系。尤其是获取种子，使用的是一些提供info-hash到种子映射的网站，通过HTTP请求来下载种子文件。我以为通过BT协议直接下载种子会快些，并且实时性也要高很多，因为这个种子可能未被这些缓存网站收录，但却可以直接向对方请求得到。为此，我还特地翻阅了相关[协议](http://www.bittorrent.org/beps/bep_0009.html)，并且用erlang实现了（以后的文章我会讲到具体实现这个协议）。

后来我怀疑get_peers的数量会不会比announce_peer多，但是理论上一般的客户端在get_peers之后都是announce_peer，但是如果get_peers查询的peers恰好不在线呢？这意味着很多资源虽然已经存在，只不过你恰好暂时请求不到。实际测试时，发现get_peers基本是announce_peer数量的10倍。

将hash的获取方式做了调整后，dhtcrawler在几分钟以内以几乎每秒上百个新增种子的速度工作。然后，程序挂掉。

从dhtcrawler到今天为止的dhtcrawler2，中间间隔了刚好1个月。我的所有业余时间全部扑在这个项目上，面临的问题一直都是程序的内存泄漏、资源收录的速度不够快，到后来又变为数据库压力过大。每一天我都以为我将会完成一个稳定版本，然后终于可以去干点别的事情，但总是干不完，目前完没完都还在观察。我始终明白在做优化前需要进行详尽的数据收集和分析，从而真正地优化到正确的点上，但也总是凭直觉和少量数据分析就开始尝试。

这里谈谈遇到的一些问题。

### erlang call timeout

最开始遇到erlang中`gen_server:call`出现`timeout`错误时，我还一直以为是进程死锁了。相关代码读来读去，实在觉得不可能发生死锁。后来发现，当erlang虚拟机压力上去后，例如内存太大，但没大到耗尽系统所有内存（耗进所有内存基本就core dump了），进程间的调用就会出现timeout。

当然，内存占用过大可能只是表象。其进程过多，进程消息队列太长，也许才是导致出现timeout的根本原因。消息队列过长，也可能是由于发生了*消息泄漏*的缘故。消息泄漏我指的是这样一种情况，进程自己给自己发消息（当然是cast或info），这个消息被处理时又会发送相同的消息，正常情况下，gen_server处理了一个该消息，就会从消息队列里移除它，然后再发送相同的消息，这不会出问题。但是当程序逻辑出问题，每次处理该消息时，都会发生多余一个的同类消息，那消息队列自然就会一直增长。

保持进程逻辑简单，以避免这种逻辑错误。

### erlang gb_trees

我在不少的地方使用了gb_trees，dht_crawler里就可能出现`gb_trees:get(xxx, nil)`这种错误。乍一看，我以为我真的传入了一个`nil`值进去。然后我苦看代码，以为在某个地方我会把这个gb_trees对象改成了nil。但事情不是这样的，gb_tress使用一个tuple作为tree的节点，当某个节点没有子节点时，就会以nil表示。

`gb_trees:get(xxx, nil)`类似的错误，实际指的是`xxx`没有在这个gb_trees中找到。

### erlang httpc

dht_crawler通过http协议从torrage.com之类的缓存网站下载种子。最开始我为了尽量少依赖第三方库，使用的是erlang自带的httpc。后来发现程序有内存泄漏，google发现erlang自带的httpc早为人诟病，当然也有大神说在某个版本之后这个httpc已经很不错。为了省事，我直接换了ibrowse，替换之后正常很多。但是由于没有具体分析测试过，加之时间有点远了，我也记不太清细节。因为早期的http请求部分，没有做数量限制，也可能是由于我的使用导致的问题。

某个版本后，我才将http部分严格地与hash处理部分区分开来。相较数据库操作而言，http请求部分慢了若干数量级。在hash_reader中将这两块分开，严格限制了提交给httpc的请求数，以获得稳定性。

对于一个复杂的网络系统而言，分清哪些是耗时的哪些是不大耗时的，才可能获得性能的提升。对于hash_reader而言，处理一个hash的速度，虽然很大程度取决于数据库，但相较http请求，已经快很多。它在处理这些hash时，会将数据库已收录的资源和待下载的资源分离开，以尽快的速度处理已存在的，而将待下载的处理速度交给httpc的响应速度。

### erlang httpc ssl

ibrowse处理https请求时，默认和erlang自带的httpc使用相同的SSL实现。这经常导致出现`tls_connection`进程挂掉的错误，具体原因不明。

### erlang调试

首先合理的日志是任何系统调试的必备。

我面临的大部分问题都是内存泄漏相关，所以依赖的erlang工具也是和内存相关的：

* 使用`etop`，可以检查内存占用多的进程、消息队列大的进程、CPU消耗多的进程等等：

		spawn(fun() -> etop:start([{output, text}, {interval, 10}, {lines, 20}, {sort, msg_q }]) end).

* 使用`erlang:system_info(allocated_areas).`检查内存使用情况，其中会输出系统`timer`数量
* 使用`erlang:process_info`查看某个具体的进程，这个甚至会输出消息队列里的消息

### hash_writer/crawler

crawler本身仅收集hash，然后写入数据库，所以可以称crawler为hash_writer。这些hash里存在大量的重复。hash_reader从数据库里取出这些hash然后做处理。处理过程会首先判定该hash对应的资源是否被收录，没有收录就先通过http获取种子。

在某个版本之后，crawler会简单地预先处理这些hash。它缓存一定数量的hash，接收到新hash时，就合并到hash缓存里，以保证缓存里没有重复的hash。这个重复率经过实际数据分析，大概是50%左右，即收到的100个请求里，有50个是重复的。这样的优化，不仅会降低hash数据库的压力，hash_reader处理的hash数量少了，也会对torrent数据库有很大提升。

当然进一步的方案可以将crawler和hash_reader之间交互的这些hash直接放在内存中处理，省去中间数据库。但是由于mongodb大量使用虚拟内存的缘故（内存映射文件），经常导致服务器内存不够（4G），内存也就成了珍稀资源。当然这个方案还有个弊端是难以权衡hash缓存的管理。crawler收到hash是一个不稳定的过程，在某些时间点这些hash可能爆多，而hash_reader处理hash的速度也会不太稳定，受限于收到的hash类别（是新增资源还是已存在资源）、种子请求速度、是否有效等。

当然，也可以限制缓存大小，以及对hash_reader/crawler处理速度建立关系来解决这些问题。但另一方面，这里的优化是否对目前的系统有提升，是否是目前系统面临的最大问题，却是需要考究的事情。

### cache indexer

dht_crawler是从torrage.com等网站获取种子文件，这些网站看起来都是使用了相同的接口，其都有一个sync目录，里面存放了每天每个月索引的种子hash，例如 http://torrage.com/sync/。这个网站上是否有某个hash对应的种子，就可以从这些索引中检查。

hash_reader在处理新资源时，请求种子的过程中发现大部分在这些服务器上都没有找到，也就是发起的很多http请求都是404回应，这不但降低了系统的处理能力、带宽，也降低了索引速度。所以我写了一个工具，先手工将sync目录下的所有文件下载到本地，然后通过这个工具 (cache indexer) 将这些索引文件里的hash全部导入数据库。在以后的运行过程中，该工具仅下载当天的索引文件，以更新数据库。 hash_reader 根据配置，会首先检查某个hash是否存在该数据库中，存在的hash才可能在torrage.com上下载得到。

### 种子缓存

hash_reader可以通过配置，将下载得到的种子保存在本地文件系统或数据库中。这可以建立自己的种子缓存，但保存在数据库中会对数据库造成压力，尤其在当前测试服务器硬件环境下；而保存为本地文件，又特别占用硬盘空间。

### 基于BT协议的种子下载

通过http从种子缓存里取种子文件，可能会没有直接从P2P网络里取更实时。目前还没来得及查看这些种子缓存网站的实现原理。但是通过BT协议获取种子会有点麻烦，因为dht_crawler是根据`get_peer`请求索引资源的，所以如果要通过BT协议取种子，那么这里还得去DHT网络里查询该种子，这个查询过程可能会较长，相比之下会没有http下载快。而如果通过`announce_peer`来索引新资源的话，其索引速度会大大降低，因为`announce_peer`请求比`get_peer`请求少很多，几乎10倍。

所以，这里的方案可能会结合两者，新开一个服务，建立自己的种子缓存。

### 中文分词

mongodb的全文索引是不支持中文的。我在之前提到，为了支持搜索中文，我将字符串拆成了若干子串。这样的后果就是字符串索引会稍稍偏大，而且目前这一块的代码还特别简单，会将很多非文字字符也算在内。后来我加了个中文分词库，使用的是rmmseg-cpp。我将其C++部分抽离出来编译成erlang nif，这可以在我的github上找到。

但是这个库拆分中文句子依赖于词库，而这个词库不太新，dhtcrawler爬到的大部分资源类型你们也懂，那些词汇拆出来的比率不太高，这会导致搜索出来的结果没你想的那么直白。当然更新词库应该是可以解决这个问题的，目前还没有时间顾这一块。

## 总结

一个老外对我说过，"i have 2 children to feed, so i will not do this only for fun"。

你的大部分编程知识来源于网络，所以稍稍回馈一下不会让你丢了饭碗。

我很穷，如果你能让我收获金钱和编程成就，还不会嫌我穿得太邋遢，that's really kind of you。


