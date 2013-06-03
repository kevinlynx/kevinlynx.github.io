---
layout: post
title: "erlang编程技巧若干"
date: 2013-06-03 21:53
comments: true
categories: [tips, erlang]
tags: [tips, erlang]
keywords: erlang, tips
---

## guard

guard可以以逗号或者分号分隔，以逗号分隔表示最终的结果为各个guard的and结果，以分号则是只要任意一个guard为true则最终结果为true。

{% highlight erlang %}
guard(X, Y) when not(X>Y), is_atom(X) ->
    X + Y.
{% endhighlight %}

guard在list comprehension中可以筛选元素：

{% highlight erlang %}
NewNodes  = [Node || Node <- AllNodes, not gb_sets:is_member(Node, NewQueried)],
{% endhighlight %}

guard中不能使用自定义函数，因为guard应该保证没有副作用，但自定义函数无法保证这一点，所以erlang禁止在guard中使用自定义函数。
<!-- more -->
## list comprehension

list comprehension是一个非常有用的语法特性，它可以用于构造一个新的list，可以用于将一种list映射到另一种list，可以筛选list元素。只要是跟list相关的操作，优先考虑用list comprehension来实现，将大大减少代码量。记住list comprehension的语法：

    [Expression || Generators, Guards, Generators, ...]

## timer

一定时间后向进程发送消息：

{% highlight erlang %}
erlang:send_after(token_lifetime(), self(), renew_token),
{% endhighlight %}

一段时间后执行某个函数：

{% highlight erlang %}
{% raw %}
{ok, TRef} = timer:apply_interval(Interval, ?MODULE, announce, [self()]),
{% endraw %}
{% endhighlight %}

## gb_trees/gb_set

## pattern match 

pattern match有太多作用了：

### pattern match in case

case中判定多个值，比其使用逻辑运算符简洁多了：

{% highlight erlang %}
{% raw %}
A = 1, B = 2,
case {A, B} of
    {_C, _C} -> true;
    {_, _} -> false
end
{% endraw %}
{% endhighlight %}

### pattern match to check data type

pattern match可以用于检测变量的类型，可以用于检测函数的返回值，就像C/C++中的assert一样，可以用于尽早检测出异常状态：

{% highlight erlang %}
ping({_, _, _, _} = IP, Port) ->
    ok.
{ok, Ret} = call().
{% endhighlight %}

## list操作

### 添加元素

添加元素进list有很多方式：

{% highlight erlang %}
[2]++[3, 4].
[2|[3,4]].
{% endhighlight %}

### foldl/foldr

用于遍历list计算出一个“累加值“。

{% highlight erlang %}
lists:foldl(fun(X, Sum) -> X + Sum end, 0, [1,2,3,4,5]).
{% endhighlight %}

也就是遍历一个list，将每个元素传递给fun，将fun的返回值继续传递给下一个元素。

### zip

将两个list一一对应构造出一个tuple，作为新的list里的元素。

{% highlight erlang %}
lists:zip([1, 2, 3], [4, 5, 6]).
    => [{1,4},{2,5},{3,6}]
{% endhighlight %}

### 数字进制

16##FF，表示16进制数字0xFF，通用格式为scale##num，即scale进制下的num。


