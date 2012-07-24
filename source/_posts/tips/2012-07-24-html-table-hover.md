---
layout: post
title: "HTML中table的高亮以及tooltip"
date: 2012-07-24 16:08
comments: true
categories: [tips, web]
tags: [tips, web, html]
---

在一个需要显示很多数据的表格(table)中，为了更友好地查看一行数据，常常需要在鼠标指针移到某一行时，高亮此行。要实现这个效果有很多方法，这里列举一个方法：

{% highlight javascript %}
{% raw %}
function setTableHover(t) {
  $(t + " tbody tr")
      .mouseover(function() { $(this).addClass("hover");})
      .mouseout(function() { $(this).removeClass("hover"); })
}
{% endraw %}
{% endhighlight %}

主要就是在鼠标移到某一行时，为该行添加一个高亮的css class，鼠标离开时移除该class即可。可以为一个特定的table设定：

<!-- more -->
{% highlight html %}
{% raw %}
<table id="test">
</table>
<script>
    setTableHover('#test')
</script>
{% endraw %}
{% endhighlight %}

甚至可以为将某个页面的所有table设为高亮：

{% highlight html %}
{% raw %}
<script>
    setTableHover('table')
</script>
{% endraw %}
{% endhighlight %}

css里需要编写这个hover：

{% highlight css %}
{% raw %}
.hover {
  background: #e9cffa;
}
{% endraw %}
{% endhighlight %}

<hr/>

除了高亮显示某一行外，可能还需要在鼠标移动到某个单元格时，弹出一个tooltip。这里的tooltip可以是[弹出窗口](http://codemacro.com/2012/07/19/popup-window-in-html/)，也就是一个div元素。

{% highlight html %}
{% raw %}
<tr>
  <td class="tip">
    hello
    <div class='popup' style='display:none;'>this is the tip</div>
  </td>
</tr>
{% endraw %}
{% endhighlight %}

要实现此效果，可以通过修改包含tip class的鼠标事件响应：

{% highlight javascript %}
{% raw %}
$(function () {
    $('.tip').hover(
        function () {
            show_popupex($(this).find("div"), $(this));
        },
        function () {
            $(this).find("div").hide();
        }
        );
});
{% endraw %}
{% endhighlight %}

hover的第一个参数表示鼠标进入的响应，第二个参数表示鼠标离开的响应。show_popupex用于将一个元素以绝对位置显示在指定元素（这里是单元格）附近，可以参看[弹出窗口](http://codemacro.com/2012/07/19/popup-window-in-html/)那篇文章。


