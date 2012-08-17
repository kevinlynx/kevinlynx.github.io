---
layout: post
title: "使用memcmp比较两个变量结果一定吗？"
date: 2012-08-17 11:37
comments: true
categories: [tips, c/c++]
tags: [tips, c/c++]
---

参考[Is using memcmp on array of int strictly conforming?](http://stackoverflow.com/questions/11994513/is-using-memcmp-on-array-of-int-strictly-conforming)

以下代码一定会输出ok吗？

{% highlight c %}
#include <stdio.h>
#include <string.h>

struct S { int array[2]; };

int main () {
    struct S a = { { 1, 2 } };
    struct S b;
    b = a;
    if (memcmp(b.array, a.array, sizeof(b.array)) == 0) {
        puts("ok");
    }
    return 0;
}
{% endhighlight %}
<!-- more -->
我在vs2005以及gcc4.4.3上做了测试，都输出了ok。但这并不意味这个代码会永远输出ok。问题主要集中于这里使用了赋值语句来复制值，但却使用了memcmp这个基于内存数据比较的函数来比较值。

c语言中的赋值运算符（=）被定义为基于值的复制，而不是基于内存内容的复制。

> **C99 section 6.5.16.1 p2:** In simple assignment (=), the value of the right operand is converted to the type of the assignment expression and replaces the value stored in the object designated by the left operand.

这个其实很好理解，尤其在不同类型的数字类型间复制时，例如：

{% highlight c %}
float a = 1.1;
int b = a;
{% endhighlight %}

因为浮点数和整形数的内存布局不一样，所以肯定是基于值的一种复制。另外，按照语言标准的思路来看，内存布局这种东西一般都属于实现相关的，所以语言标准是不会依赖实现去定义语言的。

上面的定理同样用于复杂数据类型，例如结构体。我们都知道结构体每个成员之间可能会有字节补齐，而使用赋值运算符来复制时，会不会复制这些补齐字节的内容，是语言标准未规定的。这意味着使用memcmp比较两个通过赋值运算符复制的两个结构体时，其结果是未定的。

但是上面的代码例子中，比较的其实是两个int数组。这也无法确认结果吗？这个问题最终集中于，难道int也会有不确定的补齐字节数据？

> **C99 6.2.6.2 integer types** For signed integer types, the bits of the object representation shall be divided into three groups: value bits, padding bits, and the sign bit. [...] The values of any padding bits are unspecified.

这话其实我也不太懂。一个有符号整数int，其内也有补齐二进制位(bits)？

但无论如何，这个例子都不算严谨的代码。人们的建议是使用memcpy来复制这种数据，因为memcpy和memcmp都是基于内存内容来工作的。



