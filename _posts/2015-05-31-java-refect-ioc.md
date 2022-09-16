---
layout: post
title: "Java中的反射及Bean容器的实现"
category: java
tags: [refect, bean, ioc]
comments: true
---

编程语言中的反射(Refection)指的是可以在程序运行期动态加载一个类。与之相关的是自省(Introspection)，这个指的是程序自己可以获取一个类型的描述信息，例如获取一个类的所有接口定义、一个接口的所有形参。当编程语言有了这些语言特性之后，可以在很大程度上解决代码耦合问题，所以在Java的世界里，可以看到很多库/框架使用了反射技术。

类似Spring的Bean容器实现就是大量运用了反射机制。Bean容器维护了一些Bean对象，简单来说就是一些普通对象。Bean容器可以根据配置创建这些对象，创建时如果这些对象依赖了其他对象，Bean容器还会负责将依赖的对象注入到目标对象中，也就是所谓的依赖注入(dependence injection)。放在模块设计中，又衍生出控制反转(IoC, Inverse of Control)概念，用于描述应用程序在使用一个框架时，不是框架来控制/限制应用程序的架构模式，而是由应用程序来控制框架。

本文就简单描述下Bean容器是如何使用反射来实现的，最终代码参考[github ioc-sample](https://github.com/kevinlynx/ioc-sample)

## 类的动态加载

可以简单地使用`Class.forName`，传入某个class的完整名：

{% highlight java %}
public Class<?> loadClass(String fullName) throws ClassNotFoundException {
  return Class.forName(fullName);
}
{% endhighlight %}

类的加载涉及到class loader，这块内容是可以进一步深化的。加载了类之后就可以创建出类的实例，但还没有完成依赖注入的功能：

{% highlight java %}
Class<?> c = loadClass("com.codemacro.bean.test.Test1");
Object o = c.newInstance();
{% endhighlight %}
<!-- more -->
## 通过set接口注入

我们的类可以包含`set`接口，用于设置某个成员：

{% highlight java %}
public class Test2 {
  public Test1 test1;
  
  public void setTest1(Test1 t) {
    test1 = t;
  }
}
{% endhighlight %}

那么可以通过`setXXX`接口将`Test1`注入到`Test2`中：

{% highlight java %}
// props指定哪些成员需要注入，例如{"Test1", "test1"}，Test1指的是setTest1，test1指的是bean名字
public Object buildWithSetters(String name, Class<?> c, Map<String, String> props) {
  try {
    // ClassSetMethods 类获取Class<?>中所有setXX这种接口
    ClassSetMethods setMethods = new ClassSetMethods(c);
    Object obj = c.newInstance();
    for (Map.Entry<String, String> entrys : props.entrySet()) {
      String pname = entrys.getKey();
      String beanName = entrys.getValue();
      // 取得setXXX这个Method
      Method m = setMethods.get(pname);
      Object val = getBean(beanName);
      // 调用
      m.invoke(obj, val);
    }
    beans.put(name, obj);
    return obj;
  } catch (Exception e) {
    throw new RuntimeException("build bean failed", e);
  }
}    
{% endhighlight %}

`ClassSetMethod`自省出一个Class中所有的`setXXX(xx)`接口：

{% highlight java %}
public ClassSetMethods(Class<?> c) {
  Method[] methods = c.getMethods();
  for (Method m : methods) {
    String mname = m.getName();
    Class<?>[] ptypes = m.getParameterTypes();
    if (mname.startsWith("set") && ptypes.length == 1 && m.getReturnType() == Void.TYPE) {
      String name = mname.substring("set".length());
      this.methods.put(name, m);
    }
  }
}
{% endhighlight %}

以上就可以看出Java中的自省能力，例如`Class<?>.getMethods`、`Method.getReturnType`、`Method.getParameterTypes`。

## 通过构造函数注入

类似于Spring中的：

    <bean id="exampleBean" class="examples.ExampleBean">
      <constructor-arg type="int" value="2001"/>
      <constructor-arg type="java.lang.String" value="Zara"/>
   </bean>

可以将依赖的Bean通过构造函数参数注入到目标对象中：

{% highlight java %}
List<String> params = new ArrayList<String>();
params.add("test1");
bf.buildWithConstructor("test2", Test2.class, params);
{% endhighlight %}

其实现：

{% highlight java %}
public Object buildWithConstructor(String name, Class<?> c, List<String> beanNames) {
  try {
    Constructor<?>[] ctors = c.getConstructors(); // 取得Class构造函数列表
    assert ctors.length == 1;
    Constructor<?> cc = ctors[0]; 
    Class<?>[] ptypes = cc.getParameterTypes(); // 取得构造函数参数类型列表
    assert ptypes.length == beans.size();
    Object[] args = new Object[ptypes.length];
    for (int i = 0; i < beanNames.size(); ++i) { 
      args[i] = getBean(beanNames.get(i)); // 构造调用构造函数的实参列表
    }
    Object obj = cc.newInstance(args); // 通过构造函数创建对象
    beans.put(name, obj);
    return obj;
  } catch (Exception e) {
    throw new RuntimeException("build bean failed", e);
  }
}
{% endhighlight %}

这个接口的使用约定`beanNames`保存的是bean名称，并与构造函数参数一一对应。

## 通过注解注入

我们可以通过注解标注某个数据成员是需要被自动注入的。我这里简单地获取注解标注的成员类型，找到该类型对应的Bean作为注入对象。当然复杂点还可以指定要注入Bean的名字，或自动查找类型的派生类实现。

一个空的注解即可：

{% highlight java %}
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.FIELD)
public @interface Inject {
}
{% endhighlight %}

实现：

{% highlight java %}

public Object buildWithInject(String name, Class<?> c) {
  try {
    Object obj = c.newInstance();
    Field[] fields = c.getDeclaredFields(); // 获取该类所有定义的成员
    for (Field f :fields) {
      Inject inject = f.getAnnotation(Inject.class); // 获取数据成员的注解
      if (inject != null) { // 如果被Inject注解标注
        Object bean = getBeanByType(f.getType()); // 根据成员的类型找到对应的Bean
        f.set(obj, bean); // 注入
      } else {
        throw new RuntimeException("not found bean " + f.getName());
      }
    }
    beans.put(name, obj);
    return obj;
  } catch (Exception e) {
    throw new RuntimeException("build bean failed", e);
  }
}
{% endhighlight %}

`getBeanByType`就是根据`Class`匹配所有的Bean。使用时：

{% highlight java %}
public class Test2 {
  @Inject
  public Test1 test1;
  ...
}
{% endhighlight %}

完。


