---
layout: post
title: "Java中隔离容器的实现"
category: java
tags: class loader
comments: true
---

Java中隔离容器用于隔离各个依赖库环境，解决Jar包冲突问题。

## 问题

应用App依赖库LibA和LibB，而LibA和LibB又同时依赖LibBase，而LibA和LibB都是其他团队开发的，其中LibA发布了一个重要的修复版本，但是依赖LibBase v2.0，而LibB还没有升级版本，LibBase还不是兼容的，那么此时升级就会面临困难。在生产环境中这种情况往往更恶劣，可能是好几层的间接依赖关系。

隔离容器用于解决这种问题。它把LibA和LibB的环境完全隔离开来，LibBase即使类名完全相同也不互相冲突，使得LibA和LibB的升级互不影响。众所周知，Java中判定两个类是否相同，看的是类名和其对应的class loader，两者同时相同才表示相等。隔离容器正是利用这种特性实现的。

## KContainer

这里我实现了一个demo，称为KContainer，源码见[github kcontainer](https://github.com/kevinlynx/kcontainer)。这个container模仿了一些OSGI的东西，这里把LibA和LibB看成是两个bundle，bundle之间是互相隔离的，每个bundle有自己所依赖的第三方库，bundle之间的第三方库完全对外隐藏。bundle可以导出一些类给其他bundle用，bundle可以开启自己的服务。由于是个demo，我只实现关键的部分。

KContainer的目录结构类似：

```
.
|-- bundle
    |-- test1
        |-- test1.prop
        |-- classes
        |-- lib
            |-- a.jar
            |-- b.jar
    |-- test2
        |-- test2.prop
        |-- classes
|-- lib
    |-- kcontainer.jar
    |-- kcontainer.interface.jar
```

bundle目录存放了所有会被自动载入的bundle。每一个bundle都有一个配置文件`bundle-name.prop`，用于描述自己导出哪些类，例如：

```
init=com.codemacro.test.B
export-class=com.codemacro.test.Export; com.codemacro.test.Export2
```

`init`指定bundle启动时需要调用的类，用户可以在这个类里开启自己的服务；`export-class`描述需要导出的类列表。bundle之间的所有类都是隔离的，但`export-class`会被统一放置，作为所有bundle共享的类。后面会描述KContainer如何处理类加载问题，这也是隔离容器的主要内容。
<!-- more -->
bundle依赖的类可以直接以`*.class`文件存放到`classes`目录，也可以作为`*.jar`放到`lib`目录。作为extra pratice，我还会把`*.jar`中的jar解压同时作为类加载的路径。

KContainer本身可以作为一个framework被使用。为了示例，我写了一个入口类，加载启动完所有bundle后就退出了，这个仅作为例子，用不了生产。

## 隔离的核心实现

隔离的目的是分开各个bundle中的类。利用的语言特性包括：

* class的区分由class name和载入其的class loader共同决定
* 当在class A中使用了class B时，JVM默认会用class A的class loader去加载class B
* class loader中的双亲委托机制
* `URLClassLoader`会从指定的目录及*.jar中加载类

KContainer的主要任务，就是为bundle实现一个自定义的class loader。

当KContainer加载一个bundle时，在处理其`export-class`或`init`时，都是需要加载bundle中的类的。在这之前，我给每一个bundle关联一个独立的`BundleClassLoader`。然后用这个class loader去加载bundle中的类，利用class loader传递特性，使得一个bundle中的所有类都是由其关联的class loader加载的，从而实现bundle之间类隔离效果。

实现class loader时，是实现`loadClass`还是`findClass`？通过实现`loadClass`我们可以改变class loader的双亲委托模式，制定加载类的具体顺序。但我的目的仅仅是隔离bundle，想了下其实实现`findClass`就可以达成目的。关于`loadClass`和`findClass`的区别可以参考这里 ([实现自己的类加载时，重写方法loadClass与findClass的区别](http://blog.csdn.net/fenglibing/article/details/17471659))。简单来说，就是`findClass`只有在类确实找不到的情况下才会被调用，在此之前，`loadClass`默认都是走的双亲委托模式。

`BundleClassLoader`派生于`URLClassLoader`，默认的parent class loader就是`system class loader` (`app class loader`)。这使得KContainer中的bundle类加载有三层选择：自己的class path；其他bundle共享的classes；jvm的class path。通过实现`findClass`，在默认路径都无法加载到类时，才尝试bundle共享的class，优先级最低。

其实现大概为：

{% highlight java %}
public class BundleClassLoader extends URLClassLoader {
  public BundleClassLoader(File home, SharedClassList sharedClasses) {
    // getClassPath将bundle目录下的classes和各个jar作为class path传给URLClassLoader
    super(getClassPath(home)); 
    this.sharedClasses = sharedClasses;
  }

  @Override
  protected Class<?> findClass(String name) throws ClassNotFoundException {
    logger.debug("try find class {}", name);
    Class<?> claz = null;
    try {
      claz = super.findClass(name);
    } catch (ClassNotFoundException e) {
      claz = null;
    }
    if (claz != null) {
      logger.debug("load from class path for {}", name);
      return claz;
    }
    claz = sharedClasses.get(name);
    if (claz != null) {
      logger.debug("load from shared class for {}", name);
      return claz;
    }
    logger.warn("not found class {}", name);
    throw new ClassNotFoundException(name);
  }
}
{% endhighlight %}
完整代码参看[BundleClassLoader.java](https://github.com/kevinlynx/kcontainer/blob/master/kcontainer/src/main/java/com/codemacro/container/BundleClassLoader.java)

创建bundle时，会为其创建自己的class loader，并使用这个class loader来载入`export-class`和`init-class`：

{% highlight java %}
  public static Bundle create(File home, String name, SharedClassList sharedClasses, 
      BundleConf conf) {
    BundleClassLoader loader = new BundleClassLoader(home, sharedClasses);
    List<String> exports = conf.getExportClassNames();
    if (exports != null) {
      logger.info("load exported classes for {}", name);
      loadExports(loader, sharedClasses, exports);
    }
    return new Bundle(name, conf.getInitClassName(), loader);
  }
  
  private static void loadExports(ClassLoader loader, SharedClassList sharedClasses,
      List<String> exports) {
      for (String claz_name: exports) {
        try {
          Class<?> claz = loader.loadClass(claz_name); // 载入class
          sharedClasses.put(claz_name, claz);
        } catch (ClassNotFoundException e) {
          logger.warn("load class {} failed", claz_name);
        }
      }
  }
{% endhighlight %}

以上。

## 扩展

扩展的地方有很多，例如支持导出package，导出一个完整的jar。当然可能需要实现`loadClass`，以改变类加载的优先级，让共享类的优先级高于jvm class path的优先级。

## 其他

### 线程ContextClassLoader

提到class loader，我们看下最常接触的几类：

* `XX.class.getClassLoader`，获取加载类`XX`的class loader
* `Thread.currentThread().getContextClassLoader()`，获取当前线程的ContextClassLoader
* `ClassLoader.getSystemClassLoader()`，获取system class loader

system class loader的parent就是ext class loader，再上面就是bootstrap class loader了 (不是java类，实际获取不到)。默认情况下以上三个class loader都是一个：

{% highlight java %}
System.out.println(ClassLoader.getSystemClassLoader());
System.out.println(Main.class.getClassLoader());
System.out.println(Thread.currentThread().getContextClassLoader());
{% endhighlight %}

Output:

```
sun.misc.Launcher$AppClassLoader@157c2bd
sun.misc.Launcher$AppClassLoader@157c2bd
sun.misc.Launcher$AppClassLoader@157c2bd
```

创建线程时，新的线程ContextClassLoader就是父线程的ContextClassLoader。在载入一个新的class时，推荐优先使用线程context class loader，例如框架[Jodd](http://jodd.org/)中包装的。关于线程context class loader和`Class.getClassLoader`这里有个解释算是相对合理：[ContextClassLoader浅析](http://www.xcoder.cn/html/web/j2ee/2013/0506/5557.html)

即，当你把一个对象A传递到另一个线程中，这个线程由对象B创建，A/B两个对象对应的类关联的class loader不同，在B的线程中调用A.some_method，some_method加载资源或类时，如果使用了`Class.getClassLoader`或`Class.forName`时，实际使用的是A的class loader，而这个行为可能不是预期的。这个时候就需要将代码改为`Thread.currentThread().getContextClassLoader()`。

完。


