---
layout: post
title: "使用erlang实现P2P磁力搜索-实现"
categories: [erlang, network]
tags: [erlang, dht, p2p, magnet]
comments: true
keywords: [erlang, dht, p2p, magnet]
description: 
published: false
---

接[上篇](http://codemacro.com/2013/06/20/magnet-search/)，本篇谈谈一些实现细节。

这个爬虫程序主要的问题在于如何获取P2P网络中分享的资源，获取到资源后索引到数据库中，搜索就是自然而然的事情。

DHT网络主要目的是用于查询，查询

