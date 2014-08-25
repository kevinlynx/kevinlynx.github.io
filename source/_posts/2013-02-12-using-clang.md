---
layout: post
title: "使用Clang实现C语言编程规范检查"
description: ""
categories: [clang, c/c++]
tags: clang
comments: true
keywords: clang, static checker
description: 本文使用clang实现了一个c语言的编程规范检查工具
---

## 概述

Clang是LLVM编译器工具集的前端部分，也就是涵盖词法分析、语法语义分析的部分。而LLVM是Apple在Mac OS上用于替代GCC工具集的编译器软件集合。Clang支持类C语言的语言，例如C、C++、Objective C。Clang的与众不同在于其模块化的设计，使其不仅实现编译器前端部分，并且包装成库的形式提供给上层应用。使用Clang可以做诸如语法高亮、语法检查、编程规范检查方面的工作，当然也可以作为你自己的编译器前端。

编程规范一般包含编码格式和语义规范两部分。编码格式用于约定代码的排版、符号命名等；而语义规范则用于约定诸如类型匹配、表达式复杂度等，例如不允许对常数做逻辑运算、检查变量使用前是否被赋值等。本文描述的主要是基于语义方面的检查，其经验来自于最近做的一个检查工具，该工具实现了超过130条的规范。这份规范部分规则来自于[MISRA C](http://en.wikipedia.org/wiki/MISRA_C)

## 编程模式 

编译器前端部分主要是输出代码对应的抽象语法树(AST)。Clang提供给上层的接口也主要是围绕语法树来做操作。通过google一些Clang的资料，你可能会如我当初一样对该如何正确地使用Clang心存疑惑。我最后使用的方式是基于RecursiveASTVisitor。这是一种类似回调的使用机制，通过提供特定语法树节点的接口，Clang在遍历语法树的时候，在遇到该节点时，就会调用到上层代码。不能说这是最好的方式，但起码它可以工作。基于RecursiveASTVisitor使用Clang，程序主体框架大致为：
<!-- more -->
{% highlight c++ %}
{% raw %}
// 编写你感兴趣的语法树节点访问接口，例如该例子中提供了函数调用语句和goto语句的节点访问接口
class MyASTVisitor : public RecursiveASTVisitor<MyASTVisitor> {
public:
    bool VisitCallExpr(CallExpr *expr);

    bool VisitGotoStmt(GotoStmt *stmt);
    ...
};

class MyASTConsumer : public ASTConsumer {
public:
    virtual bool HandleTopLevelDecl(DeclGroupRef DR) {
        for (DeclGroupRef::iterator b = DR.begin(), e = DR.end(); b != e; ++b) {
            Visitor.TraverseDecl(*b);
        }
        return true;
    } 
    
private:
    MyASTVisitor Visitor;
};

int main(int argc, char **argv) {
    CompilerInstance inst;
    Rewriter writer;
    inst.createFileManager();
    inst.createSourceManager(inst.getFileManager());
    inst.createPreprocessor();
    inst.createASTContext();
    writer.setSourceMgr(inst.getSourceManager(), inst.getLangOpts());
    ... // 其他初始化CompilerInstance的代码
  
    const FileEntry *fileIn = fileMgr.getFile(argv[1]);
    sourceMgr.createMainFileID(fileIn);
    inst.getDiagnosticClient().BeginSourceFile(inst.getLangOpts(), &inst.getPreprocessor());
    MyASTConsumer consumer(writer);
    ParseAST(inst.getPreprocessor(), &consumer, inst.getASTContext());
    inst.getDiagnosticClient().EndSourceFile();
    return 0;
}
{% endraw %}
{% endhighlight %}

以上代码中，ParseAST为Clang开始分析代码的主入口，其中提供了一个ASTConsumer。每次分析到一个顶层定义时(Top level decl)就会回调MyASTConsumer::HandleTopLevelDecl，该函数的实现里调用MyASTVisitor开始递归访问该节点。这里的`decl`实际上包含定义。

这里使用Clang的方式来源于[Basic source-to-source transformation with Clang](http://eli.thegreenplace.net/2012/06/08/basic-source-to-source-transformation-with-clang/)。

## 语法树

Clang中视所有代码单元为语句(statement)，Clang中使用类`Stmt`来代表statement。Clang构造出来的语法树，其节点类型就是`Stmt`。针对不同类型的语句，Clang有对应的`Stmt`子类，例如`GotoStmt`。Clang中的表达式也被视为语句，Clang使用`Expr`类来表示表达式，而`Expr`本身就派生于`Stmt`。

每个语法树节点都会有一个子节点列表，在Clang中一般可以使用如下语句遍历一个节点的子节点：

{% highlight c++ %}
{% raw %}
for (Stmt::child_iterator it = stmt->child_begin(); it != stmt->child_end(); ++it) {
    Stmt *child = *it;
}
{% endraw %}
{% endhighlight %}

但遗憾的是，无法从一个语法树节点获取其父节点，这将给我们的规范检测工具的实现带来一些麻烦。

### TraverseXXXStmt

在自己实现的Visitor中（例如MyASTVisitor），除了可以提供VisitXXXStmt系列接口去访问某类型的语法树节点外，还可以提供TraverseXXXStmt系列接口。Traverse系列的接口包装对应的Visit接口，即他们的关系大致为：

{% highlight c++ %}
{% raw %}
bool TraverseGotoStmt(GotoStmt *s) {
    VisitGotoStmt(s);
    return true;
}
{% endraw %}
{% endhighlight %}

例如对于GotoStmt节点而言，Clang会先调用TraverseGotoStmt，在TraverseGotoStmt的实现中才会调用VisitGotoStmt。利用Traverse和Visit之间的调用关系，我们可以解决一些因为不能访问某节点父节点而出现的问题。例如，我们需要限制逗号表达式的使用，在任何地方一旦检测到逗号表达式的出现，都给予警告，除非这个逗号表达式出现在for语句中，例如：

{% highlight c++ %}
{% raw %}
a = (a = 1, b = 2); /* 违反规范，非法 */
for (a = 1, b = 2; a < 2; ++a) /* 合法 */
{% endraw %}
{% endhighlight %}

逗号表达式对应的访问接口为VisitBinComma，所以我们只需要提供该接口的实现即可：

{% highlight c++ %}
{% raw %}
class MyASTVisitor : public RecursiveASTVisitor<MyASTVisitor> {
public:
    ...
    bool VisitBinComma(BinaryOperator *stmt) {
        /* 报告错误 */
        return true;
    }
    ...
};
{% endraw %}
{% endhighlight %}

（注：BinaryOperator用于表示二目运算表达式，例如a + b，逗号表达式也是二目表达式）

但在循环中出现的逗号表达式也会调用到VisitBinComma。为了有效区分该逗号表达式是否出现在for语句中，我们可以期望获取该逗号表达式的父节点，并检查该父节点是否为for语句。但Clang并没有提供这样的能力，我想很大一部分原因在于臆测语法树（抽象语法树）节点的组织结构（父节点、兄弟节点）本身就不是一个确定的事。

这里的解决办法是通过提供TraverseForStmt，以在进入for语句前得到一个标识：


{% highlight c++ %}
{% raw %}
class MyASTVisitor : public RecursiveASTVisitor<MyASTVisitor> {
public:
    ...
    // 这个函数的实现可以参考RecursiveASTVisitor的默认实现，我们唯一要做的就是在for语句的头那设定一个标志m_inForLine
    bool TraverseForStmt(ForStmt *s) {
        if (!WalkUpFromForStmt(s))
            return false;
        m_inForLine = true;
        for (Stmt::child_range range = s->children(); range; ++range) {
            if (*range == s->getBody())
                m_inForLine = false;
            TraverseStmt(*range);
        }
        return true;
    }

    bool VisitBinComma(BinaryOperator *stmt) {
        if (!m_inForLine) {
            /* 报告错误 */
        }
        return true;
    }
    ...
};
{% endraw %}
{% endhighlight %}

（注：严格来说，我们必须检查逗号表达式是出现在for语句的头中，而不包括for语句循环体）

## 类型信息

对于表达式(`Expr`)而言，都有一个类型信息。Clang直接用于表示类型的类是`QualType`，实际上这个类只是一个接口包装。这些类型信息可以用于很多类型相关的编程规范检查。例如不允许定义超过2级的指针(例如int ***p)：

{% highlight c++ %}
{% raw %}
bool MyASTVisitor::VisitVarDecl(VarDecl *decl) { // 当发现变量定义时该接口被调用
    QualType t = decl->getType(); // 取得该变量的类型
    int pdepth = 0;
    // check pointer level
    for ( ; t->isPointerType(); t = t->getPointeeType()) { // 如果是指针类型就获取其指向类型(PointeeType)
        ++pdepth;
    }
    if (pdepth >= 3)
        /* 报告错误 */
}
{% endraw %}
{% endhighlight %}

可以直接调用`Expr::getType`接口，用于获取指定表达式最终的类型，基于此我们可以检查复杂表达式中的类型转换，例如：

{% highlight c++ %}
{% raw %}
float f = 2.0f;
double d = 1.0;
f = d * f; /* 检查此表达式 */
{% endraw %}
{% endhighlight %}

对以上表达式的检查有很多方法，你可以实现MyASTVisitor::VisitBinaryOperator（只要是二目运算符都会调用），或者MyASTVisitor::VisitBinAssign（赋值运算=调用）。无论哪种方式，我们都可以提供一个递归检查两个表达式类型是否相同的接口：

{% highlight c++ %}
{% raw %}
bool HasDiffType(BinaryOperator *stmt) {
    Expr *lhs = stmt->getLHS()->IgnoreImpCasts(); // 忽略隐式转换
    Expr *rhs = stmt->getRHS()->IgnoreImpCasts();
    if (lhs->getType() == rhs->getType())) {
        if (isa<BinaryOperator>(lhs) && HasDiffType(cast<BinaryOperator>(lhs)))
            return true;
        if (isa<BinaryOperator>(rhs) && HasDiffType(cast<BinaryOperator>(rhs)))
            return true;
        return false;
    }
    return true;
}
{% endraw %}
{% endhighlight %}

（注：此函数只是简单实现，未考虑类型修饰符之类的问题）

该函数获得二目运算表达式的两个子表达式，然后递归检测这两个表达式的类型是否相同。

`Expr`类提供了更多方便的类型相关的接口，例如判定该表达式是否为常数，是否是布尔表达式，甚至在某些情况下可以直接计算得到值。例如我们可以检查明显的死循环:

{% highlight c++ %}
{% raw %}
while (1) { }
{% endraw %}
{% endhighlight %}

可以使用：

{% highlight c++ %}
{% raw %}
ASTContext &context = inst.GetASTContext();
bool result;
// 假设stmt为WhileStmt
if (stmt->getCond()->EvaluateAsBooleanCondition(result, context)) {
    if (result) 
        /* 死循环 */
{% endraw %}
{% endhighlight %}



## 符号表

符号表这个概念比较广义，这里我仅指的是用于保存类型和变量信息的表。Clang中没有显示的符号表数据结构，但每一个定义都有一个`DeclContext`，`DeclContext`用于描述一个定义的上下文环境。有一个特殊的`DeclContext`被称为`translation unit decl`，其实也就是全局环境。利用这个translation unit decl，我们可以获取一些全局符号，例如全局变量、全局类型：

{% highlight c++ %}
{% raw %}
// 获取全局作用域里指定名字的符号列表
DeclContext::lookup_result GetGlobalDecl(const std::string &name) {
    ASTContext &context = CompilerInst::getSingleton().GetASTContext();
    DeclContext *tcxt = context.getTranslationUnitDecl();
    IdentifierInfo &id = context.Idents.get(name);
    return tcxt->lookup(DeclarationName(&id));
}

// 可以根据GetGlobalDecl的返回结果，检查该列表里是否有特定的定义，例如函数定义、类型定义等
bool HasSpecDecl(DeclContext::lookup_result ret, Decl::Kind kind) {
    for (size_t i = 0; i < ret.size(); ++i) {
        NamedDecl *decl = ret[i];
        if (decl->getKind() == kind) {
            return true;
        }
    }
    return false;
}
{% endraw %}
{% endhighlight %}

有了以上两个函数，我们要检测全局作用域里是否有名为"var"的变量定义，就可以：

{% highlight c++ %}
{% raw %}
HasSpecDecl(GetGlobalDecl("var"), Decl::Var);
{% endraw %}
{% endhighlight %}

每一个`Decl`都有对应的`DeclContext`，要检查相同作用域是否包含相同名字的符号，其处理方式和全局的方式有点不一样：

{% highlight c++ %}
{% raw %}
// 检查在ctx中是否有与decl同名的符号定义
bool HasSymbolInContext(const NamedDecl *decl, const DeclContext *ctx) {
    for (DeclContext::decl_iterator it = ctx->decls_begin(); it != ctx->decls_end(); ++it) {
        Decl *d = *it;
        if (d != decl && isa<NamedDecl>(d) && 
            cast<NamedDecl>(d)->getNameAsString() == decl->getNameAsString())
            return true;
    }
    return false;
}

bool HasSymbolInContext(const NamedDecl *decl) {
    return HasSymbolInContext(decl, decl->getDeclContext());
}
{% endraw %}
{% endhighlight %}


可以看出，这里检查相同作用域的方式是遍历上下文环境中的所有符号，但对于全局作用域却是直接查找。对于`DeclContext`的详细信息我也不甚明了，只能算凑合使用。实际上，这里使用“作用域”一词并不准确，在C语言中的作用域概念，和这里的`context`概念在Clang中并非等同。

如果要检查嵌套作用域里不能定义相同名字的变量，例如：

{% highlight c++ %}
{% raw %}
int var;
{
    int var;
}
{% endraw %}
{% endhighlight %}

通过Clang现有的API是无法实现的。因为Clang给上层的语法树结构中，并不包含作用域信息（在Clang的实现中，用于语义分析的类Sema实际上有作用域的处理）。当然，为了实现这个检测，我们可以手动构建作用域信息（通过TraverseCompoundStmt）。


## 宏

宏的处理属于预处理阶段，并不涵盖在语法分析阶段，所以通过Clang的语法树相关接口是无法处理的。跟宏相关的接口，都是通过Clang的`Preprocessor`相关接口。Clang为此提供了相应的处理机制，上层需要往`Preprocessor`对象中添加回调对象，例如：

{% highlight c++ %}
{% raw %}
class MyPPCallback : public PPCallbacks {
public:
    // 处理#include
    virtual void InclusionDirective(SourceLocation HashLoc, const Token &IncludeTok,
        StringRef FileName, bool IsAngled, CharSourceRange FilenameRange,
        const FileEntry *File, StringRef SearchPath, StringRef RelativePath, const Module *Imported) {
    }

    // 处理#define
    virtual void MacroDefined(const Token &MacroNameTok, const MacroInfo *MI) {
    }

    virtual void MacroUndefined(const Token &MacroNameTok, const MacroInfo *MI) {
    } 
}

inst.getPreprocessor().addPPCallbacks(new MyPPCallback());
{% endraw %}
{% endhighlight %}

即，通过实现`PPCallbacks`中对应的接口，就可以获得处理宏的通知。

Clang使用MacroInfo去表示一个宏。MacroInfo将宏体以一堆token来保存，例如我们要检测宏体中使用`##`和`#`的情况，则只能遍历这些tokens:

{% highlight c++ %}
{% raw %}
// 分别记录#和##在宏体中使用的数量
int hash = 0, hashhash = 0;
for (MacroInfo::tokens_iterator it = MI->tokens_begin(); it != MI->tokens_end(); ++it) {
    const Token &token = *it;
    hash += (token.getKind() == tok::hash ? 1 : 0);
    hashhash += (token.getKind() == tok::hashhash ? 1 : 0);
}
{% endraw %}
{% endhighlight %}

## 其他

在我们所支持的编程规范中，有些规范是难以支持的，因此我使用了一些蹩脚的方式来实现。

### 手工解析

在针对函数的参数定义方面，我们支持的规范要求不能定义参数为空的函数，如果该函数没有参数，则必须以`void`显示标识，例如：

{% highlight c++ %}
{% raw %}
int func(); /* 非法 */
int func(void); /* 合法 */
{% endraw %}
{% endhighlight %}

对于Clang而言，函数定义（或声明）使用的是`FunctionDecl`，而Clang记录的信息仅包括该函数是否有参数，参数个数是多少，并不记录当其参数个数为0时是否使用`void`来声明（记录下来没多大意义）。解决这个问题的办法，可以通过`SourceLocation`获取到对应源代码中的文本内容，然后对此文本内容做手工分析即可。

（注：`SourceLocation`是Clang中用于表示源代码位置的类，包括行号和列号，所有`Stmt`都会包含此信息）

通过`SourceLocation`获取对应源码的内容：

{% highlight c++ %}
{% raw %}
std::pair<FileID, unsigned> locInfo = SM.getDecomposedLoc(loc);
bool invalidTemp = false;
llvm::StringRef file = SM.getBufferData(locInfo.first, &invalidTemp);
if (invalidTemp)
    return false;
// tokenBegin即为loc对应源码内容的起始点
const char *tokenBegin = file.data() + locInfo.second;
{% endraw %}
{% endhighlight %}

要手工分析这些内容实际上还是有点繁杂，为此我们可以直接使用Clang中词法分析相关的组件来完成这件事：

{% highlight c++ %}
{% raw %}
Lexer *lexer = new Lexer(SM.getLocForStartOfFile(locInfo.first), opts, file.begin(), tokenBegin, file.end());
Token tok;
lexer->Lex(tok); // 取得第一个tok，反复调用可以获取一段token流
{% endraw %}
{% endhighlight %}

### Diagnostic

Clang中用Diagnostic来进行编译错误的提示。每一个编译错误（警告、建议等）都会有一段文字描述，这些文字描述为了支持多国语言，使用了一种ID的表示方法。总之，对于一个特定的编译错误提示而言，其diagnostic ID是固定的。

在我们的规范中，有些规范检测的代码在Clang中会直接编译出错，例如函数调用传递的参数个数不等于函数定义时的形参个数。当Clang编译出错时，其语法树实际上是不完善的。解决此问题的最简单办法，就是通过diagnostic实现。也就是说，我是通过将我们的特定规范映射到特定的diagnostic，当发生这个特定的编译错误时，就可以认定该规范实际上被检测到。对于简单的情况而言，这样的手段还算奏效。


{% highlight c++ %}
{% raw %}
// `TextDiagnosticPrinter`可以将错误信息打印在控制台上，为了调试方便我从它派生而来
class MyDiagnosticConsumer : public TextDiagnosticPrinter {
public:
    // 当一个错误发生时，会调用此函数，我会在这个函数里通过Info.getID()取得Diagnostic ID，然后对应地取出规范ID
    virtual void HandleDiagnostic(DiagnosticsEngine::Level DiagLevel,
        const Diagnostic &Info) {
        TextDiagnosticPrinter::HandleDiagnostic(DiagLevel, Info);
        // 例如检查三字母词(trigraph)的使用
        if (Info.getID() == 816)
            /* 报告使用了三字母词 */
    }
};

// 初始化时需传入自己定义的diagnostic
inst.createDiagnostics(0, NULL, new MyDiagnosticConsumer(&inst.getDiagnosticOpts()));
{% endraw %}
{% endhighlight %}

该例子代码演示了对三字母词([wiki trigraph](http://en.wikipedia.org/wiki/Digraphs_and_trigraphs))使用限制的规范检测。

全文完。


