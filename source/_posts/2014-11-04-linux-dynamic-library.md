---
layout: post
title: "linux动态库的种种要点"
category: c/c++
tags: dynamic library
comments: true
---

linux下使用动态库，基本用起来还是很容易。但如果我们的程序中大量使用动态库来实现各种框架/插件，那么就会遇到一些坑，掌握这些坑才有利于程序更稳健地运行。

本篇先谈谈动态库符号方面的问题。

测试代码可以在[github上找到](https://github.com/kevinlynx/test/tree/master/dytest)

## 符号查找

一个应用程序`test`会链接一个动态库`libdy.so`，如果一个符号，例如函数`callfn`定义于libdy.so中，test要使用该函数，简单地声明即可：

{% highlight c++ %}
// dy.cpp libdy.so
void callfn() {
    ...
}

// main.cpp test
extern void callfn();

callfn();    
{% endhighlight %}

在链接test的时候，链接器会统一进行检查。

同样，在libdy.so中有相同的规则，它可以使用一个外部的符号，**在它被链接/载入进一个可执行程序时才会进行符号存在与否的检查**。这个符号甚至可以定义在test中，形成一种双向依赖，或定义在其他动态库中：
<!-- more -->
{% highlight c++ %}
// dy.cpp libdy.so
extern void mfunc();

mfunc();

// main.cpp test
void mfunc() {
    ...
}
{% endhighlight %}

在生成libdy.so时`mfunc`可以找不到，此时`mfunc`为未定义：

    $ nm libdy.so | grep mfun
    U _Z5mfuncv

但在libdy.so被链接进test时则会进行检查，试着把`mfunc`函数的定义去掉，就会得到一个链接错误：

    ./libdy.so: undefined reference to `mfunc()'

同样，如果我们动态载入libdy.so，此时当然可以链接通过，但是在载入时同样得到找不到符号的错误：

{% highlight c++ %}
#ifdef DY_LOAD
    void *dp = dlopen("./libdy.so", RTLD_LAZY);
    typedef void (*callfn)();
    callfn f = (callfn) dlsym(dp, "callfn");
    f();
    dlclose(dp);
#else
    callfn();
#endif
{% endhighlight %}

得到错误：

    ./test: symbol lookup error: ./libdy.so: undefined symbol: _Z5mfuncv

**结论：**基于以上，我们知道，如果一个动态库依赖了一些外部符号，这些外部符号可以位于其他动态库甚至应用程序中。我们可以再链接这个动态库的时候就把依赖的其他库也链接上，或者推迟到链接应用程序时再链接。而动态加载的库，则要保证在加载该库时，进程中加载的其他动态库里已经存在该符号。

例如，通过`LD_PRELOAD`环境变量可以让一个进程先加载指定的动态库，上面那个动态加载启动失败的例子，可以通过预先加载包含`mfunc`符号的动态库解决：

    $ LD_PRELOAD=libmfun.so ./test
    ...

但是如果这个符号存在于可执行程序中则不行：

    $ nm test | grep mfunc
    0000000000400a00 T _Z5mfuncv
    $ nm test | grep mfunc
    0000000000400a00 T _Z5mfuncv
    $ ./test
    ...
    ./test: symbol lookup error: ./libdy.so: undefined symbol: _Z5mfuncv
    

## 符号覆盖

前面主要讲的是符号缺少的情况，如果同一个符号存在多分，则更能引发问题。这里谈到的符号都是全局符号，一个进程中某个全局符号始终是全局唯一的。为了保证这一点，在链接或动态载入动态库时，就会出现忽略重复符号的情况。

*这里就不提同一个链接单位（如可执行程序、动态库）里符号重复的问题了*

### 函数

当动态库和libdy.so可执行程序test中包含同名的函数时会怎样？根据是否动态加载情况还有所不同。

当直接链接动态库时，libdy.so和test都会链接包含`func`函数的fun.o，为了区分，我把`func`按照条件编译得到不同的版本：

{% highlight c++ %}
// fun.cpp
#ifdef V2
extern "C" void func() {
    printf("func v2\n");
}
#else
extern "C" void func() {
    printf("func v1\n");
}
#endif

// Makefile
test: libdy obj.o mainfn
    g++ -g -Wall -c fun.cpp -o fun.o # 编译为fun.o
    g++ -g -Wall -c main.cpp #-DDY_LOAD
    g++ -g -Wall -o test main.o obj.o fun.o -ldl mfun.o -ldy -L.

libdy: obj
    g++ -Wall -fPIC -c fun.cpp -DV2 -o fun-dy.o  # 定义V2宏，编译为fun-dy.o
    g++ -Wall -fPIC -shared -o libdy.so dy.cpp -g obj.o fun-dy.o
{% endhighlight %}

这样，test中的`func`就会输出`func v1`；libdy.so中的`func`就会输出`func v2`。test和libdy.o确实都有`func`符号：

    $ nm libdy.so | grep func
    0000000000000a60 T func

    $nm test | grep func
    0000000000400a80 T func

在test和libdy.so中都会调用`func`函数：

{% highlight c++ %}
// main.cpp test
int main(int argc, char **argv) {
    func();
    ...
    callfn(); // 调用libdy.so中的函数
    ...
}

// dy.cpp libdy.so
extern "C" void callfn() {
    ... 
    printf("callfn\n");
    func();
    ...
}
{% endhighlight %}

运行后发现，都**调用的是同一个`func`**：

    $ ./test
    ...
    func v1
    ...
    callfn
    func v1
    
**结论**，直接链接动态库时，整个程序运行的时候符号会发生覆盖，只有一个符号被使用。**在实践中**，如果程序和链接的动态库都依赖了一个静态库，而后他们链接的这个静态库版本不同，则很有可能因为符号发生了覆盖而导致问题。(静态库同普通的.o性质一样，参考[浅析静态库链接原理](http://codemacro.com/2014/09/15/inside-static-library/))

更复杂的情况中，多个动态库和程序都有相同的符号，情况也是一样，会发生符号覆盖。如果程序里没有这个符号，而多个动态库里有相同的符号，也会覆盖。

但是对于动态载入的情况则不同，同样的libdy.so我们在test中不链接，而是动态载入：

{% highlight c++ %}
int main(int argc, char **argv) {
    func();
#ifdef DY_LOAD
    void *dp = dlopen("./libdy.so", RTLD_LAZY);
    typedef void (*callfn)();
    callfn f = (callfn) dlsym(dp, "callfn");
    f();
    func();
    dlclose(dp);
#else
    callfn();
#endif
    return 0;
}
{% endhighlight %}
    
运行得到：

    $ ./test
    func v1
    ...
    callfn
    func v2
    func v1

都正确地调用到各自链接的`func`。

**结论**，实践中，动态载入的动态库一般会作为插件使用，那么其同程序链接不同版本的静态库（相同符号不同实现），是没有问题的。


### 变量

变量本质上也是符号(symbol)，但其处理规则和函数还有点不一样(*是不是有点想吐槽了*)。

{% highlight c++ %}
// object.h
class Object {
public:
    Object() {
#ifdef DF
        s = malloc(32);
        printf("s addr %p\n", s);
#endif
        printf("ctor %p\n", this);
    }

    ~Object() {
        printf("dtor %p\n", this);
#ifdef DF
        printf("s addr %p\n", s);
        free(s);
#endif
    }

    void *s;
};

extern Object g_obj;
{% endhighlight %}

    
我们的程序test和动态库libdy.so都会链接object.o。首先测试test链接libdy.so，test和libdy.so中都会有`g_obj`这个符号：

    // B g_obj 表示g_obj位于BSS段，未初始化段

    $ nm test | grep g_obj
    0000000000400a14 t _GLOBAL__I_g_obj
    00000000006012c8 B g_obj
    $ nm libdy.so | grep g_obj
    000000000000097c t _GLOBAL__I_g_obj
    0000000000200f30 B g_obj

运行：

    $ ./test
    ctor 0x6012c8
    ctor 0x6012c8
    ...
    dtor 0x6012c8
    dtor 0x6012c8

**`g_obj`被构造了两次，但地址一样**。全局变量只有一个实例，似乎在情理之中。

动态载入libdy.so，变量地址还是相同的：

    $ ./test
    ctor 0x6012a8
    ...
    ctor 0x6012a8
    ...
    dtor 0x6012a8
    dtor 0x6012a8

**结论**，不同于函数，全局变量符号重复时，不论动态库是动态载入还是直接链接，变量始终只有一个。

但诡异的情况是，对象被构造和析构了两次。构造两次倒无所谓，浪费点空间，但是析构两次就有问题。因为析构时都操作的是同一个对象，那么如果这个对象内部有分配的内存，那就会对这块内存造成double free，因为指针相同。打开`DF`宏实验下：

    $ ./test
    s addr 0x20de010
    ctor 0x6012b8
    s addr 0x20de040
    ctor 0x6012b8
    ...
    dtor 0x6012b8
    s addr 0x20de040
    dtor 0x6012b8
    s addr 0x20de040

因为析构的两次都是同一个对象，所以其成员`s`指向的内存被释放了两次，从而产生了double free，让程序coredump了。

**总结**，全局变量符号重复时，始终会只使用一个，并且会被初始化/释放两次，是一种较危险的情况，应当避免在使用动态库的过程中使用全局变量。


*完*


