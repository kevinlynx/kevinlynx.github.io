---
layout: post
title: "基于servlet实现一个web框架"
category: java
tags: [servlet]
comments: true
---

servlet作为一个web规范，其本身就算做一个web开发框架，但是其web action (响应某个URI的实现)的实现都是基于类的，不是很方便，并且3.0之前的版本还必须通过web.xml配置来增加新的action。servlet中有一个filter的功能，可以配置所有URI的功能都经过filter。我们可以基于filter的功能来实现一个简单的web框架。在这个框架中，主要改进URI action的映射，就像[play framework](https://www.playframework.com/)中route的配置：

    GET     /hello      com.codemacro.webdemo.test.TestController.hello
    GET     /route      com.codemacro.webdemo.test.TestController.route
    POST    /hello      com.codemacro.webdemo.test.TestController.sayHello

即把某个URI映射到类接口级别。基于servlet实现web框架的好处不仅实现简单，还能运行在所有支持servlet容器规范的web server上，例如Tomcat、Jetty。

本文提到的web framework demo可以从我的github 上取得：[servlet-web-framework-demo](https://github.com/kevinlynx/servlet-web-framework-demo)

## 功能

这个web framework URI action部分（或者说URI routing）如同前面描述，action的编写如：

{% highlight java %}
public class TestController extends BaseController {
  // 返回字符串
  public Result index() {
    return ok("hello world");
  }

  // HTTP 404
  public Result code404() {
    return status(404, "not found");
  }

  // 使用JSP模板渲染
  public Result template() {
    String[] langs = new String[] {"c++", "java", "python"};
    return ok(jsp("index.jsp")
        .put("name", "kevin")
        .put("langs",  langs)
        );
  }
}
{% endhighlight %}
<!-- more -->
有了action之后，配置`route`文件映射URI即可：

    GET /index  com.codemacro.webdemo.test.TestController.index
    GET /404    com.codemacro.webdemo.test.TestController.code404
    GET /index.jsp com.codemacro.webdemo.test.TestController.template

然后配置`web.xml`，增加一个filter：

    <filter>
      <filter-name>MyWebFilter</filter-name>
      <filter-class>com.codemacro.webdemo.MyServletFilter</filter-class>
    </filter>
    <filter-mapping>
      <filter-name>MyWebFilter</filter-name>
      <url-pattern>/*</url-pattern>
    </filter-mapping>

最后以war的形式部署到Jetty `webapps`下即可运行。想想下次要再找个什么lightweight Java web framework，直接用这个demo就够了。接下来讲讲一些关键部分的实现。

## servlet basic

基于servlet开发的话，引入servlet api是必须的：

    <dependency>
        <groupId>javax.servlet</groupId>
        <artifactId>servlet-api</artifactId>
        <version>2.5</version>
        <type>jar</type>
        <scope>compile</scope>
    </dependency>
 
servlet filter的接口包含：

{% highlight java %}
public class MyServletFilter implements Filter {
  // web app启动时调用一次，可用于web框架初始化
  public void init(FilterConfig conf) throws ServletException { }

  // 满足filter url-pattern时就会调用；req/res分别对应HTTP请求和回应
  public void doFilter(ServletRequest req, ServletResponse res,
    FilterChain chain) throws IOException, ServletException { }

  public void destroy() { }
}
{% endhighlight %}

`init`接口可用于启动时载入`routes`配置文件，并建立URI到action的映射。

## action manager

`ActionManager`负责启动时载入`routes`配置，建立URI到action的映射。一个URI包含了HTTP method和URI String，例如`GET /index`。action既然映射到了类接口上，那么可以在启动时就同过Java反射找到对应的类及接口。简单起见，每次收到URI的请求时，就创建这个类对应的对象，然后调用映射的接口即可。

{% highlight java %}
// 例如：registerAction("com.codemacro.webdemo.test.TestController", "index", "/index", "GET");
public void registerAction(String clazName, String methodName, String uri, String method) {
  try {
    uri = "/" + appName + uri;
    // 载入对应的class
    Class<? extends BaseController> clazz = (Class<? extends BaseController>) loadClass(clazName);
    // 取得对应的接口
    Method m = clazz.getMethod(methodName, (Class<?>[])null);
    // 接口要求必须返回Result
    if (m.getReturnType() != Result.class) {
      throw new RuntimeException("action method return type mismatch: " + uri);
    }
    ActionKey k = new ActionKey(uri, getMethod(method));
    ActionValue v = new ActionValue(clazz, m);
    logger.debug("register action {} {} {} {}", clazName, methodName, uri, method);
    // 建立映射
    actions.put(k, v);
  } catch (Exception e) {
    throw new RuntimeException("registerAction failed: " + uri, e);
  }
}
{% endhighlight %}

controller都要求派生于`BaseController`，这样才可以利用`BaseController`更方便地获取请求数据之类，例如query string/cookie 等。

收到请求时，就需要根据请求的HTTP Method和URI string取得之前建立的映射，并调用之：

{% highlight java %}
public boolean invoke(HttpServletRequest req, HttpServletResponse resp) throws IOException {
  String uri = req.getRequestURI();
  String method = req.getMethod().toUpperCase();
  try {
    // 取得之前建立的映射，Map查找
    ActionValue v = getAction(uri, method);
    // 创建新的controller对象
    BaseController ctl = (BaseController) v.clazz.newInstance();
    ctl.init(req, resp, this);
    logger.debug("invoke action {}", uri);
    // 调用绑定的接口
    Result result = (Result) v.method.invoke(ctl, (Object[]) null);
    // 渲染结果
    result.render();
  } catch (Exception e) {
    ...
  }
}
{% endhighlight %}

## 结果渲染

结果渲染无非就是把框架用户返回的结果渲染为字符串，写进`HttpServletResponse`。这个渲染过程可以是直接的`Object.toString`，或者经过模板引擎渲染，或者格式化为JSON。

通过实现具体的`Result`类，可以扩展不同的渲染方式，例如最基础的`Result`就是调用返回对象的`toString`：

{% highlight java %}
public class Result {
  public void render() throws IOException, ServletException {
    PrintWriter writer = response.getWriter();
    // result是controller action里返回的
    writer.append(result.toString());
    writer.close();
  }
}
{% endhighlight %}

为了简单，不引入第三方库，可以直接通过JSP来完成。JSP本身在servlet容器中就会被编译成一个servlet对象。

{% highlight java %}
public class JSPResult extends Result {
  ...
  @Override
  public void render() throws IOException, ServletException {
    // 传入一些对象到模板中
    for (Map.Entry<String, Object> entry : content.entrySet()) {
      request.setAttribute(entry.getKey(), entry.getValue());
    }
    // 委托给JSP来完成渲染
    request.getRequestDispatcher(file).forward(request, response);
  }
}
{% endhighlight %}

JSP中可以使用传统的scriptlets表达式，也可以使用新的EL方式，例如：
    
    <%@ taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
    <h4>By EL</h4>
    <c:forEach var="lang" items="${langs}">
      <span>${lang}</span>|
    </c:forEach>

    <% String[] langs = (String[]) request.getAttribute("langs"); %>
    <% if (langs != null) { %>
    <% for (String lang : langs) { %>
      <span><%= lang %></span>|
    <% } } %>

使用EL的话需要引入`<%@ taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>`


## BaseController

`BaseController`是一种template pattern实现，其包装了一些方便的接口给具体的controller使用，例如：

{% highlight java %}
public class BaseController {
  // 取得/index?name=kevin中的name参数值
  protected String getQueryString(String key) {
    return request.getParameter(key);
  }

  protected Result status(int code, String text) {
    response.setStatus(code);
    return new Result(response, text);
  }

  // 默认是HTTP 200
  protected Result ok(Object obj) {
    return new Result(response, obj);
  }

  protected Result ok(Result result) {
    return result;
  }

  protected JSPResult jsp(String file) {
    return new JSPResult(request, response, file, actionMgr);
  }
}
{% endhighlight %}

## Reverse routing

Reverse routing指的是在开发web过程中，要引入某个URL时，我们不是直接写这个URL字符串，而是写其映射的接口，以使代码更易维护（因为URL可能会随着项目进展而改变）。并且，servlet app部署后URL会带上这个app的名字前缀，例如`/web-demo/index`中的`/web-demo`。在模板文件中，例如要链接到其他URI，更好的方式当然是直接写`/index`。

这里的实现比较丑陋，还是基于字符串的形式，例如：

    <a href='<route:reverse action="com.codemacro.webdemo.test.TestController.hello" name="kevin"/>'>index</a>

通过自定义一个EL function `reverse`来实现。这里需要引入一个JSP的库：

    <dependency>
        <groupId>javax.servlet</groupId>
        <artifactId>jsp-api</artifactId>
        <version>2.0</version>
        <optional>true</optional>
    </dependency>

首先实现一个`SimpleTagSupport`，为了支持`?name=kevin`这种动态参数，还需要`implements DynamicAttributes`：

{% highlight java %}
public class JSPRouteTag extends SimpleTagSupport implements DynamicAttributes {
  @Override
  // 输出最终的URL
  public void doTag() throws IOException {
    JspContext context = getJspContext();
    ActionManager actionMgr = (ActionManager) context.findAttribute(ACTION_MGR);
    JspWriter out = context.getOut();
    String uri = actionMgr.getReverseAction(action, attrMap);
    out.println(uri);
  }

  @Override
  // name="kevin" 时调用
  public void setDynamicAttribute(String uri, String name, Object value) throws JspException {
    attrMap.put(name, value);
  }

  // `action="xxx"` 时会调用`setAction`
  public void setAction(String action) {
    this.action = action;
  }
}
{% endhighlight %}

为了访问到`ActionManager`，这里是通过写到`Request context`中实现的，相当hack。

{% highlight java %}
public JSPResult(HttpServletRequest req, HttpServletResponse resp, String file, 
    ActionManager actionMgr) {
  super(resp, null);
  ..
  put(JSPRouteTag.ACTION_MGR, actionMgr);
}
{% endhighlight %}

第二步增加一个描述这个新tag的文件 `WEB-INF/route_tag.tld`：

    <taglib>
        <tlibversion>1.0</tlibversion>
        <jspversion>1.1</jspversion>
        <shortname>URLRouteTags</shortname>
        <uri>/myweb-router</uri>
        <info></info>

        <tag>
            <name>reverse</name>
            <tagclass>com.codemacro.webdemo.result.JSPRouteTag</tagclass>
            <bodycontent></bodycontent>
            <info></info>
            <attribute>
                <name>action</name>
                <required>true</required>
            </attribute>
            <dynamic-attributes>true</dynamic-attributes>
        </tag>
    </taglib>

最后在需要使用的JSP中引入这个自定义tag：

    <%@ taglib prefix="route" uri="/myweb-router" %>

## 参考资料

* [Servlet生命周期与工作原理](http://www.cnblogs.com/cuiliang/archive/2011/10/21/2220671.html)
* [JSP/Servlet工作原理](http://www.blogjava.net/fancydeepin/archive/2013/09/30/fan_servlet.html)
* [EL表达式](http://www.cnblogs.com/xushuai123/archive/2013/03/24/2979711.html)
* [使用Servlet、JSP开发Web程序](http://www.codedata.com.tw/java/java-tutorial-the-3rd-class-3-servlet-jsp/)
* [Java Web笔记 – Servlet中的Filter过滤器的介绍和使用 编写过滤器](http://www.itzhai.com/java-web-notes-servlet-filters-in-the-filter-writing-the-introduction-and-use-of-filters.html#read-more)
* [实现一个简单的Servlet容器](http://blog.csdn.net/bingduanlbd/article/details/38349737)

