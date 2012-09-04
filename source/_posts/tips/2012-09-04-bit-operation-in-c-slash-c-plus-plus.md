---
layout: post
title: "c/c++中几种操作位的方法"
date: 2012-09-04 19:49
comments: true
categories: [tips, c/c++]
tags: [tips, c/c++]
---

参考[How do you set, clear and toggle a single bit in C?](http://stackoverflow.com/questions/47981/how-do-you-set-clear-and-toggle-a-single-bit-in-c)

c/c++中对二进制位的操作包括设置某位为1、清除某位（置为0）、开关某位(toggling a bit)、检查某位是否为1等。这些操作较为常见并且可以作为其他位运算的基础接口，以下罗列几种方法：

## 传统方法

* 设置某位为1

{% highlight c++ %}
number |= 1 << x; // 设置第x位为1
{% endhighlight %}
<!-- more -->
* 清除某位

{% highlight c++ %}
number &= ~(1 << x); // 置第x位为0
{% endhighlight %}

* 开关某位

{% highlight c++ %}
number ^= 1 << x;
{% endhighlight %}

* 检查某位

{% highlight c++ %}
if (number & (1 << x))
{% endhighlight %}

相应地我们可以将其封装起来，简便的方法是使用宏来封装：

{% highlight c++ %}
#define BIT_SET(a,b) ((a) |= (1<<(b)))
#define BIT_CLEAR(a,b) ((a) &= ~(1<<(b)))
#define BIT_FLIP(a,b) ((a) ^= (1<<(b)))
#define BIT_CHECK(a,b) ((a) & (1<<(b)))
{% endhighlight %}

## 使用位结构操作

这个使用起来简单很多：

{% highlight c++ %}
struct bits {
    unsigned int a:1;
    unsigned int b:1;
    unsigned int c:1;
};

struct bits mybits;

// set/clear a bit
mybits.b = 1;
mybits.c = 0;

// toggle a bit
mybits.a = !mybits.a;
mybits.b = ~mybits.b;
mybits.c ^= 1;

// check a bit
if (mybits.c)
{% endhighlight %}

## 使用STL的std::bitset<N>

这个方法其实类似于使用位结构，只不过STL包装了这个结构定义，当然还提供了很多便捷的接口：

{% highlight c++ %}
std::bitset<5> bits;
bits[0] = true;
bits[1] = false;
bits.set(2);
bits.flip(3);
bits.reset(2);
{% endhighlight %}

