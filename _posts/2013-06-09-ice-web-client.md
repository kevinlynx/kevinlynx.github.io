---
layout: post
title: "使用ActionScript开发Ice Web客户端"
description: ""
categories: [ICE, web]
tags: [ICE, web, Flash, JavaScript, ActionScript]
comments: true
keywords: [ICE, web, Flash, JavaScript, ActionScript]
---

我们目前的项目服务器端使用了[Ice](http://codemacro.com/2013/02/15/ice-overview/)来构建。Ice有一套自己的网络协议，客户端和服务器端可以基于此协议来交互。由于Ice使用Slice这种中间语言来描述服务器和客户端的交互接口，所以它可以做到极大限度地屏蔽网络协议这个细节。也就是说，我们只要借助Ice和Slice，我们可以轻松地编写网络程序。

然后，我们的后端现在需要一个运行在Web浏览器上的客户端。要与Ice做交互，如果使用TCP协议的话，得保证是长连接的。但HTTP是短连接的。而另一方面，我们还需要选择一个Ice支持的和Web相关的语言来做这件事情。如果要在浏览器端直接与Ice服务建立连接，可供选择的语言/平台包括：

* Flash
* Silverlight

因为我之前用erlang简单写了个Ice的客户端库，所以我对Ice底层协议有一定了解，可以不一定使用Ice支持的语言，所以HTML5其实也是个选择。此外，如果在浏览器端使用Applet，Java可能也是个选择。

其实几个月前在这块的技术选择问题上我就做过简单的研究，当时确定的方案是使用Flash。但是，后来人员招聘上遇到了问题，看起来要招一个会ActionScript和前端页面技术的程序员来做我们这种项目，似乎大材小用，成本显高了。

那么，考虑到团队里有现成的Java程序员，而且看起来招一个会用Java写网站的程序员简单又便宜，似乎是排除技术原因的最好选择。但是，如果不在浏览器端直接连接服务器来做交互，而是让Web服务器端来做中转的话，会面临不少问题：

* 浏览器端操作结果的获取问题，说白了就是非实时了，得用Ajax等等技术去模拟实时，代价就是不断轮训，也就是通常说的poll
* Web服务器端需要编写大量代码：对用户操作的映射，结果缓存等等

如果能用Flash包装与服务器交互的部分，而把UI相关的东西留给HTML/JS/CSS去做，那是不是可行一点？如果只是用ActionScript编写与服务器端的交互逻辑代码，我就不需要花时间去系统学习ActionScript，甚至如何用Flash做界面，我甚至不用搞懂这些技术之间的关系。基本上看些Ice for ActionScript的例子代码，就可以完成这件事情。

以下记录一些主要的过程/方法：
<!-- more -->

## ActionScript程序的开发

开发一个嵌入到网页中的FLASH，只需要Flex SDK。SDK里自带了一些编译器相关工具。我不打算使用IDE，因为看起来IDE更复杂。简单的google之后，基本就可以构建出一个Flash文件：

* 构建基本的程序需要一个mxml文件，这个文件里主要用来捕获Flash在页面上初始化完成这个事件，以初始化内部逻辑
* 编写ActionScript源码，看起来其文件、类的组织方式很像Java
* 使用Flex SDK中的mxmlc程序来编译，生成swf文件，例如：

    mxmlc myflexapp.mxml -library-path+=xxx.swc

* 嵌入到网页中，简单的做法可以借助swfobject.js这个库，嵌入的方式：

{% highlight html %}
{% raw %}
  	<script type="text/javascript" src="swfobject.js"></script>
  	<script type="text/javascript">
	  	var flashvars = {};
	  	var params = {};
      params.play = "true";
	  	params.quality = "high";
	  	params.bgcolor = "white";
	  	params.allowscriptaccess = "always";
	  	params.allowfullscreen = "true";
	  	var attributes = {};
	  	attributes.id = "asclient";
	  	attributes.name = "asclient";
	  	attributes.align = "middle";
	  	swfobject.embedSWF("asclient.swf", "flashContent", "1", "1",
	  		"0", "", 
	  		flashvars, params, attributes);
	  	swfobject.createCSS("#flashContent", "display:none;");
	</script>
{% endraw %}
{% endhighlight %}

自然，页面中需加入flashContent这个div：

{% highlight html %}
  	<div id="flashContent">
  		<p>no flash</p>
  	</div>
{% endhighlight %}

我的mxml文件也很简单：

{% highlight xml %}
{% raw %}
<?xml version="1.0" encoding="utf-8"?>
<s:Application 
    xmlns:fx="http://ns.adobe.com/mxml/2009" 
    xmlns:s="library://ns.adobe.com/flex/spark" 
    xmlns:mx="library://ns.adobe.com/flex/mx"
    applicationComplete="doApplicationComplete()" >
    <fx:Script>
    <![CDATA[
       import ASClient.Coordinator;
       import flash.external.ExternalInterface;

       private var _coordinator:Coordinator;

       public function doApplicationComplete():void
       {
            trace("doApplicationComplete");
            _coordinator = new Coordinator();
            _coordinator.reg_methods();
            ExternalInterface.call("as_ready"); 
       } 
     ]]>
    </fx:Script>
</s:Application>
{% endraw %}
{% endhighlight %}

## ActionScript日志

我通过日志来调试ActionScript代码。最简单的方式就是通过trace函数来输出日志。要成功输出日志包含以下步骤：

* 给浏览器安装调试版本的Flash Player
* 日志是输出到用户目录下的，并且需要手动创建日志目录(Administrator替换为用户名)：

        C:\Users\Administrator\AppData\Roaming\Macromedia\Flash Player\Logs

* 用户目录下新建配置文件mm.cfg：

        AS3StaticProfile=0
        AS3Verbose=0
        TraceOutputFileEnable=1 
        TraceOutputBuffered=0
        ErrorReportingEnable=1  
        AS3Trace=0
   
* 编译DEBUG版本的Flash文件，可以修改flex sdk下的flex-config.xml文件，里面增加debug=true配置即可

在开发过程中需要注意浏览器缓存问题，当编译出新的Flash文件后，浏览器即使页面刷新也可能使用的是缓存里的Flash。当然，最重要的，是通过浏览器来访问这个包含了Flash的网页，Web服务器随意。

## Flash Policy文件

在Flash的某个版本后，Flash中如果要向外建立socket连接，是首先要取得目标主机返回的policy文件的。也就是在建立连接前，Flash底层会先向目标主机询问得到一个描述访问权限的文件。

简单来说，目标主机需要在843端口上建立TCP监听，一旦有网络连接，就发送以下内容，内容后需添加0x00用于标示结束。（当然，具体细节还挺多，自行google）

    <cross-domain-policy>
         <allow-access-from domain="*" to-ports="*" />
    </cross-domain-policy>

最开始我使用的是朋友给的现成的Policy服务，虽然我写的Flash可以成功连接我的Ice服务，但始终要等待2秒以上的时间。google Flash Policy相关内容，可以发现确实存在一个延时，但那是因为目标主机没有在843端口服务。后来我自己用erlang写了个Policy服务，延时就没有了。猜测可能是他的Policy服务没有添加0x00作为结束导致。

## ActionScript与JavaScript的交互

既然我使用ActionScript来包装与服务器的交互，那么JavaScript就必然需要和ActionScript通信。这个通信过程也就是在JavaScript中调用ActionScript中的函数，反过来亦然。这个过程很简单：

在JavaScript中调用ActionScript函数：

首先是ActionScript需要注册哪些函数可以被调用：

    ExternalInterface.addCallback("service_loadall", loadAll);
    
通过`ExternalInterface.addCallback`注册的函数，其实是个closure，所以在类中注册自己的成员函数都可以（因为成员函数会使用this，形成了一个closure）。

然后在JavaScript中调用：

{% highlight javascript %}
{% raw %}
    function asObject() {
        // asclient是嵌入Flash时填入的name和(或?)id
        return window.document.asclient;
    }
	var as = asObject();
	as.service_loadall();

{% endraw %}
{% endhighlight %}

在ActionScript中调用JavaScript中调用则更简单，一句话：

    ExternalInterface.call("service_load_done", args);
   
至于在两者之间的函数参数传递，其类型都可以自动映射。但因为我的应用里数据较为复杂，我就将数据转换为JSON格式，在JavaScript这边操作较为简单。

## 页面切换

这里我们需要的Web前端页面，更像是一个管理系统，所以页面切换是很有可能的。问题在于，当出现页面跳转时，Flash对象会重新初始化，新的页面无法使用前一个页面建立好的网络连接（或者能？）。为了解决这个问题，服务器当然可以设计一种重登录机制，方便客户端以一种特殊的方式进入系统，绕过正常的登录环节。但是我们使用了Glacier2这个网关，在这个网关上有针对连接的超时管理，这样反复建立新的连接对资源太浪费了。

综上，我想只能通过前端去规避这个问题。例如，前端开发人员依然可以分开设计很多页面，页面里也可以使用正常的链接。我们编写一些JavaScript代码，将页面里的链接替换成对应的JavaScript代码，动态载入新的页面内容，然后对页面内的部分内容进行替换，从而尽可能让页面设计人员编写正常的网页，同时也解决页面切换问题。

这是个蹩脚的方法，但在我有限的前端知识体系下，似乎也只能这样干了。


