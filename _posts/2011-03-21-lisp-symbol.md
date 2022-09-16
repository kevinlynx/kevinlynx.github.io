---
layout: post
title: "Lisp一瞥：增强型变量Symbol"
category: lisp
tags: lisp
comments: true
---

变量，是所有编程语言里都有的语法概念。在C/C++中，变量用于标示一个内存地址，而变
量名则在语法层面上代表这个地址。当链接器最终链接我们的程序时，就将这些名字替换
为实际的地址。在其他语言中，变量虽然或多或少有其他不同的含义，但也大致如此。

Lisp中的变量也差不多这样，但若将variable和Lisp中的 **symbol** 放在一起，则多少会 带来些困惑。
<!-- more -->
## Lisp中的“变量"

很多教授Lisp的书中，大概会简单地告诉我们可以使用如下的方式定义一个全局变量 [1]\_.
{% highlight cl %}
(defparameter *var* 1)
{% endhighlight %}
如上代码，我们便定义了一个全局变量 `*var*` [2]\_ ，它被初始化为数值1。同样，我们 还可以使用另一种基本相同的方式:

{% highlight cl %}
(defvar *var* 1)
{% endhighlight %}

除了全局变量，我们还可以定义局部变量。但局部变量的定义稍显麻烦（却可能是另一种
设计考虑）。定义局部变量需要使用一些宏，或者特殊运算符，例如:

{% highlight cl %}
(let ((var 1))
  (format t "~a" var))
{% endhighlight %}

好了，就这些了。Lisp中关于变量的细节，也就这些。你甚至能用你在C/C++中的经验来窥
探一切。但是，我们很快就看到了很多困惑的地方。

我遇到的第一个困惑的地方来源于函数，那么等我讲讲函数再来分享下坎坷。

## Lisp中的函数

Lisp中的函数绝对不复杂，你绝对不用担心我在忽悠你 [3]\_ 。作为一门函数式语言，其首要
任务就是加强函数这个东西在整个语言里的功能。如果你喜欢广阅各种与你工作不相干的
技术，你肯定已经对很多函数式语言世界中的概念略有耳闻。例如闭包，以及first class type [4]\_ 。

Lisp中的函数就是first class type。这什么意思呢？直白来说，
**Lisp中的函数和变量 没什么区别，享有同等待遇** 。进一步来说，变量fn的值可以是数值1，也可以是字符串
"hello"，甚至是某个函数。这其实就是C++程序员说的functor。

Lisp中定义函数非常简单:

{% highlight cl %}
(defun add2 (x) 
  (+ 2 x))
{% endhighlight %}

这样，我们就定义了一个名为add2，有1个参数，1个返回值的函数。要调用该函数时，只需 要 `(add2 2)`
即可。这简直和我们在Lisp中完成一个加法一模一样:`(+ 2 3)`

Lisp作为一门函数式语言，其函数也能作为另一个函数的参数和返回值 [5]\_

{% highlight cl %}
(defun apply-fn (fn x)
  (funcall fn x))
{% endhighlight %}

apply-fn函数第一个参数是一个函数，它使用funcall函数间接地调用fn指向的函数。作为
一个C++程序员，这简直太好理解了，这完全就是一个函数指针的语法糖嘛。于是，假设我 们要使用apply-fn来间接调用add2函数:

{% highlight cl %}
(apply-fn add2 2) ;; wrong 
{% endhighlight %}

可是这是不对的。我们需要通过另一个特殊操作符来完成这件事:

{% highlight cl %}
(apply-fn #'add2 2) ;; right
{% endhighlight %}

\#'操作符用于将add2对应的函数取出来，这么说当然不大准确。Again，作为一个C++程序员
，这简直就是个取地址操作符&的语法糖嘛。好吧，这么理解起来似乎没问题了。

Lisp中能甚至能在任何地方定义一个函数，例如我们创建一个函数，该函数返回创建出来的 函数，这是一个典型的讲解什么是 **闭包**
的例子:

{% highlight cl %}
(defun get-add-n (n)
  #' (lambda (x)
       (+ x n)))
{% endhighlight %}

无论如何，get-add-n函数返回一个函数，该函数是add2函数的泛型实现。它可以将你传入
的参数加上n。这些代码里使用了lambda表达式。lambda表达式直白来说，就是创建一个字
面上的函数。这又是什么意思呢？就像我们在代码中写出2，写出"hello"一样，2就是个字
面上的数字，"hello"就是个字面上的字符串 [6]\_ 。

