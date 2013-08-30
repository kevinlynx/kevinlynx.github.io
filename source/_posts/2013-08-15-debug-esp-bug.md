---
layout: post
title: "记一次堆栈平衡错误"
categories: c/c++
tags: [esp, stack, 堆栈]
comments: true
keywords: [esp, stack, 堆栈]
description: 
---

最近在一个使用Visual Studio开发的C++程序中，出现了如下错误：

> Run-Time Check Failure #0 - The value of ESP was not properly saved across a function call.  This is usually a result of calling a function declared with one calling convention with a function pointer declared with a different calling convention.

这个错误主要指的就是函数调用堆栈不平衡。在C/C++程序中，调用一个函数前会保存当前堆栈信息，目标函数返回后会把堆栈恢复到调用前的状态。函数的参数、局部变量会影响堆栈。而函数堆栈不平衡，一般是因为函数调用方式和目标函数定义方式不一致导致，例如：

{% highlight c++ %}
void __stdcall func(int a) {
}

int main(int argc, char* argv[]) {
    typedef void (*funcptr)(int);
    funcptr ptr = (funcptr) func;
    ptr(1); // 返回后导致堆栈不平衡
    return 0;
}
{% endhighlight %}

`__stdcall`修饰的函数，其函数参数的出栈由被调用者自己完成，而`__cdecl`，也就是C/C++函数的默认调用约定，则是调用者完成参数出栈。

<!-- more -->
Visual Studio在debug模式下会在我们的代码中加入不少检查代码，例如以上代码对应的汇编中，就会增加一个检查堆栈是否平衡的函数调用，当出现问题时，就会出现提示`Run-Time Check Failure...`这样的错误对话框：

    call dword ptr [ptr]  ; ptr(1)
    add  esp,4  ; cdecl方式，调用者清除参数
    cmp  esi,esp  
    call @ILT+1345(__RTC_CheckEsp) (0B01546h) ; 检查堆栈是否平衡

但是我们的程序不是这种低级错误。我们调用的函数是放在dll中的，调用约定显示定义为`__stdcall`，函数声明和实现一致。大致的结构如下：

{% highlight c++ %}
IParser *parser = CreateParser();
parser->Begin();
...
...
parser->End();
parser->Release(); // 返回后导致堆栈不平衡
{% endhighlight %}

IParser的实现在一个dll里，这反而是一个误导人的信息。`parser->Release`返回后，堆栈不平衡，**并且仅仅少了一个字节**。一个字节怎么来的？

解决这个问题主要的手段就是跟反汇编，在关键位置查看寄存器和堆栈的内容。编译器生成的代码是正确的，而我们自己的代码乍看上去也没问题。最后甚至使用最傻逼的调试手段--逐行语句注释查错。

具体查错过程就不细说了。解决问题往往需要更多的冷静，和清晰的思路。最终我使用的方法是，在进入`Release`之前记录堆栈指针的值，堆栈指针的值会被压入堆栈，以在函数返回后从堆栈弹出，恢复堆栈指针。`Release`的实现很简单，就是删除一个`Parser`这个对象，但这个对象的析构会导致很多其他对象被析构。我就逐层地检查，是在哪个函数里改变了堆栈里的内容。

理论上，函数本身是操作不到调用者的堆栈的。而现在看来，确实是被调用函数，也就是`Release`改写了调用者的堆栈内容。要改变堆栈的内容，只有通过局部变量的地址才能做到。

最终，我发现在调用完以下函数后，我跟踪的堆栈地址内容发生了改变：
 
    call llvm::RefCountedBase<clang::TargetOptions>::Release (10331117h)

因为注意到`TargetOptions`这个字眼，想起了在`parser->Begin`里有涉及到这个类的使用，类似于：

{% highlight c++ %}
TargetOptions TO;
...
TargetInfo *TI = TargetInfo::CreateTargetInfo(m_inst.getDiagnostics(), TO);
{% endhighlight %}

这部分初始化代码，是直接从网上复制的，因为并不影响主要逻辑，所以从来没对这块代码深究。查看`CreateTargetInfo`的源码，**发现这个函数将`TO`这个局部变量的地址保存了下来**。

而在`Release`中，则会对这个保存的临时变量进行删除操作，形如：

{% highlight c++ %}
void Delete() const {
  assert (ref_cnt > 0 && "Reference count is already zero.");
  if (--ref_cnt == 0) delete static_cast<const Derived*>(this);
}
{% endhighlight %}

但是，**问题并不在于对一个局部变量地址进行delete**，`delete`在调试模式下是做了内存检测的，那会导致一种断言。

`TargetOptions`包含了`ref_cnt`这个成员。当出了`Begin`作用域后，parser保存的`TargetOptions`的地址，指向的内容（堆栈）发生了改变，也就是`ref_cnt`这个成员变量的值不再正常。由于一些巧合，主要是代码中各个局部变量、函数调用顺序、函数参数个数（曾尝试去除`Begin`的参数，可以避免错误提示），导致在调用`Release`前堆栈指针恰好等于之前保存的`TargetOptions`的地址。注意，之前保存的`TargetOptions`的地址，和调用`Release`前的堆栈指针值相同了。

而在`TargetOptions`的`Delete`函数中，进行了`--ref_cnt`，这个变量是`TargetOptions`的第一个成员，它的减1，也就导致了堆栈内容的改变。

至此，整个来龙去脉算是摸清。


