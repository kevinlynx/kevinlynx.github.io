---
layout: post
title: "ReactJS项目中基于webpack实现页面插件"
category: javascript
tags: [reactjs]
comments: true
---

整个Web页面是基于ReactJS的，js打包用的webpack，现在想在Web页面端实现一种插件机制，可以动态载入第三方写的js插件。这个插件有一个约定的入口，插件被载入后调用该入口函数，插件内部实现渲染逻辑。插件的实现也使用了ReactJS，当然理论上也可以不使用。预期的交互关系是这样的：

```
// 主页面
load('/plugin/my-plugin.js', function (plugin) {
    plugin.init($('#plugin-main'), args)
})

// 基于ReactJS的插件
function init($elem, args) {
    ReactDOM.render((<Index />), $elem)
}
export {init}
```

在主页面上支持这种插件机制，有点类似一个应用市场，主页面作为应用平台，插件就是应用，用户可以在主页面上选用各种插件。

## 问题

目前主页面里ReactJS被webpack打包进了bundle.js，如果插件也把ReactjS打包进去，最终在载入插件后，浏览器环境中就会初始化两次ReactJS。**而ReactJS是不能被初始化多次的**。此外，为了插件编写方便，我把一些可重用的组件打包成一个单独的库，让主页面和插件都去依赖。这个库自然也不能把ReactJS打包进来。何况还有很多三方库，例如underscore、ReactDOM最好也能避免重复打包，从而可以去除重复的内容。所以，这里就涉及到如何在webpack中拆分这些库。

需要解决的问题：

* 拆分三方库，避免打包进bundle.js
* 动态载入js文件，且能拿到其module，或者至少能知道js什么时候被载入，才能调用其入口函数
<!-- more -->
关于第二个问题，我选用了RequireJS，但其实它不是用于我这种场景的，不过我不想自己写一个js载入器。用RequireJS在我这种场景下会带来一些问题：webpack在打包js文件时会检查是否有AMD模块加载器，如果有则会把打包的代码作为AMD模块来加载。对于三方库的依赖就需要做一些适配。

## 实现

开始做这件事时我是不熟悉RequireJS/AMD的，导致踩了不少坑。过程不表，这里就记录一些关键步骤。

公共组件库及插件是必须要打包为library的，否则没有导出符号：

```
// webpack.config.js
config.output = {
  filename: 'drogo_components.js',
  path: path.join(__dirname, 'dist'),
  libraryTarget: 'umd',
  library: 'drogo_components'
};

```

此外，为了不打包三方库进bundle.js，需要设置：

```
// webpack.config.js
config.externals = {
  'react': 'React',
  'underscore': '_',
};
```

`externals`中key为代码中`require`或`import xxx from 'xxx'`中的名字，value为输出代码中的名字。以上设置后，webpack打包出来的代码类似于：

```
(function webpackUniversalModuleDefinition(root, factory) {
    if(typeof exports === 'object' && typeof module === 'object')
        module.exports = factory(require("React"), require("_"));
    else if(typeof define === 'function' && define.amd)
        define(["React", "_"], factory);
...
```

了解了RequireJS后就能看懂上面的代码，意思是定义我这里说的插件或公共库为一个模块，其依赖`React`及`_`模块。

插件及公共库如何编写？

```
// 入口main.js中
import React from 'react'
import ReactDOM from 'react-dom'
import Test from './components/test'
import Index from './components/index'

function init($elem, data) {
    ReactDOM.render((<Index biz={data.biz} />), $elem)
}

export {Index, Test, init}

```

入口js中export的内容就会成为这个library被require载入后能拿到的符号。这个库在webpack中引用时同理。注意需要设置库的入口文件：

```
// package.json
  "main": "static/js/main.bundle.js",
```

对于本地库，可以通过以下方法在本地使用：

```
// 打包本地库，生成库.tgz文件
npm pack
// 切换到要使用该库的工程下安装
npm install ../xxx/xxx.tgz
```

`package.json`中也不需要依赖该文件，如果不自己install，也是可以在package.json中依赖的，类似：

```
"xxxx": "file:../xxx/xxx.tgz"
```

经过以上步骤后，在主页面中载入插件打包的bundle.js时，会得到错误，说找不到React模块。我这里并没有完全改造为RequireJS的模块，所以我在页面中是静态引入react的，即：

```
<script src="static/js/react-with-addons.js"></script>
<script src="static/js/react-dom.min.js"></script>
```

当执行插件后，RequireJS会去重新载入react.js，如果能load成功，就又会导致浏览器环境中出现两份ReactJS，解决方法是：

```
define('react', [], function() {
  return React
})

define('react-dom', [], function() {
  return ReactDOM
})

define('_', [], function () {
  return _
})
```

即，因为react被静态引入，就会存在全局变量window.React，所以这里是告诉RequireJS我们定义`react`模块就是全局变量React。此时webpack中打出的文件中`require(['react'], xx`时，就不会导致RequireJS再去从服务端载入react.js文件。

使用RequireJS后，要动态载入插件，代码就类似于：

```
window.require(['/api/plug/content/1'], function (m) {
  m.init($('#app-main')[0], args)
})
```

最后，之所以没有把页面全部改造为RequireJS，例如通过require载入主页面，主页面依赖react、公共组件库等，是因为我发现RequireJS的载入顺序与项目中使用的部分界面库有冲突，导致一些`<a>`的事件监听丢失（如下拉菜单不可用），根本原因还没找到。


