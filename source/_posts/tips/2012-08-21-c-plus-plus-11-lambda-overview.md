---
layout: post
title: "C++11中lambda概览"
date: 2012-08-21 16:44
comments: true
categories: [tips, c/c++]
tags: [tips, c/c++]
---

虽然我对C++11没有什么兴趣，因为C++03就已经有很多复杂的技术了。我曾经试图把我学到的那些复杂的C++技术应用到项目中，但悲剧地发现这给团队其他成员带来了不小的负担。其实也给未来一段时间的自己带来了不小的负担。尤其是template的应用，template代码从外表上就一副唬人的样子，就像即使你会Lisp，并且对Lisp中的括号不以为然，但看到满屏幕的括号时依然内心不安。

但是稍微对C++11的一些特性做了解后，单从理论上来说，还是挺让人有兴趣的。我感觉C++11加入了不少函数式语言的特性和思想，这是我感兴趣的最大理由。今天来看看C++11中的lambda。
<!-- more -->
C++03中，在使用STL容器时，或者我自己写的类中，常有遍历的需求，本来写个functor传进去就可以，但是这functor偏偏写的很恶心。因为你需要局部定义一个结构体，重载operator()，并且，如果这个operator()依赖这个functor构建时的上下文信息，你得往这个结构体里塞入若干成员，当然还得让构造函数的参数变得越来越长。最后，在包含你这个functor使用以及结构体定义的这个代码块中，在其代码格式上就变得非常奇怪。如果你像我一样常这样应用，一定深有感触。

然后，C++11来了，C++11中的lambda，就我个人而言，其语法还是非常现代的。来看看其文法形式（截自[N2550](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2008/n2550.pdf)）：

    lambda-expression:
          lambda-introducer lambda-parameter-declaration compound-statement
    lambda-introducer:
          [ lambda-capture ]
    lambda-capture:
          capture-default
          capture-list
          capture-default , capture-list
    capture-default:
          &
          =
    capture-list:
          capture
          capture-list , capture
    capture:
          identifier
          & identifier
          this
    lambda-parameter-declaration:
          ( lambda-parameter-declaration-list ) exception-specification lambda-return-type-clause
    lambda-parameter-declaration-list:
          lambda-parameter
          lambda-parameter , lambda-parameter-declaration-list
    lambda-parameter:
          decl-specifier-seq declarator
    lambda-return-type-clause:
          -> type-id

翻译过来大致就是这样的形式：

    [capture] (parameter) spec ->return-type { body }

capture就是这个lambda实现里可以访问的这个lambda定义时作用域里的变量列表，就像Lua里的upvalue。其实我觉得这个才是lambda最方便程序员的地方，一般的函数式语言其实不需要显示声明这个列表，直接引用这些变量即可。后面的部分都比较好理解，parameter就是这个lambda被调用时的形参列表，return-type就是这个lambda的返回值类型，body自然就是这个lambda的实现。至于spec，主要就是指定异常及body里对capture里的变量的使用权限。一个例子：

{% highlight c++ %}
vector<int> ints;
ints.push_back(99);
ints.push_back(100);
ints.push_back(101);
int threhold = 100;
int sum = 0;
for_each(ints.begin(), ints.end(), 
        [threhold, &sum] (int v) { 
            if (v >= threhold) ++ sum;
            });
printf("%d\n", sum);
{% endhighlight %}

capture使用了threhold和sum，但是threhold仅使用其值，而sum则使用了其引用，通过结果可以看出lambda中改变了sum的值。

C++11正在被越来越多的编译器支持，也慢慢地支持得更好。这里有个[表](http://wiki.apache.org/stdcxx/C++0xCompilerSupport)，罗列了C++11的各个特性在各个编译器上的支持情况，仅供查阅（以上示例代码测试于vs2010，即MSVC10.0）。
