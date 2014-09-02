---
layout: post
title: "C/C++中手动获取调用堆栈"
category: c/c++
tags: [stack frame]
comments: true
---

当我们的程序core掉之后，如果能获取到core时的函数调用堆栈将非常有利于定位问题。在Windows下可以使用[SEH机制](http://blog.csdn.net/starlee/article/details/6630816)；在Linux下通过gdb使用coredump文件即可。

但有时候由于某些错误导致堆栈被破坏，发生拿不到调用堆栈的情况。

一些基础预备知识本文不再详述，可以参考以下文章：

* [函数调用栈的获取原理分析](http://hutaow.com/blog/2013/10/15/dump-stack/)
* [寄存器、函数调用与栈帧](http://www.findfunaax.com/notes/file/262)

需要知道的信息：

* 函数调用对应的`call`指令本质上是先压入下一条指令的地址到堆栈，然后跳转到目标函数地址
* 函数返回指令`ret`则是从堆栈取出一个地址，然后跳转到该地址
* EBP寄存器始终指向当前执行函数相关信息（局部变量）所在栈中的位置，ESP则始终指向栈顶
* 每一个函数入口都会保存调用者的EBP值，在出口处都会重设EBP值，从而实现函数调用的现场保存及现场恢复
* 64位机器增加了不少寄存器，从而使得函数调用的参数大部分时候可以通过寄存器传递；同时寄存器名字发生改变，例如EBP变为RBP

在函数调用中堆栈的情况可用下图说明：
<!-- more -->
![](/assets/res/stack_frame/stack_frame.png)

将代码对应起来：

{% highlight c++ %}
    void g() {
        int *p = 0;
        long a = 0x1234;
        printf("%p %x\n", &a, a);
        printf("%p %x\n", &p, p);
        f();
        *p = 1;
    }

    void b(int argc, char **argv) {
        printf("%p %p\n", &argc, &argv);
        g();
    }

    int main(int argc, char **argv) {
        b(argc, argv);
        return 0;
    }
{% endhighlight %}

在函数`g()`中断点，看看堆栈中的内容(64位机器)：

    (gdb) p $rbp
    $2 = (void *) 0x7fffffffe370
    (gdb) p &p
    $3 = (int **) 0x7fffffffe368
    (gdb) p $rsp
    $4 = (void *) 0x7fffffffe360
    (gdb) x/8ag $rbp-16
    0x7fffffffe360: 0x1234  0x0
    0x7fffffffe370: 0x7fffffffe390  0x400631 <b(int, char**)+43>
    0x7fffffffe380: 0x7fffffffe498  0x1a561cbc0
    0x7fffffffe390: 0x7fffffffe3b0  0x40064f <main(int, char**)+27>

对应的堆栈图：

![](/assets/res/stack_frame/stack_frame_ex.png)

可以看看例子中`0x400631 <b(int, char**)+43>`和` 0x40064f <main(int, char**)+27>`中的代码：

    (gdb) disassemble 0x400631
    ...
    0x0000000000400627 <b(int, char**)+33>: callq  0x400468 <printf@plt>
    0x000000000040062c <b(int, char**)+38>: callq  0x4005ae <g()>
    0x0000000000400631 <b(int, char**)+43>: leaveq                           # call的下一条指令
    ...

    (gdb) disassemble 0x40064f
    ... 
    0x000000000040063f <main(int, char**)+11>:      mov    %rsi,-0x10(%rbp)
    0x0000000000400643 <main(int, char**)+15>:      mov    -0x10(%rbp),%rsi
    0x0000000000400647 <main(int, char**)+19>:      mov    -0x4(%rbp),%edi
    0x000000000040064a <main(int, char**)+22>:      callq  0x400606 <b(int, char**)>
    0x000000000040064f <main(int, char**)+27>:      mov    $0x0,%eax         # call的下一条指令
    ...

顺带一提，每个函数入口和出口，对应的设置RBP代码为：

    (gdb) disassemble g
    ...
    0x00000000004005ae <g()+0>:     push   %rbp               # 保存调用者的RBP到堆栈
    0x00000000004005af <g()+1>:     mov    %rsp,%rbp          # 设置自己的RBP
    ...
    0x0000000000400603 <g()+85>:    leaveq                    # 等同于：movq %rbp, %rsp
                                                              #         popq %rbp
    0x0000000000400604 <g()+86>:    retq                      

由以上可见，**通过当前的RSP或RBP就可以找到调用堆栈中所有函数的RBP；找到了RBP就可以找到函数地址**。因为，任何时候的RBP指向的堆栈位置就是上一个函数的RBP；而任何时候RBP所在堆栈中的前一个位置就是函数返回地址。

由此我们可以自己构建一个导致gdb无法取得调用堆栈的例子：


{% highlight c++ %}
    void f() {
        long *p = 0;
        p = (long*) (&p + 1); // 取得g()的RBP
        *p = 0;  // 破坏g()的RBP
    }

    void g() {
        int *p = 0;
        long a = 0x1234;
        printf("%p %x\n", &a, a);
        printf("%p %x\n", &p, p);
        f();
        *p = 1; // 写0地址导致一次core
    }

    void b(int argc, char **argv) {
        printf("%p %p\n", &argc, &argv);
        g();
    }

    int main(int argc, char **argv) {
        b(argc, argv);
        return 0;
    }
{% endhighlight %}

使用gdb运行该程序：

    Program received signal SIGSEGV, Segmentation fault.
    g () at ebp.c:37
    37          *p = 1;
    (gdb) bt
    Cannot access memory at address 0x8
    (gdb) p $rbp
    $1 = (void *) 0x0


`bt`无法获取堆栈，在函数`g()`中RBP被改写为0，gdb从0偏移一个地址长度即0x8，尝试从0x8内存位置获取函数地址，然后提示`Cannot access memory at address 0x8`。

**RBP出现了问题，我们就可以通过RSP来手动获取调用堆栈。**因为RSP是不会被破坏的，要通过RSP获取调用堆栈则需要偏移一些局部变量所占的空间：

    (gdb) p $rsp
    $2 = (void *) 0x7fffffffe360
    (gdb) x/8ag $rsp+16             # g()中局部变量占16字节
    0x7fffffffe370: 0x7fffffffe390  0x400631 <b(int, char**)+43>
    0x7fffffffe380: 0x7fffffffe498  0x1a561cbc0
    0x7fffffffe390: 0x7fffffffe3b0  0x40064f <main(int, char**)+27>
    0x7fffffffe3a0: 0x7fffffffe498  0x100000000

基于以上就可以手工找到调用堆栈：

    g()
    0x400631 <b(int, char**)+43>
    0x40064f <main(int, char**)+27>

上面的例子本质上也是破坏堆栈，并且仅仅破坏了保存了的RBP。在实际情况中，堆栈可能会被破坏得更多，则可能导致手动定位也较困难。

堆栈被破坏还可能导致更多的问题，例如覆盖了函数返回地址，则会导致RIP错误；例如堆栈的不平衡。导致堆栈被破坏的原因也有很多，例如局部数组越界；[delete/free栈上对象等](http://codemacro.com/2013/08/15/debug-esp-bug/)。

## omit-frame-pointer

使用RBP获取调用堆栈相对比较容易。但现在编译器都可以设置不使用RBP(gcc使用-fomit-frame-pointer，msvc使用/Oy)，对于函数而言不设置其RBP意味着可以节省若干条指令。在函数内部则完全使用RSP的偏移来定位局部变量，包括嵌套作用域里的局部变量，即使程序实际运行时不会进入这个作用域。

例如：

{% highlight c++ %}
    void f2() {
        int a = 0x1234;
        if (a > 0) {
            int b = 0xff;
            b = a;
        }
    }
{% endhighlight %}

gcc中使用`-fomit-frame-pointer`生成的代码为：

    (gdb) disassemble f2
    Dump of assembler code for function f2:
    0x00000000004004a5 <f2+0>:      movl   $0x1234,-0x8(%rsp)    # int a = 0x1234
    0x00000000004004ad <f2+8>:      cmpl   $0x0,-0x8(%rsp)       
    0x00000000004004b2 <f2+13>:     jle    0x4004c4 <f2+31>      
    0x00000000004004b4 <f2+15>:     movl   $0xff,-0x4(%rsp)      # int b = 0xff
    0x00000000004004bc <f2+23>:     mov    -0x8(%rsp),%eax
    0x00000000004004c0 <f2+27>:     mov    %eax,-0x4(%rsp)
    0x00000000004004c4 <f2+31>:     retq

可以发现`f2()`没有操作`RBP`之类的指令了。



