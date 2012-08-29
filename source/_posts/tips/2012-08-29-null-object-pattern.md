---
layout: post
title: "Null Object模式"
date: 2012-08-29 15:57
comments: true
categories: [tips, c/c++]
tags: [tips, c/c++]
---

Null Object模式用于代替空指针（C++中），以避免上层模块对返回值做空值判定。Null Object模式返回的不是一个空指针，而是一个空对象，上层模块对返回值做操作时，不需要做空判定，而是按正常逻辑调用这个对象的某个接口，只不过对于空对象而言，这个接口什么事也没做，例如：

{% highlight c++ %}
class animal {
public:
  virtual void make_sound() = 0;
};
 
class dog : public animal {
  void make_sound() { cout << "woof!" << endl; }
};
 
class null_animal : public animal {
  void make_sound() { }
};

{% endhighlight %}

在我看来这个模式在C++中其实挺扯淡的，因为去判断一个指针是否为NULL，远比创建一个空类，并且添加若干个空函数代价小更多。更何况，我们还不知道`null_animal`的生命周期如何管理。

但是在我以往写的代码中，我也写过一些避免空指针判定的代码，例如我会使用引用。注意，引用肯定不能保证所对应的对象是合法的，这就像无法确定一个指针是不是野指针一样：

{% highlight c++ %}
const Item &Container::FindItem(int id) const {
    static Item null_item;
    Table::const_iterator it = m_items.find(id);
    return it == m_items.end() ? null_item : it->second;
}
{% endhighlight %}

参考<http://en.wikipedia.org/wiki/Null_Object_pattern>
