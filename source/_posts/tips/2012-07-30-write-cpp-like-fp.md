---
layout: post
title: "像写函数式语言代码一样写C++"
date: 2012-07-30 17:11
comments: true
categories: [tips, c/c++]
tags: [tips, c/c++]
---

忘记最早接触函数式编程语言是什么时候了，也忘记接触的第一门函数式语言是哪一门。断断续续接触过好几种函数式语言（当然都算不纯的，ruby/lisp不算纯吧），这些语言的思想在潜移默化中多多少少对我有所影响。

我是个C++程序员，我不知道我平时写的都是些什么代码。最让人印象深刻就是我会经常写遍历STL容器的代码，是经常，这样的遍历你可能也不陌生：

{% highlight c++ %}
{% raw %}
for (ListType::iterator it = con.begin(); it != con.end(); ++it) {
    something
}
{% endraw %}
{% endhighlight %}

<!-- more -->
或者针对std::map/set等的查找：

{% highlight c++ %}
{% raw %}
Table::iterator it = table.find(key);
if (it == table.end())
    do-something
do-something
{% endraw %}
{% endhighlight %}

多亏STL接口的一致性，这让我们写出了很多“一致性“代码。慢慢地我觉得恶心，不禁想起函数式编程语言中，对于这种需求一般都会提供类似的接口：

{% highlight lua %}
con.map(function (it) if (it->some-filed == some-value) return something end)
# 或者
con.each do |it| if it.some-filed == some-value then return something end end
# 或者
(con.map (lambda (it) (if ((= it.some-filed some-value)) (return something))))
{% endhighlight %}

（好吧，lisp我又忘了）总之，这种针对容器的遍历操作，都会成为一种内置接口，并且通过lambda来让用户直接编写处理代码，少去写循环的冗余。然后，我写了类似下面的一组宏（随手敲的不保证能运行）：

{% highlight c++ %}
{% raw %}
#define IT_N __it

#define TRAVERSE_MAP(type, map, exps) \
    for (type::iterator IT_N = map.begin(); IT_N != map.end(); ++IT_N) { \
        exps; \
    }
#define I_KEY (IT_N->first)
#define I_VALUE (IT_N->second)

#define TRAVERSE_LIST(type, list, exps) \
    for (type::iterator IT_N = list.begin(); IT_N != list.end(); ++IT_N) { \
        exps; \
    }
#define L_VALUE (*IT_N)

#define FIDN_MAP_ITEM(type, map, key, fexps, texps) \
    do { \
        type::iterator IT_N = map.find(key); \
        if (IT_N == map.end()) { \
            fexps; \
        } else { \
            texps; \
        } \
    } while(0)

#define VAL_N __val
#define FIND_LIST_ITEM_IF(type, list, cmp, fexps, texps) \
    do { \
        struct Comp { \
            bool operator() (const type::value_type &VAL_N) const { \
                return cmp; \
            } \
        }; \
        type::iterator IT_N = std::find_if(list.begin(), list.end(), Comp()); \
        if (IT_N != list.end()) { \
            texps; \
        } else { \
            fexps; \
        } \
    } while(0)

#define NULL_EXP ;

{% endraw %}
{% endhighlight %}

当然，以上接口都还包含一些const版本，用于const容器的使用。使用的时候（截取的项目中的使用例子）：

{% highlight c++ %}
TRAVERSE_MAP(TimerTable, m_timers, 
        I_VALUE.obj->OnTimerCancel(I_KEY, I_VALUE.arg);
        TIMER_CANCEL(I_VALUE.id)); 

TRAVERSE_LIST(AreaList, areas,
        ids.push_back(L_VALUE->ID()));

FIND_MAP_ITEM(PropertyTable, m_properties, name,
        LogWarn("set a non-existed property %s", name.c_str()); return NIL_VALUE,
        if (val.Type() != I_VALUE.type()) {
            return NIL_VALUE; 
        } else {
            GValue old = I_VALUE;
            I_VALUE = val; 
            return old;
        });

{% endhighlight %}

多亏了C/C++宏对一切内容的可容纳性，可以让我往宏参数里塞进像if这种复合语句，甚至多条语句（例如最后一个例子）。这些宏我使用了一段时间，开始觉得挺爽，很多函数的实现里，我再也不用写那些重复的代码了。但是后来我发觉这些代码越来越恶心了。最大的弊端在于不可调试，我只能将断点下到更深的代码层；然后就是看起来特不直观，连作者自己都看得觉得不直观了，可想而知那些连函数式编程语言都不知道是什么的C++程序员看到这些代码会是什么心情（可以想象哥已经被诅咒了多少次）。

函数式语言让人写出更短的代码，这一点也对我有影响，例如我最近又写下了一些邪恶代码：

{% highlight c++ %}
// split a string into several sub strings by a split character i.e:
// "a;b;c;" => "a", "b", "c"
// "a;b;c" => "a", "b", "c"
std::vector<std::string> SplitString(const std::string &str, char split) {
    std::vector<std::string> ret;
    size_t last = 0;
    for (size_t pos = str.find(split); pos != std::string::npos; last = pos + 1, pos = str.find(split, last)) {
        ret.push_back(str.substr(last, pos - last));
    }
    return last < str.length() ? ret.push_back(str.substr(last)) : 0, ret;
}
{% endhighlight %}

恶心的就是最后那条return语句，因为我需要处理"a;b;c"这种c后面没加分隔符的情况，但我并不愿意为了这个需求再写一个会占超过一行的if语句。因为，我太喜欢ruby里的if了：

{% highlight ruby %}
do-something if exp
{% endhighlight %}

也就是ruby里允许这种只有一行if的代码将if放在其后并作为一条语句。我的不愿意其实是有理由的，在c/c++中有太多只有一行条件体的if语句，对这些语句参合进编程风格/可读性进来后，就不得不让你写出不安的代码，例如：

{% highlight c++ %}
if (something) return something; // 某些编程风格里不允许这样做，因为它不方便调试

if (something) 
    return something; // 某些风格里又有大括号的统一要求

if (something) {
    return something; // 就算符合风格了，但这一条语句就得多个大括号
}

if (something) 
{
    return something; // 某些风格里这大括号就更奢侈了
}
{% endhighlight %}

这个return除了乍看上去有点纠结外，其实也不算什么大问题，但是那个问号表达式返回的0实在没有任何意义，而正是没有意义才会让它误导人。本来我是可以写成：

{% highlight c++ %}
return last < str.length() && ret.push_back(str.substr(last)), ret;
{% endhighlight %}

这样利用条件表达式的短路运算，代码也清晰多了。但是，std::vector::push_back是一个没有返回值的函数，所以。

全文完。

