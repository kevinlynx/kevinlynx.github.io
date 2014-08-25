---
layout: post
title: "编写独立的Ruby脚本"
date: 2012-08-07 14:33
comments: true
categories: [tips, ruby]
tags: [tips, ruby]
---

Ruby肯定不仅仅用于编写Rails程序。要使用Ruby编写独立的脚本/程序，就像shell一样，其方式也很简单：

{% highlight ruby %}
#!/usr/bin/env ruby
if ARGV.size == 0 
  puts 'usage: program arg1 arg2'
  exit
end
ARGV.each do |arg| print arg end
{% endhighlight %}

脚本内容没有什么限制，函数、类、模块的组织方式也随意。ARGV是一个特殊的变量，是一个数组，其内保存了传入脚本的参数，不包含程序名。当然，不要忘记给脚本加上可执行权限。