那么，总而言之，通过lambda创建一个函数体，然后通过\#'操作符即可得到一个函数，虽然 没有名字。有了以上知识后，Again
and again，作为一个C++程序员，很快我们就能得到一
个程序：定义变量，用变量去保存一个函数，然后通过这个变量来调用这个函数。这是多么
天经地义的事，就像之前那个通过参数调用其指向的函数一样:

{% highlight cl %}
;; wrong 
(defvar fn #' (lambda (x) (+ x 2)))
(fn 3)
{% endhighlight %}

这样的代码是不对的，错误发生于第二行，无论你使用的Lisp实现是哪种，大概会得到如下 的错误信息:

    "The function FN is undefined."

老实说，这已经算是多么有迹可循的错误提示了啊。将以上代码和之前的apply-fn对比，是
多么得神似啊，可惜就是错的。这是我们遇到的第一个理解偏差导致的问题。如果你还不深
入探究，你将会在这一块遇到更多麻烦。及时地拿出你的勇气，披荆斩棘，刨根究底，绝对 是学习编程的好品质。

## “万恶之源“：SYMBOL

上文中提到的变量函数之类，之所以会在某些时候与我们的理解发生偏差，并且总是存在些
神秘的地方无法解释。这完全是因为我们理解得太片面导致。Lisp中的Symbol可以说就是某
个变量，或者某个函数，但这太片面。Lisp中的Symbol拥有更丰富的含义。

### Symbol的名字

就像很多语言的变量、函数名一样，Lisp中的Symbol比其他语言在命名方面更自由：
**只 要位于'|'字符之间的字符串，就表示一个合法的Symbol名。** 我们可以使用函数
symbol-name来获取一个Symbol的名字，例如:

{% highlight cl %}
(symbol-name '|this is a symbol name|)
{% endhighlight %}
    
    输出："this is a symbol name"

'(quote)操作符告诉Lisp不要对其修饰的东西进行求值(evaluate)。但假如没有这个操作符
会怎样呢？后面我们将看到会怎样。

### Symbol本质

<ANSI Common Lisp\>一书中有句话真正地揭示了Symbol的本质：
**Symbols are real objects**
。是的，Symbols是对象，这个对象就像我们理解的C++中的对象一样，它是一个
复合的数据结构。该数据结构里包含若干域，或者通俗而言：数据成员。借用<ANSI Common Lisp\>中的一图：

> ![image](/assets/res/lisp_symbol/symbol-obj.png)

通过这幅图，可以揭开所有谜底。一个Symbol包含至少图中的几个域，例如Name、Value、
Function等。在Lisp中有很多函数来访问这些域，例如上文中使用到的symbol-name，这个
函数本质上就是取出一个Symbol的Name域。

### Symbol与Variable和Function的联系

自然而然地，翻阅Lisp文档，我们会发现果然还有其他函数来访问Symbol的其他域，例如:

    symbol-function
    symbol-value
    symbol-package
    symbol-plist

但是这些又与上文提到的变量和函数有什么联系呢？真相只有一个，
**变量、函数粗略来 说就是Symbol的一个域，一个成员。变量对应Value域，函数对应Function域。一个Symbol 这些域有数据了，我们说它们发生了绑定(bind)。**
而恰好，我们有几个函数可以用于判 定这些域是否被绑定了值:

    boundp ;判定Value域是否被绑定
    fboundp;判定Function域是否被绑定

通过一些代码来回味以上结论:

{% highlight cl %}
(defvar *var* 1)
(boundp '*var*) ; 返回真
(fboundp '*var*) ; 返回假
(defun *var* (x) x) ; 定义一个名为*var*的函数，返回值即为参数
(fboundp '*var*) ; 返回真
{% endhighlight %}

上面的代码简直揭秘了若干惊天地泣鬼神的真相。首先，我们使用我们熟知的defvar定义了 一个名为 `*var*`
的变量，初值为1，然后使用boundp去判定 `*var*` 的Value域是否 发生了绑定。这其实是说：
**原来定义变量就是定义了一个Symbol，给变量赋值，原来就 是给Symbol的Value域赋值！**

**其实，Lisp中所有这些符号，都是Symbol。** 什么变量，什么函数，都是浮云。上面的
例子中，紧接着用fboundp判断Symbol `*var*` 的Function域是否绑定，这个时候为假。 然后我们定义了一个名为
`*var*` 的函数，之后再判断，则已然为真。这也是为什么， **在Lisp中某个函数可以和某个变量同名的原因所在。**
从这段代码中我们也可以看出 defvar/defun这些操作符、宏所做事情的本质。

### More More More

事情就这样结束了？Of course not。还有很多上文提到的疑惑没有解决。首先，Symbol是
如此复杂，那么Lisp如何决定它在不同环境下的含义呢？Symbol虽然是个对象，但它并不像
C++中的对象一样，它出现时并不指代自己！不同应用环境下，它指代的东西也不一样。这 些指代主要包括变量和函数，意思是说：
**Symbol出现时，要么指的是它的Value，要么是 它的Function。** 这种背地里干的事情，也算是造成迷惑的一个原因。

当一个Symbol出现在一个List的第一个元素时，它被处理为函数。这么说有点迷惑人，因为
它带进了Lisp中代码和数据之间的模糊边界特性。简单来说，就是当Symbol出现在一个括号
表达式(s-expression)中第一个位置时，算是个函数，例如:

{% highlight cl %}
(add2 3) ; add2位于第一个位置，被当作函数处理
(*var* 3) ; 这里*var*被当作函数调用，返回3
{% endhighlight %}

除此之外，我能想到的其他大部分情况，一个Symbol都被指代为它的Value域，也就是被当 作变量，例如:

{% highlight cl %}
(*var* *var*) ; 这是正确的语句，返回1
{% endhighlight %}

这看起来是多么古怪的代码。但是运用我们上面说的结论，便可轻易解释：表达式中第一个 `*var*`
被当作函数处理，它需要一个参数；表达式第二部分的 `*var*` 被当作变量 处理，它的值为1，然后将其作为参数传入。

再来说说'(quote)操作符，这个操作符用于防止其操作数被求值。而当一个Symbol出现时，
它总是会被求值，所以，我们可以分析以下代码:

{% highlight cl %}
(symbol-value *var*) ; wrong
{% endhighlight %}

这个代码并不正确，因为 `*var*` 总是会被求值，就像 `(*var* *var*)` 一样，第二 个 `*var*`
被求值，得到数字1。这里也会发生这种事情，那么最终就等同于:

{% highlight cl %}
(symbol-value 1) ; wrong
{% endhighlight %}

我们试图去取数字1的Value域，而数字1并不是一个Symbol。所以，我们需要quote运算符:

{% highlight cl %}
(symbol-value '*var*) ; right
{% endhighlight %}

这句代码是说，取Symbol `*var*` 本身的Value域！而不是其他什么地方。至此，我们 便可以分析以下复杂情况:

{% highlight cl %}
(defvar *name* "kevin lynx")
(defvar *ref* '*name*) ; *ref*的Value保存的是另一个Symbol
(symbol-value *ref*) ; 取*ref*的Value，得到*name*，再取*name*的Value
{% endhighlight %}

现在，我们甚至能解释上文留下的一个问题:

{% highlight cl %}
;; wrong 
(defvar fn #' (lambda (x) (+ x 2)))
(fn 3)
{% endhighlight %}

给fn的Value赋值一个函数， `(fn 3)` 当一个Symbol作为函数使用时，也就是取其
Function域来做调用。但其Function域什么也没有，我们试图将一个Symbol的Value域当作
Function来使用。如何解决这个问题？想想，symbol-function可以取到一个Symbol的 Function域:

{% highlight cl %}
(setf (symbol-function 'fn) #' (lambda (x) (+ x 2)))
(fn 3)
{% endhighlight %}

通过显示地给fn的Function域赋值，而不是通过defvar隐式地对其Value域赋值，就可以使 `(fn 3)`
调用正确。还有另一个问题也能轻易解释:

{% highlight cl %}
(apply-fn add2 2) ; wrong
{% endhighlight %}

本意是想传入add2这个Symbol的function域，但是直接这样写的话，传入的其实是add2的 Value域 [7]\_
，这当然是不正确的。对比正确的写法，我们甚至能猜测\#'运算符就是一个
取Symbol的Function域的运算符。进一步，我们还可以给出另一种写法:

{% highlight cl %}
(apply-fn (symbol-function 'add2) 2)
{% endhighlight %}

深入理解事情的背后，你会发现你能写出多么灵活的代码。

## END

关于Symbol的内容还有更多，例如Package。正确理解这些内容以及他们之间的关系，有助 于更深刻地理解Lisp。

## 注解

* [1]  在Lisp中全局变量又被称为dynamic variables
* [2]  Lisp中按照习惯通常在为全局变量命名时会加上星号，就像我们习惯使用g_一样
* [3]  因为我确实在忽悠你
* [4]  first class type，有人翻译为“一等公民”，我觉得压力巨大
* [5]  即高阶函数
* [6]  “字面“主要是针对这些信息会被词法分析程序直接处理
* [7]  这可能导致更多的错误

