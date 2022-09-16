---
layout: post
title: "为什么处理排序的数组要比非排序的快？"
date: 2012-08-29 19:55
comments: true
categories: [c/c++, other]
tags: [branck predictor, c/c++]
---

参考[Why is processing a sorted array faster than an unsorted array?](http://stackoverflow.com/questions/11227809/why-is-processing-a-sorted-array-faster-than-an-unsorted-array)

## 问题

看以下代码：

{% highlight c++ %}
#include <algorithm>
#include <ctime>
#include <iostream>

int main()
{
    // generate data
    const unsigned arraySize = 32768;
    int data[arraySize];

    for (unsigned c = 0; c < arraySize; ++c)
        data[c] = std::rand() % 256;


    // !!! with this, the next loop runs faster
    std::sort(data, data + arraySize);


    // test
    clock_t start = clock();
    long long sum = 0;

    for (unsigned i = 0; i < 100000; ++i)
    {
        // primary loop
        for (unsigned c = 0; c < arraySize; ++c)
        {
            if (data[c] >= 128)
                sum += data[c];
        }
    }

    double elapsedTime = static_cast<double>(clock() - start) / CLOCKS_PER_SEC;

    std::cout << elapsedTime << std::endl;
    std::cout << "sum = " << sum << std::endl;
}

{% endhighlight %}

问题就在于，去掉`std::sort`那一行，以上代码将运行更长的时间。在我的机器上未去掉`std::sort`耗时8.99s，去掉后耗时24.78s。编译器使用的是gcc4.4.3。事实上，以上代码跟编译器没有关系，甚至跟语言没有关系。那这是为什么呢？
<!-- more -->
这跟处理这个数组的逻辑有非常大的关系。如以上代码所示，这个循环里有个条件判断。条件判断被编译成二进制代码后，就是一个跳转指令，类似：

{% highlight asm %}
jl SHORT $LN3@main
{% endhighlight %}

具体为什么会不同，这涉及到计算机CPU执行指令时的行为。

## CPU的流水线指令执行

想象现在有一堆指令等待CPU去执行，那么CPU是如何执行的呢？具体的细节可以找一本计算机组成原理的书来看。CPU执行一堆指令时，并不是单纯地一条一条取出来执行，而是按照一种流水线的方式，在CPU真正执行一条指令前，这条指令就像工厂里流水线生产的产品一样，已经被经过一些处理。简单来说，一条指令可能经过这些过程：取指(Fetch)、解码(Decode)、执行(Execute)、放回(Write-back)。

假设现在有指令序列ABCDEFG。当CPU正在执行(execute)指令A时，CPU的其他处理单元（CPU是由若干部件构成的）其实已经预先处理到了指令A后面的指令，例如B可能已经被解码，C已经被取指。这就是流水线执行，这可以保证CPU高效地执行指令。

## Branch Prediction

如上所说，CPU在执行一堆顺序执行的指令时，因为对于执行指令的部件来说，其基本不需要等待，因为诸如取指、解码这些过程早就被做了。但是，当CPU面临非顺序执行的指令序列时，例如之前提到的跳转指令，情况会怎样呢？

取指、解码这些CPU单元并不知道程序流程会跳转，只有当CPU执行到跳转指令本身时，才知道该不该跳转。所以，取指解码这些单元就会继续取跳转指令之后的指令。当CPU执行到跳转指令时，如果真的发生了跳转，那么之前的预处理（取指、解码）就白做了。这个时候，CPU得从跳转目标处临时取指、解码，然后才开始执行，这意味着：CPU停了若干个时钟周期！

这其实是个问题，如果CPU的设计放任这个问题，那么其速度就很难提升起来。为此，人们发明了一种技术，称为branch prediction，也就是分支预测。分支预测的作用，就是预测某个跳转指令是否会跳转。而CPU就根据自己的预测到目标地址取指令。这样，即可从一定程度提高运行速度。当然，分支预测在实现上有很多方法。

简单的预测可以直接使用之前的实际执行结果。例如某个跳转指令某一次产生了跳转，那么下一次执行该指令时，CPU就直接从跳转目标地址处取指，而不是该跳转指令的下一条指令。

## 答案

了解了以上信息后，文章开头提出的问题就可以解释了。这个代码中有一个循环，这个循环里有一个条件判断。每一次CPU执行这个条件判断时，CPU都可能跳转到循环开始处的指令，即不执行if后的指令。使用分支预测技术，当处理已经排序的数组时，在若干次`data[c]>=128`都不成立时（或第一次不成立时，取决于分支预测的实现），CPU预测这个分支是始终会跳转到循环开始的指令时，这个时候CPU将保持有效的执行，不需要重新等待到新的地址取指；同样，当`data[c]>=128`条件成立若干次后，CPU也可以预测这个分支是不必跳转的，那么这个时候CPU也可以保持高效执行。

相反，如果是无序的数组，CPU的分支预测在很大程度上都无法预测成功，基本就是50%的预测成功概率，这将消耗大量的时间，因为CPU很多时间都会等待取指单元重新取指。

本文完。最后感叹下stackoverflow上这个帖子里那个老外回答问题的专业性，我要是楼主早就感动得涕泪横飞了。感谢每一个传播知识的人。

## 参考资料

1. <http://blog.sina.com.cn/s/blog_6c673e570100zfmo.html>
2. <http://www.cnblogs.com/dongliqian/archive/2012/04/05/2433847.html>
3. <http://en.wikipedia.org/wiki/Branch_predictor>

