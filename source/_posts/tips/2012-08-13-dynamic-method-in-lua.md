---
layout: post
title: "Lua中动态产生函数"
date: 2012-08-13 15:56
comments: true
categories: [tips, lua]
tags: [tips, lua]
keywords: lua, object-oriented
description: 可以结合[Lua里实现简单的类-对象]看。在我的应用中，存在类似以下代码：
---

可以结合[Lua里实现简单的类-对象](http://codemacro.com/2012/08/02/simple-oo-in-lua/)看。在我的应用中，存在类似以下代码：

{% highlight lua %}
function Item.new()
    local o = {
        property = {}
    }
    return newObject(o, Item)
end
{% endhighlight %}

`property`是一个key-value的表，里面的内容不是固定的。最开始我为Item类写了get/set函数，用于存取property表里的值。但这样写起来还是有点麻烦。Ruby里可以动态产生类成员函数，其实Lua里也可以。其思路就是通过metatable来做：
<!-- more -->
{% highlight lua %}
-- 为newObject增加一个可选参数，该参数是一个函数，当在表示类的table里无法找到成员时就调用该可选参数
function newObject(o, class, after)
    class.__index = function (self, key) return class[key] or after(self, key) end
    return setmetatable(o, class)
end
{% endhighlight %}

然后就是编写这个after函数，我的理想方式是，例如property里有Name和Index的key-value，那么就可以通过这样的方式来存取：

{% highlight lua %}
item = Item.new()
print(item:Name())
item:SetName("hello")
print(item:Index()
item:SetIndex(101)
{% endhighlight %}

after函数的实现：

{% highlight lua %}
function Item.new()
    local o = {
        property = {}
    }
    local function after(self, key)
        local name = string.match(key, "Set(%a+)")
        if name then 
            return function (self, value)
                self:set(name, value)
            end
        else
            return function (self)
                return self.property[key] and self.property[key].value
            end
        end
    end
    return newObject(o, Item, after)
end
{% endhighlight %}

执行过程就为：

* 当item:Name()执行时，首先试图获取Item上的Name成员，没找到就调用传入的after函数，这个函数检查`Name`这个字符串是否是`SetXX`的形式，如果不是则返回一个获取函数；这个时候取得Name成员，然后将其作为函数调用，相当于调用了after刚才返回的函数
* item:SetName("hello")过程类似，只不过调用了另一个返回函数。


