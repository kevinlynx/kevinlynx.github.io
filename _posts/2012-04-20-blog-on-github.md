---
layout: post
title: "使用Github Page来写博客"
category: other
tags: github jekyll blog
comments: true
---

最开始知道[Github Page](http://pages.github.com/)，是通过[codertrace](http://codertrace.com)上的某些注册用户，他们的BLOG就建立在Github Page上，并且清一色的干净整洁（简陋），这看起来很酷。

Github提供了很多很合coder口味的东西，例如Gist，也包括这里提到的Page。Page并不是特用于建立博客的产品，它仅提供静态页面的显示。它最酷的地方，是通过Git的方式来让你管理这些静态页面。通过建立一个repository，并使用markdown语法来编写文章，然后通过Git来管理这些文章，你就可以自动将其发布出去。
<!-- more -->
当然，要搭建一个像样点的博客，使用Github Page还不太方便。这里可以使用[Jekyll](https://github.com/mojombo/jekyll)。Jekyll是一个静态网页生成器，它可以将你的markdown文件自动输出为对应的网页。而Github Page也支持Jekyll。

为了更方便地搭建博客，我还使用了[Jekyll-bootstrap](http://jekyllbootstrap.com)。jekyll-bootstrap其实就是一些模板文件，提供了一些博客所需的特殊功能，例如评论，访问统计。

基于以上，我就可以像在Github上做项目一样，编写markdown文章，然后git push即可。可以使用jekyll --server在本地开启一个WEB SERVER，然后编写文章时，可以在本地预览。

Github Page还支持custom domain，如你所见，我将我的域名codemacro.com绑定到了Github Page所提供的IP，而不再是我的VPS。你可以通过kevinlynx.github.com或者codemacro.com访问这个博客。

<hr/>

当然实际情况并没有那么简单，例如并没有太多的theme可供选择，虽然jekyll-bootstrap提供了一些，但还是太少。虽然，你甚至可以fork别人的jekyll博客，使用别人定制的theme，但，这对于一个不想过于折腾的人说，门槛也过高了点。

jekyll-bootstrap使用了twitter的bootstrap css引擎，但我并不懂这个，所以，我也只能定制些基本的页面样式。

<hr/>

1年前我编写了[ext-blog](https://github.com/kevinlynx/ext-blog)，并且在我的VPS上开启了codemacro.com这个博客。本来，它是一个ext-blog很好的演示例子，但维护这个博客给我带来诸多不便。例如，每次发布文章我都需要使用更早前用lisp写的cl-writer，我为什么就不愿意去做更多的包装来让cl-writer更好用？这真是一个垃圾软件，虽然它是我写的。另一方面，codemacro.com使用的主题，虽然是我抄的，但依然太丑，并且恶心。

更别说那个消耗我VPS所有内存的lisp解释器，以及那恶心的两位数字乘法的验证码---你能想象别人得有多强烈的留言欲望，才愿意开一个计算器？

<hr/>

说说codertrace.com。我其实写了篇关于codertrace.com的总结，但没有作为博客发布。做这个事情的结果，简单总结来说就是瞎JB折腾没有任何结果。我真的是个苦逼双子男，我每次做件事情都需要巨大的毅力才能让自己专注下去。

整个过程中，收到了些网友的邮件，看到了些评论，虽然不多。邮件/评论中有建议的，也有单纯的交流的，也有单纯鼓励的。我想说的是，thanks guys。

<hr/>

Anyway, try Github Page, save your VPS money :D.

<hr/>
**update**

具体的搭建步骤，其实Github Page以及Jekyll的帮助文档中其实已经有说明。而Jekyll-bootstrap给了更为详细的说明：

* [安装](http://jekyllbootstrap.com/index.html#start-now)
* [发布](http://jekyllbootstrap.com/usage/jekyll-quick-start.html)

其大概步骤，差不多为：

* Github上创建一个repository
* 安装jekyll（这是一个ruby gem），这是为了本地预览
* clone Jekyll-bootstrap到你刚创建的repository
* 在_post目录下创建日志
* 提交日志到Github

