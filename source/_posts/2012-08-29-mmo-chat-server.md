---
layout: post
title: "MMO聊天服务器设计"
date: 2012-08-29 09:54
comments: true
categories: [game develop]
tags: [mmo, chat server]
---

MMO中的聊天服务主要功能就是做客户端之间的聊天内容转发。但是聊天的形式有很多，例如私聊、同场景聊、队伍内聊、工会内聊、全服务器聊、甚至临时组建房间聊。这些逻辑功能其实都是可以做在逻辑服务器上的，最多改改世界服务器，但是这样完成功能的话，不免将聊天本身的逻辑与游戏逻辑关联起来。我们希望做得更上一层，将聊天服务本身脱离开来。但是独立聊天服务还不够，因为就算独立出来了，也有可能在实现上与具体的游戏逻辑相关联。所以，我们做了进一步的抽象，想实现一个更为通用的聊天服务器。

## 设计实现

### 实体设计

聊天这个过程，我们将其抽象为实体(entity)与实体间的对话。这个实体概念其实很宽泛。任何可接收聊天消息的都算做实体，例如单个玩家、一个场景、一个队伍、一个房间、一个工会、甚至整个服务器。这个思想其实就是支持整个聊天服务器设计的最根本思想。最开始，我将聊天服务器分为个体和组两个概念，其实这个抽象程度都太低，并且会导致实现上的复杂。相反，将整个系统完全使用实体这个概念来组装，就简单很多。当然，实体是有很多种类的，在处理接收聊天消息这个动作时，其处理方式就不同。例如单个玩家实体仅做消息的发送，场景实体则是将消息发给场景内的所有玩家，队伍实体就是将消息发给队伍内的所有玩家。从这一点来看，我们的实体种类其实并不多，因为场景、队伍这些，都是组实体(group entity)。用C++来描述：
<!-- more -->
{% highlight c++ %}
class Entity {
public:
    // send text to this entity
    virtual bool Send(Entity *sender, const std::string &text) = 0;

protected:
    GUID m_id;
    int m_type;
};

class SockEntity : pubilc Entity {
public:
    virtual bool Send(Entity *sender, const std::string &text) {
        // find the map socket and send text to the socket
        long socket = FindSocket(this);
        Message msg(MSG_CS2E_SENDTEXT);
        msg.Add(sender->ID());
        msg.Add(text);
        msg.SendToSocket(socket);
        return true;
    }
};

class GroupEntity : public Entity {
public:
    virtual bool Send(Entity *sender, const std::string &text) {
        for (std::list<Entity*>::const_iterator it = m_mems.begin(); it != m_mems.end(); ++it) {
            (*it)->Send(sender, text);
        }
        return true;
    }
private:
    std::list<Entity*> m_mems;
};

{% endhighlight %}

`SockEntity`用于表示物理上聊天服务器的客户端，例如游戏客户端。

### 网络拓扑

实际上，除了转发聊天内容外(Entity::Send)，实体还有很多其他行为，例如最起码的，创建组实体，往组实体里添加成员等。在设计上，组实体的创建由逻辑服务器或者其他服务器来完成，目前游戏客户端是没有创建组实体的权限的（实现上我们还为实体添加了权限验证机制）。在网络拓扑上，聊天服务器始终是作为服务器角色，而它的客户端则包括游戏客户端、逻辑服务器、甚至其他服务器，这样聊天服务器在提供了固定的协议后，它就是完全独立的，不依赖任何其他组件：

            CS
          /  |  \
         /   |   \
        /    |    \
       GC    GC   GS

(CS: Chat Server, GC: Game Client, GS: Game Server)

基于此，我们扩充了Entity的类体系：

{% highlight c++ %}
class ClientEntity : public SockEntity {

private:
    GUID m_gsEntity; // 标示该客户端实体位于哪个逻辑服务器实体上
};

class GSEntity : public SockEntity {
};
{% endhighlight %}

### 消息协议 

聊天服务器的核心实现，其实就是针对以上实体做操作。因此，聊天服务器的消息协议方面，也主要是针对这些实体的操作，包括：

* 创建

    实体的创建很简单，不同的实体其创建所需的参数都不一样。例如客户端实体创建时需要传入一个逻辑服务器实体的ID，组实体的创建可以携带组成员实体列表。为了处理权限和安全问题，在具体实现上，逻辑服务器实体的创建是由聊天服务器本地的配置决定，即聊天服务器启动则根据配置创建好逻辑服务器实体；客户端实体是当角色进入逻辑服务器后，由服务器创建，客户端无法创建实体。

* 删除

    实体的删除为了处理方便，约定删除请求必须由实体的创建者发起。因为从逻辑上将，某个模块如果可以创建一个实体，那么其必然知道什么时候该删除这个实体。

* 修改

    修改指的是修改实体内部实现的一些属性，例如组实体修改其组成员。这个操作是非常重要的。对于`SockEntity`而言，修改意味着修改其连接状态，例如当逻辑服务器在聊天服务器上创建了客户端实体后，实际上此时客户端并没有在网络方面连接聊天服务器，此时这个`Entity`实际上是不可用的，因为它无法用于发送消息。这个时候我们标志该实体的状态为非连接状态。当客户端主动连接上聊天服务器后，客户端就主动发起修改自己对应的客户端实体请求，该请求将自己的状态修改为连接状态。当客户端关闭时，聊天服务器网络层接收到连接断开通知，该通知肯定是早于逻辑服务器发来的删除实体通知的，此时将该客户端实体状态修改为断开状态，并在接收到逻辑服务器删除实体通知时将其真正删除。这里展示的这种状态修改策略，实际上在整个系统中是非常重要的。它用于指导网络连接和上层逻辑之间的关系，因为整个聊天系统中，各个进程的状态是不可预料的（随时可能宕掉），当某个进程尤其是逻辑服务器宕掉后，聊天服务器是得不到任何正常逻辑通知的，它只能得到网络连接的通知。


## 总结

整个系统实现下来，实际上是非常简单的，代码量也很少。当然还有很多细节问题，例如聊天信息中携带物品信息，这涉及到异步预处理聊天内容，这里就不方便细说了。



