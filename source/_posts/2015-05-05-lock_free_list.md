---
layout: post
title: "无锁有序链表的实现"
category: c/c++
tags: lock free linked list
comments: true
---

无锁有序链表可以保证元素的唯一性，使其可用于哈希表的桶，甚至直接作为一个效率不那么高的map。普通链表的无锁实现相对简单点，因为插入元素可以在表头插，而有序链表的插入则是任意位置。

本文主要基于论文[High Performance Dynamic Lock-Free Hash Tables](http://www.research.ibm.com/people/m/michael/spaa-2002.pdf)实现。

## 主要问题

链表的主要操作包含`insert`和`remove`，先简单实现一个版本，就会看到问题所在，以下代码只用作示例：

{% highlight c++ %}
    struct node_t {
        key_t key;
        value_t val;
        node_t *next;
    };

    int l_find(node_t **pred_ptr, node_t **item_ptr, node_t *head, key_t key) {
        node_t *pred = head;
        node_t *item = head->next;
        while (item) {
            int d = KEY_CMP(item->key, key);
            if (d >= 0) {
                *pred_ptr = pred;
                *item_ptr = item;
                return d == 0 ? TRUE : FALSE;
            }
            pred = item;
            item = item->next;
        } 
        *pred_ptr = pred;
        *item_ptr = NULL;
        return FALSE;
    }

    int l_insert(node_t *head, key_t key, value_t val) {
        node_t *pred, *item, *new_item;
        while (TRUE) {
            if (l_find(&pred, &item, head, key)) {
                return FALSE;
            }
            new_item = (node_t*) malloc(sizeof(node_t));
            new_item->key = key;
            new_item->val = val;
            new_item->next = item;
            // A. 如果pred本身被移除了
            if (CAS(&pred->next, item, new_item)) {
                return TRUE;
            }
            free(new_item);
        }
    }

    int l_remove(node_t *head, key_t key) {
        node_t *pred, *item;
        while (TRUE) {
            if (!l_find(&pred, &item, head, key)) {
                return TRUE;
            }
            // B. 如果pred被移除；如果item也被移除
            if (CAS(&pred->next, item, item->next)) {
                haz_free(item);
                return TRUE;
            }
        }
    }
{% endhighlight %}
<!-- more -->
`l_find`函数返回查找到的前序元素和元素本身，代码A和B虽然拿到了`pred`和`item`，但在`CAS`的时候，其可能被其他线程移除。甚至，在`l_find`过程中，其每一个元素都可能被移除。问题在于，**任何时候拿到一个元素时，都不确定其是否还有效**。元素的有效性包括其是否还在链表中，其指向的内存是否还有效。

## 解决方案

**通过为元素指针增加一个有效性标志位，配合CAS操作的互斥性**，就可以解决元素有效性判定问题。

因为`node_t`放在内存中是会对齐的，所以指向`node_t`的指针值低几位是不会用到的，从而可以在低几位里设置标志，这样在做CAS的时候，就实现了DCAS的效果，相当于将两个逻辑上的操作变成了一个原子操作。想象下引用计数对象的线程安全性，其内包装的指针是线程安全的，但对象本身不是。

CAS的互斥性，在若干个线程CAS相同的对象时，只有一个线程会成功，失败的线程就可以以此判定目标对象发生了变更。改进后的代码（代码仅做示例用，不保证正确）：

{% highlight c++ %}
    typedef size_t markable_t;
    // 最低位置1，表示元素被删除
    #define HAS_MARK(p) ((markable_t)p & 0x01)
    #define MARK(p) ((markable_t)p | 0x01)
    #define STRIP_MARK(p) ((markable_t)p & ~0x01)

    int l_insert(node_t *head, key_t key, value_t val) {
        node_t *pred, *item, *new_item;
        while (TRUE) {
            if (l_find(&pred, &item, head, key)) { 
                return FALSE;
            }
            new_item = (node_t*) malloc(sizeof(node_t));
            new_item->key = key;
            new_item->val = val;
            new_item->next = item;
            // A. 虽然find拿到了合法的pred，但是在以下代码之前pred可能被删除，此时pred->next被标记
            //    pred->next != item，该CAS会失败，失败后重试
            if (CAS(&pred->next, item, new_item)) {
                return TRUE;
            }
            free(new_item);
        }
        return FALSE;
    }

    int l_remove(node_t *head, key_t key) {
        node_t *pred, *item;
        while (TRUE) {
            if (!l_find(&pred, &item, head, key)) {
                return FALSE;
            }
            node_t *inext = item->next;
            // B. 删除item前先标记item->next，如果CAS失败，那么情况同insert一样，有其他线程在find之后
            //    删除了item，失败后重试
            if (!CAS(&item->next, inext, MARK(inext))) {
                continue;
            }
            // C. 对同一个元素item删除时，只会有一个线程成功走到这里
            if (CAS(&pred->next, item, STRIP_MARK(item->next))) {
                haz_defer_free(item);
                return TRUE;
            }
        }
        return FALSE;
    }

    int l_find(node_t **pred_ptr, node_t **item_ptr, node_t *head, key_t key) {
        node_t *pred = head;
        node_t *item = head->next;
        hazard_t *hp1 = haz_get(0);
        hazard_t *hp2 = haz_get(1);
        while (item) {
            haz_set_ptr(hp1, pred);
            haz_set_ptr(hp2, item);
            /* 
             如果已被标记，那么紧接着item可能被移除链表甚至释放，所以需要重头查找
            */
            if (HAS_MARK(item->next)) { 
                return l_find(pred_ptr, item_ptr, head, key);
            }
            int d = KEY_CMP(item->key, key);
            if (d >= 0) {
                *pred_ptr = pred;
                *item_ptr = item;
                return d == 0 ? TRUE : FALSE;
            }
            pred = item;
            item = item->next;
        } 
        *pred_ptr = pred;
        *item_ptr = NULL;
        return FALSE;
    }
{% endhighlight %}

`haz_get`、`haz_set_ptr`之类的函数是一个hazard pointer实现，用于支持多线程下内存的GC。上面的代码中，要删除一个元素`item`时，会标记`item->next`，从而使得`insert`时中那个`CAS`不需要做任何调整。总结下这里的线程竞争情况：

* `insert`中`find`到正常的`pred`及`item`，`pred->next == item`，然后在`CAS`前有线程删除了`pred`，此时`pred->next == MARK(item)`，`CAS`失败，重试；删除分为2种情况：a) 从链表移除，得到标记，`pred`可继续访问；b) `pred`可能被释放内存，此时再使用`pred`会错误。为了处理情况b，所以引入了类似hazard pointer的机制，可以有效保障任意一个指针`p`只要还有线程在使用它，它的内存就不会被真正释放
* `insert`中有多个线程在`pred`后插入元素，此时同样由`insert`中的`CAS`保证，这个不多说
* `remove`中情况同`insert`，`find`拿到了有效的`pred`和`next`，但在`CAS`的时候`pred`被其他线程删除，此时情况同`insert`，`CAS`失败，重试
* 任何时候改变链表结构时，无论是`remove`还是`insert`，都需要重试该操作
* `find`中遍历时，可能会遇到被标记删除的`item`，此时`item`根据`remove`的实现很可能被删除，所以需要重头开始遍历

