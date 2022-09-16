---
layout: post
title: "scala主要特性一览"
categories: Scala
tags: [scala, curry]
comments: true
keywords: [scala, curry, 偏函数]
description: 
---

## 概述

scala语言包含了函数式语言和面向对象语言的语法特性，从我目前的感受来看，这不是一门简单的语言。同Ruby/Erlang相比，其语法集大多了。scala基于JVM或.NET平台，其可以几乎无缝地使用Java库（不但使用上没有负担，其运行效率上也不会增加负担），配合其强大的语言表达能力，还是很有吸引力。

## 类型

### 类/对象

scala中一切都是对象，虽然Java也是这样说的（其实ruby也是这样说的）。在Java中一个数字仅仅是个值，但在scala中却真的是对象：

{% highlight scala %}	
println("2 type: " + 2.getClass())
{% endhighlight %}

scala同Java一样将所有类型都设定了一个基类：`Any`。不同的是，`Any`下还区分了`AnyVal`和`AnyRef`。

### 类型推断

scala是一门静态类型语言，但是其强大的类型推断可以避免很多冗余信息的代码。例如：

{% highlight scala %}	
val map:Map[String, Int] = new HashMap[String, Int]
// 可简写为
val map = new HashMap[String, Int]

def func():String = {
	"hello"
}
// 可简写为
def func() = {
	"hello"
}
{% endhighlight %}

类型推断可以根据表达式的类型决定这个变量/函数的类型，这就如同C++11中的`auto`关键字。

### 函数

scala既然包含了函数式语言的特性，那么函数作为first citizen就是自然而言的事情。而function literal的语法形式也就必须更自然（想想common lisp里lambda那蛋疼的关键字）：

{% highlight scala %}	
val factor = 3
val multiplier = (i:Int) => i * factor // function literal, lexical bind to factor
val l1 = List(1, 2, 3, 4, 5) map multiplier // map `multiplier` to every element in List l1

def add(a:Int, b:Int) = {
  a + b
}

val f:(Int, Int) => Int = add // f is a function type: (Int, Int) => Int
println("f:" + f(2, 3))
{% endhighlight %}
<!-- more -->
### Symbol

在Ruby中有Symbol，在Erlang中也有Symbol(Erlang中叫Atom)。Symbol在Erlang中使用非常自然，因为其思维模式；但在scala中基于目前我还在把它当命令式语言使用，Symbol成了一个可有可无的特性。

## 语句/表达式

scala中其实没有语句。对于if/while之类都算是表达式，其处理方式同函数式语言中一样，将最后一个表达式的值作为返回值：

{% highlight scala %}	
val i = if (2 > 1) 'true else 'false
{% endhighlight %}

### 控制语句

if/while什么的同C-like language一致。

### for comprehension

这个语法特性对应着函数式语言中的List Comprehension，可以用于处理一个集合，以产出另一个集合。

{% highlight scala %}	
val r = for {
  n <- Array(1, 2, 3, 4, 5)
  if n % 2 == 0
} yield n
r map println
{% endhighlight %}

这个例子同Erlang中的：

{% highlight erlang %}
[N || N <- [1, 2, 3, 4, 5], N rem 2 == 0].
{% endhighlight %}

for中的generator在实践中也比较有用，相当于foreach：

{% highlight scala %}	
for (i <- Array(1, 2, 3, 4)) println(i)
{% endhighlight %}

### pattern match

pattern match同Erlang中一样，可以简单地当switch...case来用，但用途远不止于对整数值的匹配。pattern match同样有返回值，其返回值为匹配成功块的值。

最简单的匹配：

{% highlight scala %}	
println(1 match { 
  case 1 => "one" 
  case 2 => "two" 
  case _ => "unknown" })
{% endhighlight %}

对类型进行匹配：

{% highlight scala %}	
val obj:Any = null
println(obj match {
  case t:Int => "int"
  case t:String => "string"
  case _ => "unknown"
})
{% endhighlight %}

更有用的是提取list/tuple之类集合里的元素。通过一个match...case才能匹配出list/tuple里的元素（当然也可以通过一些函数来提取），多少有点累赘：

{% highlight scala %}	
("hello", 110) match {
  case (str, _) => println(str)
  case _ => println("unknown")
}

List("hello", 110, 'sym) match {
  case List(_, _, s) => println(s)
  case _::n::_ => println(n) // head::tail
}
{% endhighlight %}

例子中还体现了scala对于list的处理能力，果然包含了函数式语言的特性。

### Guard

函数式语言里为了支持if，一般都会有Guard的概念。其用于进行条件限定，在scala中的for comprehension和pattern match中四处可见：

{% highlight scala %}	
val obj:Any = "hello"
println(obj match {
  case t:Int => "int"
  case t:String if t == "hello" => "world" // guard
  case t:String => "hello"
  case _ => "unknown"
})
{% endhighlight %}

## trait/abstract type

trait可以用于实现mix-in，虽然可以简单地将它视为interface，但它的功能远不止于此：

简单的应用：

{% highlight scala %}	
trait Show {
  def show(s:String) = println(s)
}

