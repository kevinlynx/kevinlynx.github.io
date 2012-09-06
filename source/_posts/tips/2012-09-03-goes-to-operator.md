---
layout: post
title: "c/c++中的-->运算符"
date: 2012-09-03 15:14
comments: true
categories: [tips, c/c++]
tags: [tips]
keywords: -->, c/c++, operator
description: -->是一个合法的操作符，我打赌自认c/c++熟手的你们都不知道这个操作符。有人称它为goes to操作符，x-->0表示x向0趋近。
---

参考[What is the name of this operator: "-->"?](http://stackoverflow.com/questions/1642028/what-is-the-name-of-this-operator)

c/c++中以下代码是合法的：

{% highlight c++ %}
#include <stdio.h>
int main()
{
     int x = 10;
     while( x --> 0 ) // x goes to 0
     {
        printf("%d ", x);
     }
}
{% endhighlight %}
<!-- more -->
`-->`是一个合法的操作符，我打赌自认c/c++熟手的你们都不知道这个操作符。有人称它为`goes to`操作符，`x-->0`表示x向0趋近。

**其实我在忽悠你们。** 并且我相信有很多人对此把戏相当熟悉。没错，`-->`只是两个操作符恰好遇在了一起，他们是自减运算符`--`和大于比较运算符`>`：

{% highlight c++ %}
while (x-- > 0)
    ...
{% endhighlight %}

类似的把戏还有：

{% highlight c++ %}
while (x -- \
             \
              \
               \
                > 0)
    printf("%d ", x);
{% endhighlight %}




