---
layout: post
title: "HTML中实现弹出窗口"
date: 2012-07-19 14:56
comments: true
categories: [tips, web]
tags: [tips, web, html]
---

{% img right /assets/res/popup-window-tip.png %}

做网页时弹出一个窗口显示一些内容是一种很常见的交互方式，如图中用户点击“个人资料“时并不是转到一个新页面，而是在当前页面弹出修改密码的窗口。弹出窗口的实现方式有很多，这里罗列一种。

弹出窗口的内容是作为一个单独的div存在的，这个div可以在页面刚开始载入时不填入内容，而在以后通过json或者直接返回js来填入。其次，弹出窗口的显示位置一般是绝对位置，一方面是不影响页面布局，另一方面也希望其作为一个顶层窗口来呈现，所以需要指定其position css。

{% highlight html %}
<div id='userprofile' class='popup' style="display:none;"></div>
{% endhighlight %}

{% highlight css %}
{% raw %}
.popup {
  position: absolute;
  z-index: 200;
  left: 0px;
  top: 0px;
  border: 1px solid #666;
  background: white;
  padding: 8px 5px 5px;
  margin: 10px 5px;
}
{% endraw %}
{% endhighlight %}

我这里div里的内容是后面填入的，预先填入也可以。当要显示时，就通过js将这个div显示即可。为此我封装了几个js函数。

{% highlight javascript %}
{% raw %}
function show_popupex(pannel, target, manual) {
    var pos = target.position();
    var height = target.outerHeight();
    pannel.css('left', pos.left + 'px');
    pannel.css('top', pos.top + height + 'px');
    pannel.show();
    if (!manual) {
        pannel.mouseleave(function() { pannel.hide(); });
    }
}

function show_popup(pannel_id, target_id, manual) {
    var target = $(target_id);
    var pannel = $(pannel_id);
    show_popupex(pannel, target, manual);
}

function hide_popup(pannel_id) {
    $(pannel_id).hide();
}
{% endraw %}
{% endhighlight %}

show_popup函数主要就是将目标元素的位置做调整，然后显示。通常情况下我只需传入元素的id，manual属性指定弹出窗口是否手动关闭。对于tooltip的实现，则需要让其自动关闭。针对以上例子，使用方式为：

{% highlight js %}
show_popup('#userprofile', '#profile-link', true);
{% endhighlight %}

其中profile-link就是那个“个人资料“链接。