abstract class Widget
class MyClass extends Widget with Show {
  override def show(s:String) = println("MyClass " + s)
}

val t:Show = new MyClass
t show "hello" // 等同于t.show("hello")，scala中支持这种函数调用，可应用于构建DSL

{% endhighlight %}

以上例子显现不出trait的作用。trait为了支持“混入(mixin)“，**语法上允许在创建一个对象时，混入一个trait**，而不用在类定义时混入：

{% highlight scala %}	
trait Show {
  def show(s:String) = println(s)
}

class Person(val name:String) {
}

val person = new Person("kevin") with Show // 混入Show到person中
person.show(person.name) // person拥有show接口

{% endhighlight %}

## class

class方面的语法可以简单关注些常用的语法，trait一节中的例子已经显示了class定义方面的一些语法：

{% highlight scala %}	

class Person(val name:String) { // primary constructor，参数作为类成员
  val address = "earth" // 另一个成员，默认的可见属性
  var id:Int = 0
  private val email = "kevinlynx at gmail dot com" // private成员

  id = randid // 类体一定程度上作为primary constructor函数体 

  def fullname = println(name + " lynx") // 接口
  
  def this() = this("ah") // 0个或多个auxiliary constructor，可以调用primary constructor
  
  def randid:Int = 2
}

val p = new Person
println(p.fullname)
println(p.id)

{% endhighlight %}

面向对象语法在scala中占有很大的比例，除了基本类语法外，还有很多类相关的语法，例如`companion classes`、`case classes`等。

## object

object类似于类，类可以有很多实例化出很多对象，但object则只有一个实例，其更像一个语言内置的单件模式。scala中任意object，只要包含了main接口，即可作为一个程序的入口：

{% highlight scala %}	
object Test {
  val i = 100
  val str = "hello"	

  def main(args:Array[String]) = {
    println(i)
  }
}
println(Test.str)

{% endhighlight %}

## functions

首先，函数定义是可以嵌套的。

函数相关的语法里这里只关注几个重要的函数式风格的语法，包括：偏函数(partial function)、柯里化(currying)等。

### partial functions

简单来说就是将多参数的函数转换为某个参数为固定值的函数：

{% highlight scala %}	
def concatUpper(s1:String, s2:String):String = (s1 + " " + s2).toUpperCase

val c1 = concatUpper _ // now c1 is a function value, type: (String, String) => String
println(c1("short", "pants"))
val c2 = concatUpper("short", _:String)
println(c2("pants")) 
{% endhighlight %}

### currying

函数柯里化同偏函数一定程度上具有相同的作用。scala里柯里化函数的语法不同：

{% highlight scala %}	
def multiplier(i:Int)(factor:Int) = i * factor

// 当然也可以将一个普通函数转换为柯里化版本
val catVal = concatUpper _
val curryCat = catVal.curried // 2.10中curry，以前是用Function.curried
val catLeft = curryCat("hello")
println(catLeft("world"))

{% endhighlight %}

### call by name

函数参数传递中的call by name特性，有点类似于惰性计算，即在使用到参数的时候才计算该参数，而不是在调用函数之前就把参数值计算好。

{% highlight scala %}	
def show(s: => String) = { // 指定s call by name
  println("show get called")
  println("argument:" + s)
}
def getStr = {
  println("getStr get called") 
  "hello"
}
show(getStr)
{% endhighlight %}

给我印象较深的是，通过call by name语法，**可以实现一个如同while的函数**：

{% highlight scala %}	
def myWhile(cond: => Boolean)(f: => Unit) {
  if (cond) { 
    f
    myWhile(cond)(f)
  }
}

var count = 0
// WTF ?
myWhile(count < 3) {
  println("in while")
  count += 1
}
{% endhighlight %}

## other

scala中有那么一些语法，虽然不是什么很大的特性，但很会给人留下深刻的印象。structural types和parameterized types有点像C++里的模板，前者约定拥有相同接口的类型，后者则只表示一种类型。

### structural types

用来表示所有拥有某个相同原型接口的类型：

{% highlight scala %}	
// 相当于C中的typedef，定义一个structural types类型，需要包含名为show的接口
type MyType = { def show():Unit } 
class ClassA {
  def show():Unit = {
    println("ClassA")
  }
}
class ClassB {
  def show():Unit = {
    println("ClassB")
  }
}
var obj:MyType = null
obj = new ClassA
obj.show
obj = new ClassB
obj.show

{% endhighlight %}

虽然ClassA/ClassB没有任何关系，但因为都包含了一个`show`接口，则可以通过一个统一的类型将其统一起来。

### parameterized types

基本类似于C++模板，但仅限于类型信息，适合定义类似C++ STL的容器：

{% highlight scala %}	
class Vector[T](var a:T, var b:T) {
}
val v = new Vector[Int](1, 2)
println(v.a + ":" + v.b)
{% endhighlight %}

## 小结

目前基于JVM的语言有很多，基于JVM的好处是可以使用Java社区丰富的库、框架。scala的语法还算优美，值得一试。希望能有机会投入到更大的项目中使用。

