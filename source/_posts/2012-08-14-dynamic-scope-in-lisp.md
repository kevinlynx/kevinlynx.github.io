---
layout: post
title: "Lisp中定义变量*var*和var有什么不同？"
date: 2012-08-14 15:53
comments: true
categories: [lisp]
tags: [lisp]
---

参考[What's difference between *var* and var when using defvar?](http://stackoverflow.com/questions/11932876/whats-difference-between-var-and-var-when-using-defvar)

其实，Common Lisp中使用defvar定义变量加不加星号没有区别。这只是一种Lisp程序员的约定。Lisp中并不使用特定的符号来影响语法元素，例如Ruby中通过给变量添加@前缀来标示该变量为类成员变量。这个问题引出了lisp总dynamic scope这个话题。
<!-- more -->
Lisp中变量分为两种，分别为`lexical`和`special`。这两种不同的变量有不同的作用域(scope)：词法作用域(lexical scope)和动态作用域(dynamic scope)。`special variables`通过`defvar/defparameter/declare`来定义。而`lexical variables`通常在`let`中定义。

这两种作用域有什么不同呢？引用\<ANSI Common Lisp\>里说的：

> Under lexical scope, a symbol refers to the variable that has that name in the context where the symbol appears (define)

> With dynamic scope, we look for a variable in the environment where the function is called, not in the environment where it was defined.

所以：

{% highlight cl %}
(defvar b 3)

(defun add-to-b (x)
  (+ x b))

(add-to-b 1)
  => 4

(let ((b 4))
  (list (add-to-b 1) b))
=> (5 4)

(let ((a 3))
  (defun add-to-a (x)
    (+ x a)))

(add-to-a 1)
  => 4

(let ((a 4))
  (list (add-to-a 1) a))
=> (4 4)
{% endhighlight %}

`add-to-b`这个函数中使用的变量`b`是`special variable`，所以在调用`add-to-b`时，取的就是调用(called)这个函数时环境中的变量，所以：

{% highlight cl %}
(let ((b 4))
  (list (add-to-b 1) b))
=> (5 4)
{% endhighlight %}

取的就是let中临时出现的`b`。而`add-to-a`这个函数中使用的变量`a`是`lexical variable`，所以调用这个函数时，取的就是这个函数定义(defined)时的`a`，所以无论在哪里调用`add-to-a`，都是取的：

{% highlight cl %}
(let ((a 3))
  (defun add-to-a (x)
    (+ x a)))
{% endhighlight %}

这里的`a`，也就是一直是3。


