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

