---
layout: post
title: "Octopress中的SEO"
date: 2012-09-06 19:02
comments: true
categories: tips
tags: [tips, octopress]
keywords: seo, octopress
description: Octopress默认为每个页面添加`meta description`，其内容为当前文章的前150个字符，如果是首页就会是第一篇文章的前150个字符。这里主要通过增加`meta keywords`来提高SEO。
---

来自[SEO for Octopress](http://www.yatishmehta.in/seo-for-octopress)

Octopress默认为每个页面添加`meta description`，其内容为当前文章的前150个字符，如果是首页就会是第一篇文章的前150个字符。这里主要通过增加`meta keywords`来提高SEO。
<!-- more -->
## 为每篇文章增加keywors和description

就像我的这篇博客，这下文章头得填很多数据了，有点麻烦：

{% highlight yaml %}
{% raw %}
---
layout: post
title: "Octopress中的SEO"
date: 2012-09-06 19:02
comments: true
categories: tips
tags: [tips, octopress]
keywords: seo, octopress
description: Octopress默认为每个页面添加`meta description`，其内容为当前文章的前150个字符，如果是首页就会是第一篇文章的前150个字符。这里主要通过增加`meta keywords`来提高SEO。
---
{% endraw %}
{% endhighlight %}

这样，每篇文章页面头就会自动增加`meta keywords`项，`description`也会使用这里填的，而不是自动为文章前若干个字符。这个功能的实现在`_includes/head.html`中。

{% highlight html %}
{% raw %}
<meta name="author" content="Kevin Lynx"> 
<meta name="description" content=" Octopress默认为每个页面添加`meta description`，其内容为当前文章的前150个字符，如果是首页就会是第一篇文章的前150个字符。这里主要通过增加`meta keywords`来提高SEO。 "> 
<meta name="keywords" content="seo, octopress"> 
{% endraw %}
{% endhighlight %}

## 为页面(Page)增加keywords

上面只是修正了每篇博客页面的`meta`信息，octopress中还有几个页面需要修正，例如首页，这个可以通过修改`_includes/head.html`来完成。替换相关内容为以下：

{% highlight html %}
{% raw %}
<meta name="author" content="{{ site.author }}">
{% capture description %}{% if page.description %}{{ page.description }}{% elsif site.description %}{{ site.description }}{%else%}{{ content | raw_content }}{% endif %}{% endcapture %}
<meta name="description" content="{{ description | strip_html | condense_spaces | truncate:150 }}">
{% if page.keywords %}<meta name="keywords" content="{{ page.keywords }}">{%else%}<meta name="keywords" content="{{ site.keywords }}">{% endif %}
{% endraw %}
{% endhighlight %}

如果页面没有提供`keywords`或者`description`的话，就使用`site`里的设置，也就需要修改`_config.yml`：

{% highlight yaml %}
{% raw %}
description: loop in codes, Kevin Lynx blog
keywords: c/c++, mmo, game develop, lisp, ruby, lua, web development
{% endraw %}
{% endhighlight %}
