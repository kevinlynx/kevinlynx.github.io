---
layout: post
title: "Ruby应用几则（解析HTML、XMLRPC）"
date: 2012-08-09 14:26
comments: true
categories: [tips, ruby]
tags: [tips, ruby, nokogiri]
---

### Ruby解析HTML

Ruby解析HTML（或XML）可以使用[nokogiri](http://nokogiri.org/)。我的应用里需要查找HTML页面里的某个元素，结果发现实现方式非常简单，就像使用jquery一样。例如我要获取到octopress博客文章里的文章内容、文章标题、文章分类，就像这篇博客：

{% highlight ruby %}
{% raw %}
# get post title and content for an octopress post
def post_info(url)
  doc = Nokogiri::HTML(open(url))
  content = doc.css('div.entry-content').to_s
  title = doc.css('header h1.entry-title').inner_html
  categories = doc.css('a.category').collect do |link| link.content end
  return title, content, categories
end
{% endraw %}
{% endhighlight %}
<!-- more -->
最关键就是`doc.css('div.entry-content')`。想起以前用lisp写的那个版本，还手工遍历了整个HTML页面，实在太落后了。上面这个函数的作用就是取得一篇博文的HTML页面，然后返回该博文的内容、标题和分类。

### Ruby调用xml-rpc

可以使用`rails-xmlrpc`这个库，直接使用gem安装：`gem install rails-xmlrpc`。这个库分为客户端和服务器两部分，我的应用是使用metaweblog API：

{% highlight ruby %}
{% raw %}
class MetaWeblogClient < XMLRPC::Client
  def initialize(username, password, host, url)
    super(host, url)
    @username = username
    @password = password
  end

  def newPost(post, publish)
    call("metaWeblog.newPost", "0", "#{@username}", "#{@password}", post, publish)
  end

  # other methods

end

def new_post(api, url)
  title, content, categories = post_info(url)
  if title.nil? or content.nil?
    puts "get post info failed at #{url}\n"
    return
  end
  post = { :title => title, :description => content, :categories => categories }
  api.newPost(post, true)
  puts "new post #{title} in #{categories} done\n"
end

api = MetaweblogClient.new(username, password, host, url)
new_post(api, "http://codemacro.com/2012/08/07/write-standalone-ruby-script/")

{% endraw %}
{% endhighlight %}

### Ruby读取yaml

就像Rails里那些配置文件一样，都属于yaml配置文件。我的应用里只需使用简单的key-value形式的yaml配置，就像：

{% highlight ruby %}
host: www.cppblog.com
url: /kevinlynx/services/metaweblog.aspx
username: kevinlynx
password: xxxxxx
{% endhighlight %}

解析的时候需要使用`yaml`库：

{% highlight ruby %}
file = File.open(filename)
cfg = YAML::load(file)
{% endhighlight %}

针对以上配置，`YAML::load`得到的结果就是一个hash表：

{% highlight ruby %}
{% raw %}
puts cfg["host"]
puts cfg["url"]
{% endraw %}
{% endhighlight %}

以上，我写了一个小工具，可以让我每次在[codemacro.com](http://codemacro.com)发表博客后，使用这个工具自动解析生成的文章，然后发表到CPPBLOG上。完整源码可在这个上：<https://gist.github.com/3301662>
