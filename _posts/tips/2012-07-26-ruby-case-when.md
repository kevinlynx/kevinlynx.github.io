---
layout: post
title: "ruby中的case...when语法"
date: 2012-07-26 10:13
comments: true
categories: [tips, ruby]
tags: [tips, ruby]
---

参考[How to write a switch statement in Ruby?](http://stackoverflow.com/questions/948135/how-to-write-a-switch-statement-in-ruby)

其实用Rails写个业务逻辑不算复杂的app根本用不上ruby的很多高级语法，更别说\<meta programming in ruby\>中的东西了（凡是打上meta programming标签的都不是什么简单的东西，参考c++/lisp）。ruby中的case...when语句和c/c++中的switch...case其实根本不是一回事。\<Programming in Ruby 2nd\>：

> case operates by comparing the target with each of the comparison expression after the when keywords. This test is done using comparison === target.

<!-- more -->
也就是说case...when用的不是==操作符，不是使用相等逻辑去判断，而是使用===运算符。===运算符从C++的角度简单来说就是判定is-a关系，例如

{% highlight ruby %}
Fixnum === 1
String === "hello"
(1..3) === 2
{% endhighlight %}

1 is a Fixnum，hello is a String，2 is a (1..3) (in the range of)。比较让人产生误解的，大概就是1===1也为true。所以理解起来，也不纯碎是is-a关系。

{% highlight ruby %}
case a
when Fixnum
    puts "fixnum"
when String
    puts "string"
when (1..3)
    puts "between 1 and 3"
else
    puts "default"
end
{% endhighlight %}

最后，作为一种functional-like language，其语句也算是表达式，意即也有返回值。case..when的返回值就是执行的分支的返回值。

