---
layout: post
title: "一次逆向网页内容加密"
category: other
tags: html
comments: true
---

最近写一个爬虫要从这个[网页](http://cpquery.sipo.gov.cn/txnQueryFeeData.do?select-key:shenqingh=2007200071873&select-key:zhuanlilx=2&select-key:gonggaobj=&select-key:backPage=http%3A%2F%2Fcpquery.sipo.gov.cn%2FtxnQueryOrdinaryPatents.do%3Fselect-key%3Ashenqingh%3D2015204531832%26select-key%3Azhuanlimc%3D%26select-key%3Ashenqingrxm%3D%26select-key%3Azhuanlilx%3D%26select-key%3Ashenqingr_from%3D%26select-key%3Ashenqingr_to%3D%26inner-flag%3Aopen-type%3Dwindow%26inner-flag%3Aflowno%3D1470846836440&inner-flag:open-type=window&inner-flag:flowno=1471142917509)爬取内容。以往爬取网页内容复杂点的，一般就是处理下页面内容动态载入，动态载入的内容可能会要求复杂奇怪的参数，或者找到这个动态载入的HTTP接口在哪里麻烦点。但是这个网页不同。类似：

```
<td><span name="record_yijiaof:feiyongzldm" title="pos||"><span id="5d299905633d4aa288b65f5bf74e414c" class="nlkfqirnlfjerldfgzxcyiuro">专</span><span id="546c73d012f74931aa5d45707121eb50" class="nlkfqirnlfjerldfgzxcyiuro">实</span><span id="e0285e05974b4577b23b2ced8e453005" class="nlkfqirnlfjerldfgzxcyiuro">新</span><span id="82b9e003de4e4577aa7617681a0d3777" class="nlkfqirnlfjerldfgzxcyiuro">用</span><span id="417aaf4c6ad14b7781db02a688a4f885" class="nlkfqirnlfjerldfgzxcyiuro">用</span><span id="a3f326efa35e4fe898d2f751e77d6777" class="nlkfqirnlfjerldfgzxcyiuro">新</span><span id="c6c5135b931c48c09c6529735f4c6434" class="nlkfqirnlfjerldfgzxcyiuro">型</span><span id="8c55b119929147ddbe178776903554e5" class="nlkfqirnlfjerldfgzxcyiuro">专</span><span id="f8e47702c9f5420198a6f9b9aa132c9c" class="nlkfqirnlfjerldfgzxcyiuro">利</span><span id="60cc2e23682e4ca2b850a92f55029458" class="nlkfqirnlfjerldfgzxcyiuro">第9年年费</span></span></td>
```

最终希望得到的内容其实是`实用新型专利第9年年费`，但是得到的网页确实乱序后的字符串，并且每次刷新得到的乱序还不一样，试过几次也看不出规律。

按照以往的思路，猜测肯定是某个js文件中包含了还原算法，我的目的，就是找出这个算法，在爬虫程序中实现这个算法，以还原出可读的字符串。

js中要完成这样的事，首先得找到网页元素，包括：根据外层span `name=record_yijiaof:feiyongzldm`；根据再外层的table；根据内层span `class='nlkfqirnlfjerldfgzxcyiuro'`。以前我一直想要个工具，可以在某网页载入的所有js文件中搜索特定字符串，从而帮助逆向，但是一直没有这个工具。所以这次也只有人肉看每个js。根据js的名字猜测这个逻辑会放在哪里。
<!-- more -->
看了几个可能的js文件，在文件中都没有搜索出我认为可能的字符串。于是我又人肉搜索其他不太可能的js文件，均未果。此时陷入死胡同。

网页文件末尾会有个超长id的span元素，类似：

```
<span style="display: none" id="3535346033366237393b6c3c38343d3e71702777202021272f28282a797f2b2f0c1910411d4016171b4d4f1f49191b18075053040204010100085b0b580e0908776d2370227674712d2f2b7879287a2935696b6b306730606d683f6c6b39686857564e00520653565b5c08525f5c0d5b4812424a17434345414e494e1a491d49b4b2b6afbce6b3b2eab8bbb2b5bfb7bea4a6f6f7f6f0a7a0a0aeadada5adadaa9595c79688c39ec29c9e9d9b9ece97c985858083858c8ed68edf83d985dcdf8ef3f3a1faa7e9f0f7abaaf8aefefef8f7e2b4e6b0b5e7b4efede9bbe2eebbebead0d3dbd7d1ddcad2d0d88fdfd88fdddc9695c6c79693c595cd9fcbcacb989f9b32303a373236372b3039383f3e34683a71262b2120237722207b2279792c2d2d1043411b131017170411181a48151a4b0307570a01015255015b5e5e5e0d0f0624767374222377232d65282f2a282c2d69656a35626362663b3d633f3f39673e53555a015c04545f505a460d5f585a5a13464015174c14434f4a49434845184fb5b9e6b5e7e4e5e1bbbdeca7eab9bdb6f6a5a4f1a4a3a0f6acaaaaadfda5aea890c4c6c696c6c797999d92c980cbc89ad5828383848dd2828e8dd88ed984d88aa1a4f0a0a5a3a3f6abf8acaaf5e1fcfce2e3b0b5edb6e6efeabbeeeabebee6eb8685d0d186848486dbd18edcd8dfc2d7c39593cac6cdc7cecaccc9cfcb9e9f9d31623b3a61303465383132336a3f372322297322702d21717a782b7d287c287e194041161417431e104d4c124e491b181c005355025153540d09025d5e090b5d727973717d75277278797c7a2f7b792a347d6061306630606d6e696d3e386a3a58575a01545351515c5b09095c0f0a5744175e10454743144a1d42484948484be3b8b5bbb7e3bfb5bdebbebdbdebb9b8a6a7f3bff2f7a3a5abffaffdafacfdab9494c193c5929196c99bcb9c94c89c9dd2818ad5988c8680d98d8fda8b8b8adca6f5f4a6a2a7a5a1faadabfcaaf8f9adb2e2b0b2e5f
```
这个字符串不像base64加密，看这个网页带了md5的js，怀疑跟md5有关，但md5不应该用来加密字符内容，js文件中也未看到可能的API。

后来发现乱序的字符串中有些字符是不显示的，通过这个css控制：

```
nlkfqirnlfjerldfgzxcyiuro {
    display: none!important;
    visibility: hidden!important;
}
```

网页载入经过js处理后，显示出来的字符看起来是相同的css class `nlkfqirnlfjer1dfgzxcyiuro`，开始觉得奇怪，研究了下这个的差异。折腾了好久发现被人戏弄了：nlkfqirnlfje**r1d**fgzxcyiuro与nlkfqirnlfje**rld**fgzxcyiuro，前一个是`r1d`后一个是`rld`，分别是数字1和字母L！WTF

原始网页中所有字符的css class都是不显示的，所以可以推测js中经过一定算法将需要显示的字符改了css class。但是此刻还是没有思路。

后来尝试了chrome的DOM breakpoint，可以在DOM元素被改变时断点，但是用起来不是特别好用，没有带来任何帮助。

绝望之际把整个网页另存下来，另存下来的网页是经过js处理后的，手工将css改回原始内容，本地载入网页发现还是可以正常显示，证明处理逻辑真的还在js文件中。然后我逐个删除每一个js文件，还是想找出具体是哪个js文件包含了这个还原算法。

然后发现竟然是jquery-1.7.2.min.js。但我想这不能说明问题，因为作者肯定是通过jQuery来获取元素的，删除jQuery.js作者的代码不能work，当然就显示不出来。这个时候我开始清理html中的js代码，发现所有js代码都被清除完后，网页内容依然可以还原，所以断定还原算法就在jQuery.js中。然而这个文件是min版本的，网上找了个还原工具，其实就是重新格式化方便阅读。

但是此刻发现在这个文件中依然搜索不到可能的字符串，例如前面提到的找元素的一些线索，如span css，如span name等等。此时重新通过chrome的DOM断点来获取调用堆栈。这次直接断css class会被改变的span元素，竟然发现可行。此时无非是断点，看效果，继续下更精确的断点，最后发现源头：

```
    b(function() {
        b.mix()
    });

    ...
    mix: function() {
        var b0 = bF("s" + "p" + "a" + "n");
        if (b0 && b0[b0.length - 1]) {
            var b5 = b0[b0.length - 1].getAttribute("i" + "d");
            if (!b5) {
                return
            }
            var b2 = "";
            var b4 = 0;
            for (var b3 = 0; b3 < b5.length; b3 += 2) {
                if (b4 > 255) {
                    b4 = 0
                }
                var b1 = parseInt(parseInt(b5.substring(b3, b3 + 2), 16) ^ b4++);
                b2 += String.fromCharCode(b1)
            }
            if (b2) {
                // ... 省略

```

首先看到的是`"s" + "p" + "a" + "n"`，这不就是`span`！看前面几行代码很快就明白这是在取网页的最后一个`span`元素，也就是那个包含超长id属性的span元素。此时需要提下，之前也是对这个页尾span元素做过实验，发现必须是span元素且为最后一个元素才能正确还原网页内容，可以推断这个span是多么关键的一个线索。感兴趣的可以把这个网页的jQuery-1.7.2.min.js还原后查看`mix`函数实现。

翻译过来还原函数非常简单，写一个java版本：

```
public static String parseSipoIds(String enStr) {
  int b4 = 0;
  StringBuilder sb = new StringBuilder();
  for (int i = 0; i < enStr.length(); i += 2) {
    if (b4 > 255) b4 = 0;
    int c = Integer.parseInt(enStr.substring(i, i + 2), 16) ^ b4++;
    sb.append((char)c);
  }
  return sb.toString();
}
```

即这个span元素就是需要显示出来的span元素id集合，以逗号分隔。

以前还爬过一个日本政府网站，防爬也是做得很过分，不过主要是配合服务器，每一个网页的url是动态变化的，且需要从最原始的网页经过一定的操作才能获得。流程复杂让人痛苦不堪，最后还是一路携带cookie，真的模拟人的操作流程走下来。具体也记不清了。

最后吐槽一下，作者把还原算法写到jQuery.js里，也真是苦费心机。

