---
layout: post
title: "为octopress添加分类(category)列表"
date: 2012-07-18 16:10
comments: true
categories: tips
tags: [tips, octopress]
---

参考<http://paz.am/blog/blog/2012/06/25/octopress-category-list-plugin/>。大致步骤为：

**增加category_list插件**

保存以下代码到plugins/category_list_tag.rb：

{% highlight ruby %}
module Jekyll
  class CategoryListTag < Liquid::Tag
    def render(context)
      html = ""
      categories = context.registers[:site].categories.keys
      categories.sort.each do |category|
        posts_in_category = context.registers[:site].categories[category].size
        category_dir = context.registers[:site].config['category_dir']
        category_url = File.join(category_dir, category.gsub(/_|\P{Word}/, '-').gsub(/-{2,}/, '-').downcase)
        html << "<li class='category'><a href='/#{category_url}/'>#{category} (#{posts_in_category})</a></li>\n"
      end
      html
    end
  end
end

Liquid::Template.register_tag('category_list', Jekyll::CategoryListTag)
{% endhighlight %}

这个插件会向liquid注册一个名为category_list的tag，该tag就是以li的形式将站点所有的category组织起来。如果要将category加入到侧边导航栏，需要增加一个aside。

**增加aside**

复制以下代码到source/_includes/asides/category_list.html。

{% highlight ruby %}
{% raw %}
<section>
  <h1>Categories</h1>
  <ul id="categories">
    {% category_list %}
  </ul>
</section>
{% endraw %}
{% endhighlight %}

配置侧边栏需要修改_config.yml文件，修改其default_asides项：

{% highlight ruby %}
default_asides: [asides/category_list.html, asides/recent_posts.html]
{% endhighlight %}

以上asides根据自己的需求调整。


