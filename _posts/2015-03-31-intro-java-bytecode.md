---
layout: post
title: "初识JVM byte code"
category: java
comments: true
---

关于JVM和其上的byte code，网上其实有足够多的资料了，我这里就简单做个提纲和介绍，权当记录吧。

## stack-based VM

Java byte code运行在JVM上，就像机器指令运行在物理机上，是需要遵循这个机器的指令规范的。所以认识JVM byte code，是需要稍微了解下JVM的。JVM是一个基于栈(stack-based)的虚拟机。很久以前我还写过类似[简单的虚拟机](http://www.cppblog.com/kevinlynx/archive/2010/04/15/112704.html)。

基于栈的虚拟机其操作数和指令运算的中间结果全部都在一个虚拟栈中，与之对应的是基于寄存器(register-based)的虚拟机，其操作数和指令运算结果会存放在若干个寄存器（也就是存储单元）里。x86机器就可以理解为基于寄存器的机器。

byte code其实和x86汇编代码本质一样，无非是对应机器制定的一堆指令，这里可以举例说明下两类虚拟机的不同：

    # stack-based 
    push 1       # 压立即数1到栈顶
    push 2       # 压立即数2到栈顶
    add          # 弹出栈顶2个数相加，将结果3压到栈顶

    # register-based
    mov ax, 1    # 写立即数到寄存器ax
    add ax, 2    # 取ax中的值1与立即数2进行相加，存放结果到ax

关于两类实现的比较，网上也有不少资料，例如[Dalvik 虚拟机和 Sun JVM 在架构和执行方面有什么本质区别？](http://www.zhihu.com/question/20207106)。
<!-- more -->

*至于有人说基于栈的虚拟机更利于移植，我不是很理解，因为即使是基于寄存器的实现，也不一定真的必须把这些寄存器映射到物理机CPU上的寄存器，使用内存来模拟性能上跟基于栈的方式不是八九不离十吗？*

了解了JVM的这个特点，JVM上的各种指令就可以更好地理解，如果要理解JVM如何运行byte code的，那还需要了解JVM内部的各种结构，例如符号解析、class loader、内存分配甚至垃圾回收等。这个以后再谈。

## byte-code

`*.class`文件就已经是编译好的byte code文件，就像C/C++编译出来的目标文件一样，已经是各种二进制指令了。这个时候可以通过JDK中带的`javap`工具来反汇编，以查看对应的byte code。

{% highlight java %}
    // Test.java
    public class Test {
        public static void main(String[] args) {
            int a = 0xae;
            int b = 0x10;
            int c = a + b;
            int d = c + 1;
            String s;
            s = "hello";
        }
    }
{% endhighlight %}

编译该文件：`javac Test.java`得到`Test.class`，然后`javap -c Test`即得到：

    Compiled from "Test.java"
    public class Test {
      public Test();
        Code:
           0: aload_0
           1: invokespecial #1                  // Method java/lang/Object."<init>":()V
           4: return

      public static void main(java.lang.String[]);
        Code:
           0: sipush        174           # push a short onto the stack 0xae=174
           3: istore_1                    # store int value into variable 1: a = 0xae
           4: bipush        16            # push a byte onto the stack 0x10=16
           6: istore_2                    # store int value into variable 2: b = 0x10
           7: iload_1                     # load value from variable 1 and push onto the stack
           8: iload_2                   
           9: iadd                        # add two ints: a + b
          10: istore_3                    # c = a + b
          11: iload_3                     
          12: iconst_1                    # 1
          13: iadd                        # c + 1
          14: istore        4             # d = c + 1
          16: ldc           #2                  // String hello
          18: astore        5
          20: return
    }

这个时候对照着JVM指令表看上面的代码，比起x86汇编浅显易懂多了，秒懂，参考[Java bytecode instruction listings](http://en.wikipedia.org/wiki/Java_bytecode_instruction_listings)。JVM中每个指令只占一个字节，操作数是变长的，所以其一条完整的指令（操作码+操作数）也是变长的。上面每条指令前都有一个偏移，实际是按字节来偏移的。*想起Lua VM的指令竟然是以bit来干的*

从上面的byte code中，以x86汇编的角度来看会发现一些不同的东西：

* 局部变量竟是以索引来区分：`istore_1` 写第一个局部变量，`istore_2`写第二个局部变量，第4个局部变量则需要用操作数来指定了：`istore 4`
* 函数调用`invokespecial #1`竟然也是类似的索引，这里调用的是`Object`基类构造函数
* 常量字符串也是类似的索引：`ldc #2`
* `*.class`中是不是也分了常量数据段和代码段呢

以上需要我们进一步了解`*.class`文件的格式。

## class file format

class 文件格式网上也有讲得很详细的了，例如这篇[Java Class文件详解](http://www.importnew.com/15161.html)。整个class文件完全可以用以下结构来描述：

    ClassFile {
        u4 magic;                                        //魔数
        u2 minor_version;                                //次版本号
        u2 major_version;                                //主版本号
        u2 constant_pool_count;                          //常量池大小
        cp_info constant_pool[constant_pool_count-1];    //常量池
        u2 access_flags;                                 //类和接口层次的访问标志（通过|运算得到）
        u2 this_class;                                   //类索引（指向常量池中的类常量）
        u2 super_class;                                  //父类索引（指向常量池中的类常量）
        u2 interfaces_count;                             //接口索引计数器
        u2 interfaces[interfaces_count];                 //接口索引集合
        u2 fields_count;                                 //字段数量计数器
        field_info fields[fields_count];                 //字段表集合
        u2 methods_count;                                //方法数量计数器
        method_info methods[methods_count];              //方法表集合
        u2 attributes_count;                             //属性个数
        attribute_info attributes[attributes_count];     //属性表
    }

这明显已经不是以区段来分的格式了，上面提到的函数索引、常量字符串索引，都是保存在`constant_pool`常量池中。常量池中存储了很多信息，包括：

* 各种字面常量，例如字符串
* 类、数据成员、接口引用 

常量池的索引从1开始。对于上面例子`Test.java`，可以使用`javap -v Test`来查看其中的常量池，例如：

    Constant pool:
       #1 = Methodref          #4.#13         //  java/lang/Object."<init>":()V
       #2 = String             #14            //  hello
       #3 = Class              #15            //  Test
       #4 = Class              #16            //  java/lang/Object
       #5 = Utf8               <init>
       #6 = Utf8               ()V
       #7 = Utf8               Code
       #8 = Utf8               LineNumberTable
       #9 = Utf8               main
      #10 = Utf8               ([Ljava/lang/String;)V
      #11 = Utf8               SourceFile
      #12 = Utf8               Test.java
      #13 = NameAndType        #5:#6          //  "<init>":()V
      #14 = Utf8               hello
      #15 = Utf8               Test
      #16 = Utf8               java/lang/Object

每一个类都会有一个常量池。

## summary

要想了解JVM运行byte code，还需要了解更多JVM本身的东西，例如符号解析，内存管理等，可参考：

* [JVM Internals](http://blog.jamesdbloom.com/JVMInternals.html)
* [Understanding JVM Internals](http://www.cubrid.org/blog/dev-platform/understanding-jvm-internals/)