## ABA问题

ABA问题还是存在的，`insert`中：

{% highlight c++ %}
    if (CAS(&pred->next, item, new_item)) {
        return TRUE;
    }
{% endhighlight %}


如果`CAS`之前，`pred`后的`item`被移除，又以相同的地址值加进来，但其value变了，此时`CAS`会成功，但链表可能就不是有序的了。`pred->val < new_item->val > item->val`

为了解决这个问题，可以利用指针值地址对齐的其他位来存储一个计数，用于表示`pred->next`的改变次数。当`insert`拿到`pred`时，`pred->next`中存储的计数假设是0，`CAS`之前其他线程移除了`pred->next`又新增回了`item`，此时`pred->next`中的计数增加，从而导致`insert`中`CAS`失败。

{% highlight c++ %}
    // 最低位留作删除标志
    #define MASK ((sizeof(node_t) - 1) & ~0x01)

    #define GET_TAG(p) ((markable_t)p & MASK)
    #define TAG(p, tag) ((markable_t)p | (tag))
    #define MARK(p) ((markable_t)p | 0x01)
    #define HAS_MARK(p) ((markable_t)p & 0x01)
    #define STRIP_MARK(p) ((node_t*)((markable_t)p & ~(MASK | 0x01)))
{% endhighlight %}

`remove`的实现：

{% highlight c++ %}
    /* 先标记再删除 */
    if (!CAS(&sitem->next, inext, MARK(inext))) {
        continue;
    }
    int tag = GET_TAG(pred->next) + 1;
    if (CAS(&pred->next, item, TAG(STRIP_MARK(sitem->next), tag))) {
        haz_defer_free(sitem);
        return TRUE;
    }
{% endhighlight %}

`insert`中也可以更新`pred->next`的计数。

## 总结

无锁的实现，本质上都会依赖于`CAS`的互斥性。从头实现一个lock free的数据结构，可以深刻感受到lock free实现的tricky。最终代码可以从[这里github](https://github.com/kevinlynx/lockfree-list)获取。代码中为了简单，实现了一个不是很强大的hazard pointer，可以[参考之前的博文](http://codemacro.com/2015/05/03/hazard-pointer/)。

