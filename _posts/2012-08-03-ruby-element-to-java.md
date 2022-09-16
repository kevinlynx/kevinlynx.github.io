---
layout: post
title: "『你会把Ruby的哪些特性加入Java』"
date: 2012-08-03 14:14
comments: true
categories: [ruby]
tags: [ruby, java]
---

参考（翻译、摘抄）于[Can Ruby Live without Rails?](http://java.sys-con.com/node/251986)。这篇文章发表于2006年，受访者在回答“如果可以你会把Ruby的哪些特性加入Java“这个问题时，提到了Ruby的一些我个人认为比较突出的语法特性。其实并不是针对Java语言，何况6年时间过去，以Java语法特性的加入速度怕早就有Ruby这些特性了。我对Java不熟，仅限于曾经写的几个简单的android应用，买了\<Java编程思想\>也没翻完。

以下内容半翻译自原文。

### Closure

闭包支持将代码块作为函数参数传递。这在写很多代码时会比较方便，例如以下代码打印10次字符串：

{% highlight ruby %}
10.times { puts "Hello" }
{% endhighlight %}
<!-- more -->
又例如针对数组的每个元素做一些事情（do...end是上例中{}的替代）：

{% highlight ruby %}
array.each do |item|
  item.do_something
end
{% endhighlight %}

也可以构建一个新的数组：

{% highlight ruby %}
array.collect { |number| number * number }
{% endhighlight %}

Ruby中闭包的使用随处可见，它的语法形式太简单，这使得要使用它时所付出的代价很小（想想其他语言里得手动构造一个函数对象吧）。

### Continuation

使用continuation你可以保存一块代码的执行状态，以便将来某个时刻恢复执行。这就像游戏存档一样，玩到一半存档，一段时间回来后取出存档从上次的进度继续玩。


{% highlight ruby %}
require 'continuation' # 原文中未给这句，须加上

def loop
  for i in 1..10
    puts i
    callcc { |c| return c } if i == 5
  end
end
{% endhighlight %}

`loop`函数执行里面那个循环时，当`i==5`就调用`callcc`函数（貌似现在Java已有这个了），该函数在回调传入的闭包时构建了一个continuation对象，以上代码直接将此对象返回，循环暂停于`i==5`。执行代码`continuation = loop`输出：

{% highlight ruby %}
1
2
3
4
5
{% endhighlight %}

然后你可以在任意时刻恢复执行那个循环：`continuation.call`，得到：

{% highlight ruby %}
6
7
8
9
10
{% endhighlight %}

这个continuation和Lua里的`coroutine`很像，可以用于实现轻量级的线程。

### mix-ins

这节没看懂。提到了AOP、POJO之类的术语，大概是Java世界里的什么东西。看起来像是针对before/after method的东西，意思就是执行某个函数时，会先去执行before函数，完了后再执行after函数，Lisp里有这个概念。

### Open class

这个算是Ruby里用的比较多的特性。open classes可以让你在很多情况下“打开“并重定义某个类，这个类可以是你使用的任意库里的类。Ruby里的类并不是一个封闭的代码集合，作为一个类库的使用者你甚至可以不用修改类库的代码而重新定义、扩展里面的接口。例如Ruby中的数字其实就是Fixnum类，而我们可以为Fixnum直接添加更多的接口（原文的代码有问题，以下我做了修改）：

{% highlight ruby %}
class Fixnum
  def days
    self.hours * 24
  end

  def hours
    self.minutes * 60
  end

  def minutes
    self.seconds * 60
  end

  def seconds
    self
  end

  def from_now
    Time.now + self
  end

  def ago
    Time.now - self
  end
end
{% endhighlight %}

基于以上，我们可以写出`10.days.ago`或者`6.hours.from_now`这样的代码。这有助于构建DSL(domain specific language)。

### Full object orientation

Ruby中一切都是对象。这让我们写代码变得更容易，因为不用处理特殊情况。这些特殊情况主要就是很多基础数据类型并非对象，但Ruby里是。Ruby里每个对象都有一个函数`class`，表示该对象的类型：

{% highlight ruby %}
1.class # => Fixnum
2.5.class # = > Float
"hello".class # => String
[1, 2].class # => Array
(1..2).class # => Range
{% endhighlight %}

全文完。

