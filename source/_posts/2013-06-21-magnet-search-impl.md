---
layout: post
title: "使用erlang实现P2P磁力搜索-实现"
categories: [erlang, network]
tags: [erlang, dht, p2p, magnet]
comments: true
keywords: [erlang, dht, p2p, magnet]
description: 
---

接[上篇](http://codemacro.com/2013/06/20/magnet-search/)，本篇谈谈一些实现细节。

这个爬虫程序主要的问题在于如何获取P2P网络中分享的资源，获取到资源后索引到数据库中，搜索就是自然而然的事情。

## DHT 

DHT网络本质上是一个用于查询的网络，其用于查询一个资源有哪些计算机正在下载。每个资源都有一个20字节长度的ID用于标示，称为infohash。当一个程序作为DHT节点加入这个网络时，就会有其他节点来向你查询，当你做出回应后，对方就会记录下你。对方还会询问其他节点，当对方开始下载这个infohash对应的资源时，他就会告诉所有曾经询问过的节点，包括你。这个时候就可以确定，这个infohash对应的资源在这个网络中是有效的。

关于这个网络的工作原理，参看：[P2P中DHT网络爬虫](http://codemacro.com/2013/05/19/crawl-dht/)以及[写了个磁力搜索的网页](http://xiaoxia.org/2013/05/11/magnet-search-engine/)。

获取到infohash后能做什么？关键点在于，我们现在使用的磁力链接(magnet url)，是和infohash对应起来的。也就是拿到infohash，就等于拿到一个磁力链接。但是这个爬虫还需要建立资源的信息，这些信息来源于种子文件。种子文件其实也是对应到一个资源，种子文件包含资源名、描述、文件列表、文件大小等信息。获取到infohash时，其实也获取到了对应的计算机地址，我们可以在这些计算机上下载到对应的种子文件。
<!-- more -->
但是我为了简单，在获取到infohash后，从一些提供映射磁力链到种子文件服务的网站上直接下载了对应的种子。dhtcrawler里使用了以下网站：

	http://torrage.com
	https://zoink.it
	http://bt.box.n0808.com

使用这些网站时，需提供磁力哈希（infohash可直接转换），构建特定的URL，发出HTTP请求即可。

{% highlight erlang %}
	U1 = "http://torrage.com/torrent/" ++ MagHash ++ ".torrent",
	U2 = "https://zoink.it/torrent/" ++ MagHash ++ ".torrent",
	U3 = format_btbox_url(MagHash),

format_btbox_url(MagHash) ->
	H = lists:sublist(MagHash, 2),
	T = lists:nthtail(38, MagHash),
	"http://bt.box.n0808.com/" ++ H ++ "/" ++ T ++ "/" ++ MagHash ++ ".torrent".
{% endhighlight %}

但是，以一个节点的身份加入DHT网络，是无法获取大量查询的。在DHT网络中，每个节点都有一个ID。每个节点在查询信息时，仅询问离信息较近的节点。这里的信息除了infohash外还包含节点，即节点询问一个节点，这个节点在哪里。DHT的典型实现中（Kademlia），使用两个ID的xor操作来确定距离。既然距离的计算是基于ID的，为了尽可能获取整个DHT网络交换的信息，爬虫程序就可以建立尽可能多的DHT节点，让这些节点的ID均匀地分布在ID取值区间内，以这样的方式加入网络。

在dhtcrawler中，我使用以下方式产生了N个大致均匀分布的ID：

{% highlight erlang %}
create_discrete_ids(1) ->
	[dht_id:random()];
create_discrete_ids(Count) ->
	Max = dht_id:max(),
	Piece = Max div Count,
	[random:uniform(Piece) + Index * Piece || Index <- lists:seq(0, Count - 1)].
{% endhighlight %}

除了尽可能多地往DHT网络里部署节点之外，对单个节点而言，也有些注意事项。例如应尽可能快地将自己告诉尽可能多的节点，这可以在启动时进行大量的随机infohash的查询。随着查询过程的深入，该节点会与更多的节点打交道。因为DHT网络里的节点实际上是不稳定的，它今天在线，明天后天可能不在线，所以计算你的ID固定，哪些节点与你较近，本身就是个相对概念。节点在程序退出时，也最好将自己的路由信息（与自己交互的节点列表）保存起来，这样下次启动时就可以更快地加入网络。

在dhtcrawler的实现中，每个节点每个一定时间，都会向网络中随机查询一个infohash，这个infohash是随机产生的。其查询目的不在于infohash，而在于告诉更多的节点，以及在其他节点上保持自己的活跃。

{% highlight erlang %}
handle_event(startup, {MyID}) ->
	timer:apply_interval(?QUERY_INTERVAL, ?MODULE, start_tell_more_nodes, [MyID]).

start_tell_more_nodes(MyID) ->
	spawn(?MODULE, tell_more_nodes, [MyID]).

tell_more_nodes(MyID) ->
	[search:get_peers(MyID, dht_id:random()) || _ <- lists:seq(1, 3)].
{% endhighlight %}

DHT节点的完整实现是比较繁琐的，涉及到查询以及繁杂的各种对象的超时（节点、桶、infohash），而超时的处理并不是粗暴地做删除操作。因为本身是基于UDP协议，你得对这些超时对象做进一步的查询才能正确地进一步做其他事情。而搜索也是个繁杂的事情，递归地查询节点，感觉上，你不一定离目标越来越近，由于被查询节点的不确定性（无法确定对方是否在玩弄你，或者本身对方就是个傻逼），你很可能接下来要查询的节点反而离目标变远了。

在我第一次的DHT实现中，我使用了类似transmission里DHT实现的方法，不断无脑递归，当搜索有太久时间没得到响应后终止搜索。第二次实现时，我就使用了etorrent里的实现。这个搜索更聪明，它记录搜索过的节点，并且检查是否离目标越来越远。当远离目标时，就认为搜索是不太有效的，不太有效的搜索尝试几次就可以放弃。

实际上，爬虫的实现并不需要完整地实现DHT节点的正常功能。**爬虫作为一个DHT节点的唯一动机仅是获取网络里其他节点的查询**。而要完成这个功能，你只需要装得像个正常人就行。这里不需要保存infohash对应的peer列表，面临每一次查询，你随便回复几个节点地址就可以。但是这里有个责任问题，如果整个DHT网络有2000个节点，而你这个爬虫就有1000个节点，那么你的随意回复，就可能导致对方根本找不到正确的信息，这样你依然得不到有效的资源。（可以利用这一点破坏DHT网络）

DHT的实现没有使用第三方库。

## 种子

种子文件的格式同DHT网络消息格式一样，使用一种称为bencode的文本格式来编码。种子文件分为两类：单个文件和多个文件。

文件的信息无非就是文件名、大小。文件名可能包含utf8编码的名字，为了后面处理的方便，dhtcrawler都会优先使用utf8编码。

{% highlight erlang %}
	{ok, {dict, Info}} = dict:find(<<"info">>, TD),
	case type(Info) of
		single -> {single, parse_single(Info)};
		multi -> {multi, parse_multi(Info)}
	end.
parse_single(Info) ->
	Name = read_string("name", Info),
	{ok, Length} = dict:find(<<"length">>, Info),
	{Name, Length}.

parse_multi(Info) ->
	Root = read_string("name", Info),
	{ok, {list, Files}} = dict:find(<<"files">>, Info),
	FileInfo = [parse_file_item(Item) || {dict, Item} <- Files],
	{Root, FileInfo}.
{% endhighlight %}

## 数据库

我最开始在选用数据库时，为了不使用第三方库，打算使用erlang自带的mnesia。但是因为涉及到字符串匹配搜索，mnesia的查询语句在我看来太不友好，在经过一些资料查阅后就直接放弃了。

然后我打算使用couchdb，因为它是erlang写的，而我正在用erlang写程序。第一次接触非关系型数据库，发现NoSQL数据库使用起来比SQL类的简单多了。但是在erlang里要使用couchdb实在太折腾了。我使用的客户端库是couchbeam。

因为couchdb暴露的API都是基于HTTP协议的，其数据格式使用了json，所以couchbeam实际上就是对各种HTTP请求、回应和json的包装。但是它竟然使用了ibrowse这个第三方HTTP客户端库，而不是erlang自带的。ibrowse又使用了jiffy这个解析json的库。这个库更惨烈的是它的解析工作都是交给C语言写的动态库来完成，我还得编译那个C库。

couchdb看起来不支持字符串查询，我得自己创建一个view，这个view里我通过翻阅了一些资料写了一个将每个doc的name拆分成若干次查询结果的map。这个map在处理每一次查询时，我都得动态更新之。couchdb是不支持局部更新的，这还不算大问题。然后很高兴，终于支持字符串查询了。这里的字符串查询都是基于字符串的子串查询。但是问题在于，太慢了。每一次在WEB端的查询，都直接导致erlang进程的call超时。

要让couchdb支持字符串查询，要快速，当然是有解决方案的。但是这个时候我已经没有心思继续折腾，任何一个库、程序如果接口设计得如此不方便，那就可以考虑换一个其他的。

我选择了mongodb。同样的基于文档的数据库。2.4版本还支持全文搜索。什么是全文搜索呢，这是一种基于单词的全文搜索方式。`hello world`我可以搜索`hello`，基于单词。mongodb会自动拆词。更关键更让人爽的是，要开启这个功能非常简单：设置启动参数、建立索引。没了。mongodb的erlang客户端库mongodb-erlang也只依赖一个bson-erlang库。然后我又埋头苦干，几个小时候我的这个爬虫程序就可以在浏览器端搜索关键字了。

后来我发现，mongodb的全文搜索是不支持中文的。因为它还不知道中文该怎么拆词。恰好我有个同事做过中文拆词的研究，看起来涉及到很复杂的算法。直到这个时候，我他妈才醒悟，我为什么需要基于单词的搜索。我们大部分的搜索其实都是基于子字符串的搜索。

于是，我将种子文件的名字拆分成了若干个子字符串，将这些子字符串以数组的形式作为种子文档的一个键值存储，而我依然还可以使用全文索引，因为全文索引会将整个字符串作为单词比较。实际上，基于一般的查询方式也是可以的。当然，索引还是得建立。

使用mongodb时唯一让我很不爽的是mongodb-erlang这个客户端库的文档太欠缺。这还不算大问题，因为看看源码参数还是可以大概猜到用法。真正悲剧的是mongodb的有些查询功能它是不支持的。例如通过cursor来排序来限制数量。在cursor模块并没有对应的mongodb接口。最终我只好通过以下方式查询，我不明白batchsize，但它可以工作：

{% highlight erlang %}
search_announce_top(Conn, Count) ->
	Sel = {'$query', {}, '$orderby', {announce, -1}},
	List = mongo_do(Conn, fun() ->
		Cursor = mongo:find(?COLLNAME, Sel, [], 0, Count), 
		mongo_cursor:rest(Cursor)
	end),
	[decode_torrent_item(Item) || Item <- List].
{% endhighlight %}

另一个悲剧的是，mongodb-erlang还不支持文档的局部更新，它的update接口直接要求传入整个文档。几经折腾，我可以通过runCommand来完成：

{% highlight erlang %}
inc_announce(Conn, Hash) when is_list(Hash) ->
	Cmd = {findAndModify, ?COLLNAME, query, {'_id', list_to_binary(Hash)}, 
		update, {'$inc', {announce, 1}},
		new, true},
	Ret = mongo_do(Conn, fun() ->
		mongo:command(Cmd)
	end).
{% endhighlight %}

## Unicode

不知道在哪里我看到过erlang说自己其实是不需要支持unicode的，因为这门语言本身是通过list来模拟字符串。对于unicode而言，对应的list保存的本身就是整数值。但是为了方便处理，erlang还是提供了一些unicode操作的接口。

因为我需要将种子的名字按字拆分，对于`a中文`这样的字符串而言，我需要拆分成以下结果：

	a
	a中
	a中文
	中
	中文
	文

那么，在erlang中当我获取到一个字符串list时，我就需要知道哪几个整数合起来实际上对应着一个汉字。erlang里unicode模块里有几个函数可以将unicode字符串list对应的整数合起来，例如：`[111, 222, 333]`可能表示的是一个汉字，将其转换以下可得到`[111222333]`这样的形式。

{% highlight erlang %}
split(Str) when is_list(Str) ->
	B = list_to_binary(Str), % 必须转换为binary
	case unicode:characters_to_list(B) of
		{error, L, D} ->
			{error, L, D};
		{incomplete, L, D} ->
			{incomplete, L, D};
		UL ->
		{ok, subsplit(UL)}
	end.

subsplit([]) ->
	[];

subsplit(L) ->
	[_|R] = L,
	{PreL, _} = lists:splitwith(fun(Ch) -> not is_spliter(Ch) end, L),
	[unicode:characters_to_binary(lists:sublist(PreL, Len)) 
		|| Len <- lists:seq(1, length(PreL))] ++ subsplit(R).
{% endhighlight %}

除了这里的拆字之外，URL的编码、数据库的存储都还好，没遇到问题。

**注意**，以上针对数据库本身的吐槽，完全基于我不熟悉该数据库的情况下，不建议作为你工具选择的参考。

## erlang的稳定性

都说可以用erlang来编写高容错的服务器程序。看看它的supervisor，监视子进程，自动重启子进程。天生的容错功能，就算你宕个几次，单个进程自动重启，整个程序看起来还稳健地在运行，多牛逼啊。再看看erlang的进程，轻量级的语言特性，就像OOP语言里的一个对象一样轻量。如果说使用OOP语言写程序得think in object，那用erlang你就得think in process，多牛逼多骇人啊。

实际上，以我的经验来看，你还得以传统的思维去看待erlang的进程。一些多线程程序里的问题，在erlang的进程环境中依然存在，例如死锁。

在erlang中，对于一些异步操作，你可以通过进程间的交互将这个操作包装成同步接口，例如ping的实现，可以等到对方回应之后再返回。被阻塞的进程反正很轻量，其包含的逻辑很单一。这不但是一种良好的包装，甚至可以说是一种erlang-style。但这很容易带来死锁。在最开始的时候我没有注意这个问题，当爬虫节点数上升的时候，网络数据复杂的时候，似乎就出现了死锁型宕机（进程互相等待太久，直接timeout）。

另一个容易在多进程环境下出现的问题就是消息依赖的上下文改变问题。当投递一个消息到某个进程，到这个消息被处理之前，这段时间这个消息关联的逻辑运算所依赖的上下文环境改变了，例如某个ets元素不见了，在处理这个消息时，你还得以多线程编程的思维来编写代码。

至于supervisor，这玩意你得端正态度。它不是用来包容你的傻逼错误的。当你写下傻逼代码导致进程频繁崩溃的时候，supervisor屁用没有。supervisor的唯一作用，仅仅是在一个确实本身可靠的系统，确实人品问题万分之一崩溃了，重启它。毕竟，一个重启频率的推荐值，是一个小时4次。

