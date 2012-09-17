---
layout: post
title: "C++陷阱：virtual析构函数"
date: 2012-09-13 17:03
comments: true
categories: [c/c++]
tags: [c/c++, destructor, virtual]
keywords: c/c++, virtual, destructor
description: 当然，实际代码比这个复杂得多(这也是导致从发现问题到找到问题耗费大量时间的原因)。vld在报内存泄漏时，当然报的位置是`new`的地方。这个同事检查了这个对象的整个生命周期，确定他正确地释放了这个对象。
---

有一天有个同事在通过vld调试一个内存泄漏问题，折腾了很久然后找到我。我瞥了一眼他的代码，发现问题和我曾经遇到的一模一样：

{% highlight c++ %}
class Base {
public:
    ~Base();
};

class Derived : public Base {
privated:
    std::vector<int> m_data;    
};

Base *obj = new Derived();
delete obj;
{% endhighlight %}
<!-- more -->
当然，实际代码比这个复杂得多(这也是导致从发现问题到找到问题耗费大量时间的原因)。vld在报内存泄漏时，当然报的位置是`new`的地方。这个同事检查了这个对象的整个生命周期，确定他正确地释放了这个对象。

问题的关键就在于：**`Base`类的析构函数不是`virtual`的**。因为不是`virtual`，所以在对一个`Base`类型的指针进行`delete`时，就不会调用到派生类`Derived`的析构函数。而派生类里的析构函数会用于析构其内部的子对象，也就是这里的`m_data`。这样，就造成了内存泄漏。

这其实是一个很低级的失误。但毫不客气地说C++中有很多这种少个关键字或者代码位置不对就会造成另一个结果的例子。事实上，针对这些悲剧也有很多书提出一些准则来让大家去无脑遵守。例如针对这个例子，我就记得曾有书说，只要你觉得你的类会被继承，那么最好给析构函数加上virtual。



