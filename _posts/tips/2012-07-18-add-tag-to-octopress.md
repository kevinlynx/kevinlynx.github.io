---
layout: post
title: "为octopress添加tag cloud"
date: 2012-07-18 16:37
comments: true
categories: tips
tags: [tips, octopress]
---

同添加category list一样，网络上有很多方法，这里列举一种。首先到<https://github.com/robbyedwards/octopress-tag-pages>和<https://github.com/robbyedwards/octopress-tag-cloud>clone这两个项目的代码。这两个项目分别用于产生tag page和tag cloud。 针对这两个插件，需要手工复制一些文件到你的octopress目录。

**octopress-tag-pages**

复制tag_generator.rb到/plugins目录；复制tag_index.html到/source/\_layouts目录。**需要注意的是，还需要复制tag_feed.xml到/source/\_includes/custom/目录。**这个官方文档里没提到，在我机器上rake generate时报错。其他文件就不需要复制了，都是些例子。

<!-- more -->
**octopress-tag-cloud**

仅复制tag_cloud.rb到/plugins目录即可。但这仅仅只是为liquid添加了一个tag（非本文所提tag）。如果要在侧边导航里添加一个tag cloud，我们还需要手动添加aside。

复制以下代码到/source/\_includes/custom/asides/tags.html。

{% highlight ruby %}
{% raw %}
<section>
  <h1>Tags</h1>
  <ul class="tag-cloud">
    {% tag_cloud font-size: 90-210%, limit: 10, style: para %}
  </ul>
</section>
{% endraw %}
{% endhighlight %}

tag_cloud的参数中，style :para指定不使用li来分割，limit限定10个tag，font-size指定tag的大小范围，具体参数参看官方文档。

最后，当然是在_config.xml的default_asides 中添加这个tag cloud到导航栏，例如：

{% highlight ruby %}
default_asides: [asides/category_list.html, asides/recent_posts.html, custom/asides/tags.html]
{% endhighlight %}

