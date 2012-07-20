---
layout: post
title: "Rails中获取客户端时区"
date: 2012-07-20 16:42
comments: true
categories: [tips, web]
tags: [tips, rails]
published: true
---

开发网站功能时，有时候需要获取客户端（浏览器）所在的时区，然后根据不同的时区做一些不同的逻辑功能。这里提供一种方法，其思路为客户端通过js获取时区，然后发送给服务器，服务器存储时区到session中。

{% highlight javascript %}
{% raw %}
function submit_timezone(url) {
  $.get(url, {'offset_min' : (-1 * (new Date()).getTimezoneOffset())});
}

$(document).ready(function() {
    submit_timezone('<%= sys_timezone_path %>');
});
{% endraw %}
{% endhighlight %}

<!-- more -->
sys_timezone_path是一个特地用来处理时区的route。其实主要需要的是offset_min这个请求参数，你可以把这个参数附加到其他请求里。

然后根据offset_min获取到时区名：

{% highlight ruby %}
def timezone
  offset_sec = params[:offset_min].to_i * 60
  zone = ActiveSupport::TimeZone[offset_sec]
  zone = ActiveSupport::TimeZone["UTC"] unless zone
  session[:zone_name] = zone.name if zone
  respond_to do |format|
    format.js
  end
end
{% endhighlight %}

以上，获取到时区名后存储到session[:zone_name]里。在之后处理这个客户端的请求时，就可以通过这个时区名取得对应的时区，例如：

{% highlight ruby %}
zone_name = session[:zone_name] 
zone = ActiveSupport::TimeZone[zone_name] if zone_name
{% endhighlight %}

但经过我实际测试，部署在heroku上的应用偶尔会发现session[:zone_name]取出来是nil，尽管我确认了timezone函数是被调用过的。这难道跟session的超时有关？后来我只好将timezone name写到客户端页面中，然后在其他请求中再把这个时区名发回来。


