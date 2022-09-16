---
layout: post
title: "RequireJS最简实现"
category: javascript
tags: requirejs
comments: true
---

网上有不少解析RequireJS源码的文章，我觉得意义不大。阅读源代码的目的不是为了熟悉代码，而是为了学习核心实现原理。相对RequireJS的源码，[kitty.js](https://github.com/zengjialuo/kittyjs)的实现更简单，更容易理解。本文正是抄了kitty.js的实现，是一个更精简的RequireJS，用于理解RequireJS的实现原理。

[github dummy-requirejs](https://github.com/kevinlynx/dummy-requirejs)。这个实现仅支持核心feature：

```
require(deps, callback) // deps 是依赖数组
define(id, deps, factory) // factory是一个函数

```

例子参考git中rect.js/main.js。

从实现来看，require/define是基本一致的，require的callback等同于define的factory：都会要求deps被加载且被执行，获得deps的exports作为整个module传入callback/factory。不同的是，factory的返回值会被作为define出来的模块的export，可被视为模块本身；而callback返回值被忽略。

从用法来看，define仅是定义了模块，这个模块可能被作为deps被其他模块依赖，但define传入的factory此时是不执行的；而require则会触发各个模块的factory执行。
<!-- more -->
## 实现

主要实现分为3部分内容，其中关键的地方在于模块载入。

### 数据结构

既然是模块加载器，并且需要处理模块之间的依赖问题，所以设置一个哈希表保存所有的模块。

```
var mods = {} // <id, Module>

function Module(id) {
    var mod = this
    mod.id = id
    mod.uri = id // 简单起见，根据id拼出uri: abc.js
    mod.deps = []  // 依赖的模块id列表
    mod.factory = blank // 定义模块时的factory
    mod.callback = blank // 模块加载完毕后回调
    mod.exports = {} // 模块导出的对象
}

```

define的实现就比较简单，主要就是往`mods`里添加一个`Module`对象，简单来说就是：

```
function define(id, deps, factory) {
    var mod = getModule(id) // mods存在就返回，否则就往mods里新增
    mod.deps = deps
    mod.factory = factory
}

```
### 模块载入

遇到require时就会产生模块载入的动作。模块载入时可能发生以下动作：

* 往页面添加script标签以让浏览器从服务端拉取js文件
* js文件中可能遇到define从而立即添加模块 (非AMD模块不考虑)
* define定义的模块可能有其他依赖模块，递归载入这些模块，直到所有模块载入完毕

这里的模块载入只是把模块js文件载入到浏览器环境中。以上过程对应的大概代码为：

```
Module.prototype.load = function() {
    var mod = this
    if (mod.status == STATUS.FETCHING) return
    if (mod.status == STATUS.UNFETCH) {
        return mod.fetch() // 添加script标签从服务端拉取文件
    }
    mod.status = STATUS.LOADING
    mod.remain = mod.deps.length // 所有依赖载入完毕后通知回调
    function callback() {
        mod.remain--
        if (mod.remain === 0) {
            mod.onload() // 通知回调
        }
    }
    each(mod.deps, function (dep) {
        var m = getModule(dep)  // 获取依赖模块对象，依赖模块可能已经被载入也可能没有
        if (m.status >= STATUS.LOADED || m.status == STATUS.LOADING) { // 已经载入
            mod.remain--
            return
        }
        m.listeners.push(callback)
        if (m.status < STATUS.LOADING) {
            m.load()
        }
    })
    if (mod.remain == 0) {
        mod.onload()
    }
}

```

`load`的实现由于混合了异步问题，所以理解起来会有点难。`fetch`的实现就是一般的往页面添加script及设置回调的过程。在fetch完毕后会重新调用`load`以完成递归载入该模块的依赖：

```
// 该函数回调时，该js文件已经被浏览器执行，其内容包含define则会添加模块（当然已经被添加过了）
// 可以回头看上面的define调用的是getModule，此时会重新设置deps/factory等属性
function onloadListener() {
    var readyState = script.readyState;
    if (typeof readyState === 'undefined' || /^(loaded|complete)$/.test(readyState)) {
        mod.status = STATUS.FETCHED
        mod.load()
    }
}

```

### 模块生效

模块载入后模块其实还没生效，还无法使用模块中定义的各种符号。要让模块生效，就得执行模块定义的factory函数。在直接间接依赖的模块被全部载入完成后，最终回调到我们的callback。此时可以看看require的实现：

```
// 前面提到require/define实现类似，所以这里创建了Module对象，只是复用代码
function require(deps, callback) {
    var mod = new Module(getId())
    mod.deps = deps
    mod.factory = callback
    mod.callback = function () {
        mod.exec()
    }
    mod.status = STATUS.FETCHED
    mod.load()
}

```

就是简单地调用了`load`，完成后调用了`exec`。`exec`又是一个涉及到递归的函数，它会递归执行所有模块的factory。factory的执行需要各个模块的exports对象，只有模块exec后才会得到exports对象。

```
Module.prototype.exec = function() {
    var mod = this
    if (mod.status >= STATUS.EXECUTED) { return mod.exports }
    // 获取依赖模块的exports列表
    var args = mod.getDepsExport()
    var ret = mod.factory.apply(null, args)
    // factory 返回值作为该模块的exports
    mod.exports = ret 
    mod.status = STATUS.EXECUTED
    return mod.exports
}

```

上面的代码主要是实现这样的功能：

```
// 将依赖[d1, d2]的exports作为参数d1,d2传入
define('my-module', ['d1', 'd2'], function (d1, d2) {
    return {func: function() {}}
})
```

`getDepsExport`就是一个取依赖模块exports的过程：


```
Module.prototype.getDepsExport = function() {
    var mod = this
    var exports = []
    var deps = mod.deps
    var argsLen = mod.factory.length < deps.length ? mod.factory.length : deps.length
    for (var i = 0; i < argsLen; i++) {
        exports.push(mod.require(deps[i]))
    }
    return exports
}
```

`Module.require(id)`用于exec目标模块并返回其exports：


```
Module.prototype.require = function(dep) {
    // 由于之前已经递归载入过所有模块，所以该依赖模块必然是已经存在的，可以被exec的
    var mod = getModule(dep)
    return mod.exec()
}
```

于是又回到了`exec`，实现了递归执行所有依赖模块的功能。`exec`主要是获取依赖模块exports并调用factory，所以最初的require将用户的callback作为factory传入那个临时Module，最终使得调用到用户的callback。


通过以上过程，实际上就已经走通了从define到require实现的整个过程。整个代码不到200行。基于此可以添加更多RequireJS的附加功能。完。


