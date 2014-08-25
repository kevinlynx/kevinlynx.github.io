---
layout: post
title: "使用erlang实现P2P磁力搜索(开源)"
categories: [erlang, network]
tags: [erlang, dht, p2p, magnet]
comments: true
keywords: [erlang, dht, p2p, magnet]
description: 
---

接上回对[DHT网络的研究](http://codemacro.com/2013/05/19/crawl-dht/)，我用erlang克隆了一个[磁力搜索引擎](http://bt.shousibaocai.com/)。我这个实现包含了完整的功能，DHT网络的加入、infohash的接收、种子的获取、资源信息的索引、搜索。

如下图：

![screenshot](https://raw.github.com/kevinlynx/dhtcrawler/master/screenshot.png)
<!-- more -->
在我的笔记本上，我开启了100个DHT节点，大致均匀地分布在DHT网络里，资源索引速度大概在1小时一万个左右（包含重复资源）。

这个程序包含三大部分：

* DHT实现，kdht，[https://github.com/kevinlynx/kdht](https://github.com/kevinlynx/kdht)
* 基于该DHT实现的搜索引擎，dhtcrawler，[https://github.com/kevinlynx/dhtcrawler](https://github.com/kevinlynx/dhtcrawler)，该项目包含爬虫部分和一个简单的WEB端

这两个项目总共包含大概2500行的erlang代码。其中，DHT实现部分将DHT网络的加入包装成一个库，爬虫部分在搜索种子时，暂时没有使用P2P里的种子下载方式，而是使用现成的磁力链转种子的网站服务，这样我只需要使用erlang自带的HTTP客户端就可以获取种子信息。爬虫在获取到种子信息后，将数据存储到mongodb里。WEB端我为了尽量少用第三方库，我只好使用erlang自带的HTTP服务器，因此网页内容的创建没有模板系统可用，只好通过字符串构建，编写起来不太方便。

## 使用

整个程序依赖了两个库：bson-erlang和mongodb-erlang，但下载依赖库的事都可以通过rebar解决，项目文件里我已经包含了rebar的执行程序。我仅在Windows7上测试过，但理论上在所有erlang支持的系统上都可以。

* 下载安装[mongodb](http://www.mongodb.org/downloads)
* 进入mongodb bin目录启动mongodb，数据库目录保存在db下，需手动建立该目录

        mongod --dbpath db --setParameter textSearchEnabled=true

* 下载[erlang](http://www.erlang.org/download.html)，我使用的是R16B版本
* 下载dhtcrawler，不需要单独下载kdht，待会下载依赖项的时候会自动下载

        git clone git@github.com:kevinlynx/dhtcrawler.git

* cmd进入dhtcrawler目录，下载依赖项前需保证环境变量里有git，例如`D:\Program Files (x86)\Git\cmd`，需注意不要将bash的目录加入进来，使用以下命令下载依赖项

        rebar get-deps

* 编译

        rebar compile

* 在dhtcrawler目录下，启动erlang

        erl -pa ebin

* 在erlang shell里运行爬虫，**erlang语句以点号(.)作为结束**

        crawler_app:start().

* erlang shell里运行HTTP服务器

        crawler_http:start().

* 浏览器里输入`localhost:8000/index.html`，这个时候还没有索引到资源，建议监视网络流量以观察爬虫程序是否正确工作

爬虫程序启动时会读取`priv/dhtcrawler.config`配置文件，该文件里配置了DHT节点的UDP监听端口、节点数量、数据库地址等，可自行配置。

接下来我会谈谈各部分的实现方法。


