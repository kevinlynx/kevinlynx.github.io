---
layout: post
title: "为octopress每篇文章添加一个文章信息"
date: 2012-07-26 14:27
comments: true
categories: [tips, other]
tags: [tips, octopress, blog]
---

当你的博客文章被转载时，你肯定希望转载者能添加一个原始地址。或者你的文章被各种RSS抓取器抓取时，你也希望能在明显的位置显示这个原始地址。使用octopress写博客时，可以通过插件来做这件事。最开始，我只是想单纯地添加这个“原始地址“，一番google未能找到现成的插件，所以只好动手。

话说编写octopress真不是件容易事，因为我实在没找到编写插件的文档。octopress基于jekyll，jekyll又使用了liquid。最后我把这几个项目的文档都翻了下，也仅仅看到几个代码示例，而且liquid的API页面居然出错。无奈之下只好多翻了些现有插件的代码，摸索着来写。写octopress的插件，主要分为generator/tag/filter几种。tag很好理解，就是在文章中插入一个插件注册的tag，然后生成页面时就会调用到对应的插件。filter大概就是把文章内容过滤一遍转换成其他内容输出。
<!-- more -->
后来发现了一篇文章[\<给中英文间加个空格\>](http://xoyo.name/2012/04/auto-spacing-for-octopress/)，这人写的插件从流程上大致是我需要的，模仿如下：

{% highlight ruby %}
{% raw %}
#
# post_footer_filter.rb
# Append every post some footer infomation like original url 
# Kevin Lynx
# 7.26.2012
#
require './plugins/post_filters'

module AppendFooterFilter
  def append(post)
     author = post.site.config['author']
     url = post.site.config['url']
     pre = post.site.config['original_url_pre']
     post.content + %Q[<p class='post-footer'>
            #{pre or "original link:"}
            <a href='#{post.full_url}'>#{post.full_url}</a><br/>
            &nbsp;written by <a href='#{url}'>#{author}</a>
            &nbsp;posted at <a href='#{url}'>#{url}</a>
            </p>]
  end 
end

module Jekyll
  class AppendFooter < PostFilter
    include AppendFooterFilter
    def pre_render(post)
      post.content = append(post) if post.is_post?
    end
  end
end

Liquid::Template.register_filter AppendFooterFilter
{% endraw %}
{% endhighlight %}

大概就是当传入的页面是post时，就添加页脚信息，我这里主要添加了原始地址和作者信息，并且留了个post-footer作为这个段落的样式定制。附加的信息对于RSS输出同样有效。

这个插件的使用方式很简单，直接放到plugins目录下即可。可以在_config.yml中配置下origional_url_pre，例如配置为“原始地址：“。


