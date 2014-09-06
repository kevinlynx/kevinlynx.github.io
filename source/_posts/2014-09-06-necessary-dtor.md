---
layout: post
title: "C++构造/析构函数中的多态(二)"
category: c/c++
tags: [c/c++, virtual]
comments: true
---


本来是几年以前写的一篇博客：[C++陷阱：构造函数中的多态](http://codemacro.com/2012/09/17/c-plus-plus-ctor-virtual/)。然后有同学在评论中讨论了起来，为了记录我就在这里单独写一篇，基本上就是用编译器的实现去证明了早就被大家熟知的一些结论。

**默认构造函数/析构函数不是在所有情况下都会被生成出来的。**为此我还特地翻出《Inside C++ object model》：

> 2.1 Default Constructor Construction 

> The C++ Annotated Reference Manual (ARM) [ELLIS90] (Section 12.1) tells us that "default constructors…are generated (by the compiler) where needed…." 


后面别人还罗列了好些例子告诉你哪些情况才算`needed`。本文我就解释`构造函数中的多态`评论中的问题。
<!-- more -->
实验代码如下：

{% highlight c++ %}
#include <stdio.h>

class Base {
public:
    Base() {
        Init();
    }

    //virtual
     ~Base() {
        printf("Base dtor\n");
        Release();
    }

    virtual void Init() {
        printf("Base::Init\n");
    }

    virtual void Release() {
        printf("Base::Release\n");
    }
};

class Derived : public Base {
public:
    /*
    ~Derived() {
        printf("Derived dtor\n");
    } // */

    virtual void Init() {
        printf("Derived::Init\n");
    }

    virtual void Release() {
        printf("Derived:Release\n");
    }
};

int main()
{
    Base *obj = new Derived();
    delete obj;
    return 0;
}
{% endhighlight %}

去掉`Derived`的析构函数，去掉`Base`析构函数的`virtual`：

    # g++ -Wa,-adhln -g test.cpp > test.s

      44:test.cpp      ****     delete obj;
     227                    .loc 1 44 0
     228 0028 488B45F0      movq    -16(%rbp), %rax
     229 002c 488945E0      movq    %rax, -32(%rbp)
     230 0030 48837DE0      cmpq    $0, -32(%rbp)       
     230      00
     231 0035 7520          jne .L17                   
     232 0037 EB30          jmp .L18
    ...
     244                .L17:
     245                    .loc 1 44 0
     246 0057 488B7DE0      movq    -32(%rbp), %rdi
     247 005b E8000000      call    _ZN4BaseD1Ev             # 直接call
   
从这里甚至可以看到`delete`对空指针的判定。`Base`的析构函数不是`virtual`，所以这里编译器生成的析构函数调用代码根本不需要用到`vptr`，直接`call`就可以。而具体`call`谁则是根据`obj`指向的类型`Base`确定。*即使`Derived`用户定义了析构函数也不会调用，无论是否`virtual`。*

事实上编译器甚至不需要生成`Derived`的析构函数，*多傻的编译器才会生成这些什么事都不做的代码而光进出函数就得好几条指令？*

查看程序中的符号，没有生成`Derived`析构函数：

    # nm test
    ...
    0000000000400816 W _ZN4Base4InitEv
    00000000004007fe W _ZN4Base7ReleaseEv
    000000000040082e W _ZN4BaseC2Ev
    0000000000400876 W _ZN4BaseD1Ev             
    00000000004007e6 W _ZN7Derived4InitEv
    00000000004007ce W _ZN7Derived7ReleaseEv
    0000000000400852 W _ZN7DerivedC1Ev
    ...

现在把`Base`析构函数变为`virtual`的：

      44:test.cpp      ****     delete obj;
     170                    .loc 1 44 0
     171 0028 48837DF0      cmpq    $0, -16(%rbp)
     171      00
     172 002d 7520          jne .L12
     173 002f EB32          jmp .L13
    ...
     185                .L12:
     186                    .loc 1 44 0
     187 004f 488B45F0      movq    -16(%rbp), %rax     # this -> rax
     188 0053 488B00        movq    (%rax), %rax        # *rax -> vptr
     189 0056 4883C008      addq    $8, %rax            # vptr += 8
     190 005a 488B00        movq    (%rax), %rax        # *vptr -> Base::~Base
     191 005d 488B7DF0      movq    -16(%rbp), %rdi     # this as first argument (passed by rdi)
     192 0061 FFD0          call    *%rax               # call

析构函数动态调用这也是预期的。至于为什么是偏移`vptr+8`，是因为第一个指针指向的是`type_info`，具体可看[浅议 Dynamic_cast 和 RTTI](http://www.cnblogs.com/zhyg6516/archive/2011/03/07/1971898.html)。*vptr和virtual function table还需要详述吗？*

此时就会生成`Derived`的析构函数：

    ...
    000000000040084c W _ZN4Base4InitEv
    00000000004008ac W _ZN4Base7ReleaseEv
    0000000000400864 W _ZN4BaseC2Ev
    0000000000400970 W _ZN4BaseD0Ev
    00000000004009b0 W _ZN4BaseD1Ev
    00000000004008c4 W _ZN4BaseD2Ev
    0000000000400834 W _ZN7Derived4InitEv
    000000000040081c W _ZN7Derived7ReleaseEv
    0000000000400888 W _ZN7DerivedC1Ev
    0000000000400904 W _ZN7DerivedD0Ev          
    000000000040093a W _ZN7DerivedD1Ev
    ...

细心的人就会发现无论是`Base`还是`Derived`都会生成多个析构函数，这个深入下去还有很多内容，具体可以参看：[GNU GCC (g++): Why does it generate multiple dtors?](http://stackoverflow.com/questions/6613870/gnu-gcc-g-why-does-it-generate-multiple-dtors)。

甚至可以运行这个例子看到调用到了`Derived`的析构函数：

    (gdb) ni
    0x000000000040080d      45          return 0;
    1: x/3i $pc
    0x40080d <main()+117>:  callq  *%rax                  # 调用
    0x40080f <main()+119>:  mov    $0x0,%eax
    0x400814 <main()+124>:  add    $0x28,%rsp
    (gdb) si
    Derived::~Derived (this=0x7ffff7ffd000, __in_chrg=<value optimized out>) at test.cpp:24
    24      class Derived : public Base {
    1: x/3i $pc
    0x400904 <Derived::~Derived()>: push   %rbp
    0x400905 <Derived::~Derived()+1>:       mov    %rsp,%rbp
    0x400908 <Derived::~Derived()+4>:       sub    $0x10,%rsp

其实看`Derived`的析构函数实现会发现很多有趣的东西：

    (gdb) disassemble 'Derived::~Derived'
    Dump of assembler code for function Derived::~Derived():
    0x0000000000400904 <Derived::~Derived()+0>:     push   %rbp
    0x0000000000400905 <Derived::~Derived()+1>:     mov    %rsp,%rbp
    0x0000000000400908 <Derived::~Derived()+4>:     sub    $0x10,%rsp
    0x000000000040090c <Derived::~Derived()+8>:     mov    %rdi,-0x8(%rbp)
    0x0000000000400910 <Derived::~Derived()+12>:    mov    $0x400b50,%edx
    0x0000000000400915 <Derived::~Derived()+17>:    mov    -0x8(%rbp),%rax
    0x0000000000400919 <Derived::~Derived()+21>:    mov    %rdx,(%rax)
    0x000000000040091c <Derived::~Derived()+24>:    mov    -0x8(%rbp),%rdi
    0x0000000000400920 <Derived::~Derived()+28>:    callq  0x4008c4 <Base::~Base()>
    0x0000000000400925 <Derived::~Derived()+33>:    mov    $0x1,%eax
    0x000000000040092a <Derived::~Derived()+38>:    test   %al,%al
    0x000000000040092c <Derived::~Derived()+40>:    je     0x400937 <Derived::~Derived()+51>
    0x000000000040092e <Derived::~Derived()+42>:    mov    -0x8(%rbp),%rdi
    0x0000000000400932 <Derived::~Derived()+46>:    callq  0x400670 <_ZdlPv@plt>               
    0x0000000000400937 <Derived::~Derived()+51>:    leaveq
    0x0000000000400938 <Derived::~Derived()+52>:    retq

实际上这个析构函数就是上面的`D0`版本，它做了一件重要的事就是`delete this`。具体的可以google gcc对析构函数的实现。

构造函数和析构函数中根本就不会启用多态，这个是结论或者说是标准，但不是原因(真怕又有人告诉我c++ standard某section这样写的所以这就是理由)。既然反正已经看实现了，就索性看一眼编译器怎么处理这个问题：

    // Base::~Base
     261 0000 55            pushq   %rbp
     262                .LCFI22:
     263 0001 4889E5        movq    %rsp, %rbp
     264                .LCFI23:
     265 0004 4883EC10      subq    $16, %rsp
     266                .LCFI24:
     267 0008 48897DF8      movq    %rdi, -8(%rbp)
     268                    .loc 1 10 0
     269 000c BA000000      movl    $_ZTV4Base+16, %edx
     269      00
     270 0011 488B45F8      movq    -8(%rbp), %rax
     271 0015 488910        movq    %rdx, (%rax)
     272                    .loc 1 11 0
     273 0018 BF000000      movl    $.LC4, %edi
     273      00
     274 001d E8000000      call    puts
     274      00
     275                    .loc 1 12 0
     276 0022 488B7DF8      movq    -8(%rbp), %rdi
     277 0026 E8000000      call    _ZN4Base7ReleaseEv  # 直接call绝对地址

构造函数一样：

      94 0000 55            pushq   %rbp
      95                .LCFI9:
      96 0001 4889E5        movq    %rsp, %rbp
      97                .LCFI10:
      98 0004 4883EC10      subq    $16, %rsp
      99                .LCFI11:
     100 0008 48897DF8      movq    %rdi, -8(%rbp)
     101                .LBB2:
     102                    .loc 1 5 0
     103 000c B8000000      movl    $_ZTV4Base+16, %eax
     103      00
     104 0011 488B55F8      movq    -8(%rbp), %rdx
     105 0015 488902        movq    %rax, (%rdx)
     106                    .loc 1 6 0
     107 0018 488B7DF8      movq    -8(%rbp), %rdi
     108 001c E8000000      call    _ZN4Base4InitEv  # 直接call地址


*END*


