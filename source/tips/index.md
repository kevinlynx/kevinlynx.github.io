---
layout: page
title: "tips"
sharing: true
footer: false
---

tips收集各种程序方面的小技巧、解决方案、代码段子。主要是我自己总结的，或者从stackoverflow上翻译过来的。其内容一般是我自己最近关注、使用的技术。

<div id="blog-archives">
{% for post in site.categories['tips'] %}
  {% capture this_year %}{{ post.date | date: "%Y" }}{% endcapture %}
  {% unless year == this_year %}
    {% assign year = this_year %}
      <h2>{{ year }}</h2>
  {% endunless %}
  <article>
    {% include archive_post.html %}
  </article>
{% endfor %}
</div>
