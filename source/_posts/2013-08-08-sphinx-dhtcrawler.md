---
layout: post
title: "dhtcrawler2换用sphinx搜索"
categories: [erlang, network]
tags: [erlang, dht, dhtcrawler, mongodb, sphinx]
comments: true
keywords: [erlang, dht, dhtcrawler, mongodb, sphinx]
description: 
---

dhtcrawler2最开始使用mongodb自带的全文搜索引擎搜索资源。搜索一些短关键字时很容易导致erlang进程call timeout，也就是查询时间太长。对于像`avi`这种关键字，搜索时间长达十几秒。搜索的资源数量200万左右。这其中大部分资源只是对root文件名进行了索引，即对于多文件资源而言没有索引单个文件名。索引方式有部分资源是按照字符串子串的形式，没有拆词，非常占用存储空间；有部分是使用了rmmseg（我编译了rmmseg-cpp作为erlang nif库调用 [erl-rmmseg](https://github.com/kevinlynx/erl-rmmseg)）进行了拆词，占用空间小了很多，但由于词库问题很多片里的词汇没拆出来。

很早以前我以为搜索耗时的原因是因为数据库太忙，想部署个mongodb集群出来。后来发现数据库没有任何读写的状态下，查询依然慢。终于只好放弃mongodb自带的文本搜索。于是我改用sphinx。简单起见，我直接下载了[coreseek4.1](http://www.coreseek.cn/)（sphinx的一个支持中文拆词的包装）。

现在，已经导入了200多万的资源进sphinx，并且索引了所有文件名，索引文件达800M。对于`avi`关键字的搜索大概消耗0.2秒的时间。[搜索试试](http://bt.cm/e/http_handler:search?q=avi)。

以下记录下sphinx在dhtcrawler的应用

### sphinx简介

sphinx包含两个主要的程序：indexer和searchd。indexer用于建立文本内容的索引，然后searchd基于这些索引提供文本搜索功能，而要使用该功能，可以遵循searchd的网络协议连接searchd这个服务来使用。

indexer可以通过多种方式来获取这些文本内容，文本内容的来源称为数据源。sphinx内置mysql这种数据源，意思是可以直接从mysql数据库中取得数据。sphinx还支持xmlpipe2这种数据源，其数据以xml格式提供给indexer。要导入mongodb数据库里的内容，可以选择使用xmlpipe2这种方式。
<!-- more -->
### sphinx document

xmlpipe2数据源需要按照以下格式提交：

    <sphinx:docset>
        <sphinx:schema>
            <sphinx:field name="subject"/>
            <sphinx:field name="files"/>
            <sphinx:attr name="hash1" type="int" bits="32"/>
            <sphinx:attr name="hash2" type="int" bits="32"/>
        </sphinx:schema>
        <sphinx:document id="1">
            <subject>this is the subject</subject>
            <files>file content</files>
            <hash1>111</hash1>
        </sphinx:document>
    </sphinx:docset>

该文件包含两大部分：`schema`和`documents`，其中`schema`又包含两部分：`field`和`attr`，其中由`field`标识的字段就会被indexer读取并全部作为输入文本建立索引，而`attr`则标识查询结果需要附带的信息；`documents`则是由一个个`sphinx:document`组成，即indexer真正要处理的数据。注意其中被`schema`引用的属性名。

document一个很重要的属性就是它的id。这个id对应于sphinx需要唯一，查询结果也会包含此id。一般情况下，此id可以直接是数据库主键，可用于查询到详细信息。searchd搜索关键字，其实可以看作为搜索这些document，搜索出来的结果也是这些document，搜索结果中主要包含schema中指定的attr。

### 增量索引

数据源的数据一般是变化的，新增的数据要加入到sphinx索引文件中，才能使得searchd搜索到新录入的数据。要不断地加入新数据，可以使用增量索引机制。增量索引机制中，需要一个主索引和一个次索引(delta index)。每次新增的数据都建立为次索引，然后一段时间后再合并进主索引。这个过程主要还是使用indexer和searchd程序。实际上，searchd是一个需要一直运行的服务，而indexer则是一个建立完索引就退出的工具程序。所以，这里的增量索引机制，其中涉及到的“每隔一定时间就合并”这种工作，需要自己写程序来协调（或通过其他工具）

### sphinx与mongodb

上面提到，一般sphinx document的id都是使用的数据库主键，以方便查询。但mongodb中默认情况不使用数字作为主键。dhtcrawler的资源数据库使用的是资源info-hash作为主键，这无法作为sphinx document的id。一种解决办法是，将该hash按位拆分，拆分成若干个sphinx document attr支持位数的整数。例如，info-hash是一个160位的id，如果使用32位的attr（高版本的sphinx支持64位的整数），那么可以把该info-hash按位拆分成5个attr。而sphinx document id则可以使用任意数字，只要保证不冲突就行。当获得查询结果时，取得对应的attr，组合为info-hash即可。

mongodb默认的Object id也可以按这种方式拆分。

### dhtcrawler2与sphinx

dhtcrawler2中我自己写了一个导入程序。该程序从mongodb中读出数据，数据到一定量时，就输出为xmlpipe2格式的xml文件，然后建立为次索引，最后合并进主索引。过程很简单，包含两次启动外部进程的工作，这个可以通过erlang中os:cmd完成。

值得注意的是，在从mongodb中读数据时，使用skip基本是不靠谱的，skip 100万个数据需要好几分钟，为了不增加额外的索引字段，我只好在`created_at`字段上加索引，然后按时间段来读取资源，这一切都是为了支持程序关闭重启后，可以继续上次工作，而不是重头再来。200万的数据，已经处理了好几天了。

后头数据建立好了，需要在前台展示出来。erlang中似乎只有一个sphinx客户端库：[giza](https://github.com/kevsmith/giza)。这个库有点老，写成的时候貌似还在使用sphinx0.9版本。其中查询代码包含了版本判定，已经无法在我使用的sphinx2.x版本中使用。无奈之下我只好修改了这个库的源码，幸运的是查询功能居然是正常的，意味着sphinx若干个版本了也没改动通信协议？后来，我为了取得查询的统计信息，例如消耗时间以及总结果，我再一次修改了giza的源码。新的版本可以在我的github上找到：[my giza](https://github.com/kevinlynx/giza)，看起来我没侵犯版本协议吧？

目前dhtcrawler的搜索，先是基于sphinx搜索出hash列表，然后再去mongodb中搜索hash对应的资源。事实上，可以为sphinx的document直接附加这些资源的描述信息，就可以避免去数据库查询。但我想，这样会增加sphinx索引文件的大小，担心会影响搜索速度。实际测试时，发现数据库查询有时候还真的很消耗时间，尽管我做了分页，以使得单页仅对数据库进行少量查询。

### xml unicode

在导入xml到sphinx的索引过程中，本身我输出的内容都是unicode的，但有很多资源会导致indexer解析xml出错。出错后indexer直接停止对当前xml的处理。后来查阅资料发现是因为这些无法被indexer处理的xml内容包含unicode里的控制字符，例如 ä (U+00E4)。我的解决办法是直接过滤掉这些控制字符。unicode的控制字符参看[UTF-8 encoding table and Unicode characters](http://www.utf8-chartable.de/)。在erlang中干这个事居然不复杂：

{% highlight erlang %}
strip_invalid_unicode(<<>>) ->
	<<>>;
strip_invalid_unicode(<<C/utf8, R/binary>>) ->
	case is_valid_unicode(C) of
		true ->
			RR = strip_invalid_unicode(R),
			<<C/utf8, RR/binary>>;
		false ->
			strip_invalid_unicode(R)
	end;
strip_invalid_unicode(<<_, R/binary>>) ->
	strip_invalid_unicode(R).
	
is_valid_unicode(C) when C < 16#20 ->
	false;
is_valid_unicode(C) when C >= 16#7f, C =< 16#ff ->
	false;
is_valid_unicode(_) ->
	true.
{% endhighlight %}

