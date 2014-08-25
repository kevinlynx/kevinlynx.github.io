---
layout: post
title: "Lua里实现简单的类-对象"
date: 2012-08-02 10:18
comments: true
categories: [tips, lua]
tags: [tips, lua, rapanui, moai]
---

要在Lua里实现面向对象有很多方法，为了支持面向对象的一些特性（类、对象、继承、重载等），其实现可能会比较复杂。看看云风的[这篇](http://blog.codingnow.com/2006/06/oo_lua.html)，以及后面的评论，有总结的不错的。这真是让人对Lua刮目相看。但是我并不需要这些机制，一般情况下我只需要支持类即可。

类其实就是定义一个对象的函数模板，避免我写出带模块名并且第一个参数是操作对象的函数（像C一样）。以下代码提炼于rapanui（基于[moai](http://getmoai.com/)的高层封装），摘抄于几个月前我基于rapanui移植到android上的一个[小游戏](https://github.com/kevinlynx/crazyeggs_mobile)：

<!-- more -->
{% highlight lua %}
local function newindex(self, key, value)
    getmetatable(self).__object[key] = value
end

local function index(self, key)
    return getmetatable(self).__object[key]
end

function newObject(o, class)
    class.__index = class
    setmetatable(o, class)
    return setmetatable({}, { __newindex = newindex, __index = index, __object = o })
end
{% endhighlight %}

基于newObject函数，可以这样定义类：

{% highlight lua %}
Button = {}

function Button.new(text, x, y, onclick, parent)
    -- 定义这个类的数据成员
    local obj = {
        text = text,
        onclick = onclick,
        normal_img = nil,
        text_inst = nil,
        hover_img = nil,
    }
    obj = newObject(obj, Button)
    ...
    return obj
end

function Button:onTouchDown(x, y)
    ...
    -- 可以访问成员，即使看起来normal_img不属于Button这个table
    self.normal_img.visible = true
end

function Button:onTouchUp(x, y)
    ...
end
{% endhighlight %}

通过以上定义后，就可以以面向对象的方式来使用Button类了：

{% highlight lua %}
local btn = Button.new()
btn:OnTouchDown(100, 100)
btn:OnTouchUp(100, 100)
{% endhighlight %}

其实现原理，主要就是将类的函数集通过`__index`开放给对象，在这些函数中，其`self`就像c++ 中的`this`一样拥有多态性，即其是创建出来的对象，而不是作为类角色的那个`table`（例如Button）。

<hr/>

#### 8.13.2012更新

其实根本没必要这么复杂，`newObject`函数多引入了一个空表，实在看不出有什么作用，修改后的版本简单直接：

{% highlight lua %}
function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end
{% endhighlight %}

因为只需要将类定义的函数引入到实际对象里，使用方法相同。另外上文中提到的一句话：

> 在这些函数中，其`self`就像c++ 中的`this`一样拥有多态性，即其是创建出来的对象

其实这是不对的，这个self应该就是触发这个metamethod的table，不具备什么`多态性`。

