---
layout: post
title: "C++陷阱：构造函数中的多态"
date: 2012-09-17 16:01
comments: true
categories: [c/c++]
tags: [c/c++, virtual]
keywords: c/c++, virtual, polymorphism
description: C++中主要是通过给函数加上`virtual`关键字来实现多态。多态可用于改变一个接口的实现，也算是一种嵌入应用层代码到底层的实现手段。就算你用不到C++那些复杂的技术，多态肯定会被用到。
---

C++中主要是通过给函数加上`virtual`关键字来实现多态。多态可用于改变一个接口的实现，也算是一种嵌入应用层代码到底层的实现手段。就算你用不到C++那些复杂的技术，多态肯定会被用到。

但加上`virtual`不一定能保证多态成功：
<!-- more -->
{% highlight c++ %}
{% raw %}
#include <stdio.h>

class Base {
public:
    Base() {
        Init();
    }

    virtual ~Base() {
        Release();
    }

    virtual void Init() {
        printf("Base::Init\n");
    }

    virtual void Release() {
        printf("Base::Release\n");
    }
};

class Derived : public Base {
public:
    virtual void Init() {
        printf("Derived::Init\n");
    }

    virtual void Release() {
        printf("Derived:Release\n");
    }
};

int main()
{
    Base *obj = new Derived();
    delete obj;
    return 0;
}
{% endraw %}
{% endhighlight %}

当在构造函数，包括析构函数中调用`virtual`函数时，预想中的多态是无法完成的，以上代码输出结果为：

{% highlight c++ %}
Base::Init
Base::Release
{% endhighlight %}

从语言设计角度来看，我个人是不接受这种行为的。我觉得对一门语言而言，几乎所有特性都应该是一致的，不应该或尽量少地出现这种“例外“。如果我构造一个对象，让它以不同的方式被构造，这和改变它的某个行为有什么区别？（从这句话来看，似乎还真有区别）

当然，从语言实现来看，这样的运行结果又似乎是必然的。因为，基类的构造是早于派生类的（作为其一部分），只有当构造完派生类后，其用于支持多态的虚表才会被正确构造。也就是说，在基类中调用虚函数时，既然虚表都为正确构造，自然调用的不会是派生类的虚函数了。析构函数按照析构的顺序来看，也会面临同样的情况。

**UPDATE**

*因为我接触了很多编程语言，2010年之前甚至是C++的重度粉，在学习各种编程语言的过程中我领略到语言设计里的很多艺术及美感，以及各种妥协。遗憾的是我不能站在更高的计算机程序语言理论层面评论这些语言。*

*所以，对于本文描述的问题，我并不需要找到C++ language manual里某section里提到的standard。我想从语言设计者的角度来考虑这个问题。*

语言设计者需要让语言的设计思想贯穿整个语言的设计，而同时也需要考虑到语言实现的可行性。

*lisp虽然我觉得易用性是个问题，但它的设计是非常统一的：所有操作符都被视作函数，它们同函数拥有相同的语法；lisp的编译器实现也是相对容易的，因为前缀表达式基本就是语法树。erlang的基础API设计得非常糟糕，因为其API原型很不一致。*

派生类用于扩展基类功能，同时依赖了基类。所以如果在基类构造函数中可以多态地调用到派生类里的函数，那必然会引起问题：
     
{% highlight c++ %}
Base::Base() {
    init(); // if we called Derived::init
    init io 
}

Derived::init() {
    use base io file descriptor etc
}

{% endhighlight %}

*这个结论其实我之前已经说过*

析构函数面临相同的问题：


{% highlight c++ %}
Base::~Base() {
    release();
}

Derived::~Derived() {
    release my io file descriptor etc
} // Base::~Base will be called 

Derived::release() {
    use my io file descriptor
}

{% endhighlight %}

从语言设计角度，派生类就是可以在任意地方使用基类的东西，这也是为什么基类构造函数要先于派生类构造函数调用的很大原因。另一方面，一个类在自己的任意地方使用自己的东西也是很自然的事情。上面的代码都再自然不过，但是语言设计者如果设定这里的多态要起作用，那这些代码将非常危险。



