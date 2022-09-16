---
layout: post
title: "浅析静态库链接原理"
category: c/c++
tags: [static library, archive]
comments: true
---

静态库的链接基本上同链接目标文件`.obj/.o`相同，但也有些不同的地方。本文简要描述linux下静态库在链接过程中的一些细节。

## 静态库文件格式

静态库远远不同于动态库，不涉及到符号重定位之类的问题。静态库本质上只是将一堆目标文件进行打包而已。静态库没有标准，不同的linux下都会有些细微的差别。大致的格式[wiki](http://en.wikipedia.org/wiki/Ar_%28Unix%29#File_format_details)上描述的较清楚：

    Global header
    -----------------        +-------------------------------
    File header 1       ---> | File name
    File content 1  |        | File modification timestamp 
    -----------------        | Owner ID
    File header 2            | Group ID
    File content 2           | File mode
    -----------------        | File size in bytes
    ...                      | File magic
                             +-------------------------------

`File header`很多字段都是以ASCII码表示，所以可以用文本编辑器打开。

静态库本质上就是使用`ar`命令打包一堆`.o`文件。我们甚至可以用`ar`随意打包一些文件：

    $ echo 'hello' > a.txt && echo 'world' > b.txt
    $ ar -r test.a a.txt b.txt
    $ cat test.a
    !<arch>
    a.txt/          1410628755  60833 100   100644  6         `
    hello
    b.txt/          1410628755  60833 100   100644  6         `
    world
<!-- more -->

## 链接过程

链接器在链接静态库时，同链接一般的`.o`基本相似。链接过程大致可以归纳下图：

![](/assets/res/link-process.png)

总结为：

* **所有传入链接器的`.o`都会被链接进最终的可执行程序**；链接`.o`时，会将`.o`中的`global symbol`和`unresolved symbol`放入一个临时表
* 如果多个`.o`定义了相同的`global symbol`，那么就会得到多重定义的链接错误
* 如果链接结束了，`unresolved symbol`表不为空，那么就会得到符号未定义的链接错误
* `.a`静态库处理本质上就是处理其中的每一个`.o`，不同的是，如果某个`.o`中没有一个符号属于`unresolved symbol`表，也就是链接器此时怀疑该`.o`没有必要，那么其就会被忽略

可以通过一些代码来展示以上过程。在开发C++程序时，可以利用文件静态变量会先于`main`之前执行做一些可能利于程序结构的事情。如果某个`.o`（包含静态库中打包的`.o`）被链接进程序，那么其文件静态变量就会先于`main`初始化。

{% highlight c++ %}
// test.cpp
#include <stdio.h>

class Test {
public:
    Test() {
        printf("Test ctor\n");
    }
};

static Test s_test;

// lib.cpp
#include <stdio.h>

class Lib {
public:
    Lib() {
        printf("Lib ctor\n");
    }
};

static Lib s_lib;

// main.cpp
#include <stdio.h>

int main() {
    printf("main\n");
    return 0;
}
{% endhighlight %}
    
以上代码`main.cpp`中未引用任何`test.cpp``lib.cpp`中的符号：

    $ g++ -o test test.o lib.o main.o
    $ ./test
    Lib ctor
    Test ctor
    main
   
生成的可执行程序执行如预期，其链接了`test.o``lib.o`。但是如果把`lib.o`以静态库的形式进行链接，情况就不一样了：为了做对比，基于以上的代码再加一个文件，及修改`main.cpp`：

{% highlight c++ %}
// libfn.cpp
int sum(int a, int b) {
    return a + b;
}

// main.cpp
#include <stdio.h>

int main() {
    printf("main\n");
    extern int sum(int, int);
    printf("sum: %d\n", sum(2, 3));
    return 0;
}
{% endhighlight %}

将`libfn.o`和`lib.o`创建为静态库：

    $ ar -r libfn.a libfn.o lib.o
    $ g++ -o test main.o test.o -lfn -L.
    $ ./test
    Test ctor
    main
    sum: 5

因为`lib.o`没有被链接，导致其文件静态变量也未得到初始化。

调整链接顺序，可以进一步检验前面的链接过程：

    # 将libfn.a的链接放在main.o前面

    $ g++ -o test test.o -lfn main.o  -L.
    main.o: In function `main':
    main.cpp:(.text+0x19): undefined reference to `sum(int, int)'
    collect2: ld returned 1 exit status

这个问题遇到得比较多，也有点让人觉得莫名其妙。其原因就在于链接器在链接`libfn.a`的时候，发现`libfn.o`依然没有**被之前链接的`*.o`引用到，也就是没有任何符号在`unresolved symbol table`中**，所以`libfn.o`也被忽略。

## 一些实践

在实际开发中还会遇到一些静态库相关的问题。

### 链接顺序问题

前面的例子已经展示了这个问题。**调整库的链接顺序**可以解决大部分问题，但当静态库之间存在环形依赖时，则无法通过调整顺序来解决。

#### -whole-archive

`-whole-archive`选项告诉链接器把静态库中的所有`.o`都进行链接，针对以上例子：

    $ g++ -o test -L. test.o -Wl,--whole-archive -lfn main.o -Wl,--no-whole-archive
    $ ./test
    Lib ctor
    Test ctor
    main
    sum: 5

连`lib.o`也被链接了进来。*`-Wl`选项告诉gcc将其作为链接器参数传入；之所以在命令行结尾加上`--no-whole-archive`是为了告诉编译器不要链接gcc默认的库*

可以看出这个方法还是有点暴力了。

#### --start-group 

格式为：

    --start-group archives --end-group

位于`--start-group`  `--end-group`中的所有静态库将被反复搜索，而不是默认的只搜索一次，直到不再有新的`unresolved symbol`产生为止。也就是说，出现在这里的`.o`如果发现有`unresolved symbol`，则可能回到之前的静态库中继续搜索。

    $ g++ -o test -L. test.o -Wl,--start-group -lfn main.o -Wl,--end-group
    $ ./test
    Test ctor
    main
    sum: 5

查看`ldd`关于该参数的man page还可以一窥链接过程的细节：

> The specified archives are searched repeatedly until no new undefined references are created. Normally, an archive is searched only once in the order that it is specified on the command line. If a symbol in that archive is needed to resolve an undefined symbol referred to by an object in an archive that appears later on the command line, the linker would not be able to resolve that reference. By grouping the archives, they all be searched repeatedly until all possible references are resolved.

### 嵌套静态库

由于`ar`创建静态库时本质上只是对文件进行打包，所以甚至可以创建一个嵌套的静态库，从而测试链接器是否会递归处理静态库中的`.o`：

    $ ar -r libfn.a libfn.o
    $ ar -r liboutfn.a libfn.a lib.o
    $ g++ -o test -L. test.o main.o -loutfn
    main.o: In function `main':
    main.cpp:(.text+0x19): undefined reference to `sum(int, int)'
    collect2: ld returned 1 exit status

**可见链接器并不会递归处理静态库中的文件**

之所以要提到嵌套静态库这个问题，是因为我发现很多时候我们喜欢为一个静态库工程链接其他静态库。当然，这里的链接并非真正的链接（仅是打包），这个过程当然可以聪明到将其他静态库里的`.o`提取出来然后打包到新的静态库。

如果我们使用的是类似[scons](http://www.scons.org/)这种封装更高的依赖项管理工具，那么它是否会这样干呢？

基于之前的例子，我们使用scons来创建`liboutfn.a`：

    # Sconstruct
    StaticLibrary('liboutfn.a', ['libfn.a', 'lib.o'])

使用文本编辑器打开`liboutfn.a`就可以看到其内容，或者使用：

    $ ar -tv liboutfn.a
    rw-r--r-- 60833/100   1474 Sep 14 02:59 2014 libfn.a
    rw-r--r-- 60833/100   2448 Sep 14 02:16 2014 lib.o

可见scons也只是单纯地打包。**所以，在scons中构建一个静态库时，再`链接`其他静态库是没有意义的**


## 参考文档

* [ar (Unix)](http://en.wikipedia.org/wiki/Ar_%28Unix%29#File_format_details)
* [ld man page](http://linux.die.net/man/1/ld)
* [GNU ld初探](http://wen00072-blog.logdown.com/posts/188339-study-on-the-gnu-ld)
* [Library order in static linking](http://eli.thegreenplace.net/2013/07/09/library-order-in-static-linking/)
* [Linkers and Loaders](http://www.linuxjournal.com/article/6463?page=0,1)
* [scons Building and Linking with Libraries](http://www.scons.org/doc/0.96.1/HTML/scons-user/c549.html)


