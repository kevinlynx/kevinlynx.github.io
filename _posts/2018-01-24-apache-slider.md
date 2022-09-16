---
layout: post
title: "基于Yarn的分布式应用调度器Slider"
category: 弹性调度
tags: [slider]
comments: true
---

Apache Hadoop Map-Reduce
框架为了解决规模增长问题，发展出了yarn。而yarn不仅解决Map-Reduce调度问题，还成为了一个通用的分布式应用调度服务。yarn中的一个创新是把各种不同应用的调度逻辑拆分到了一个称为Application
Manager(以下简称AM)的角色中，从而让yarn自己变得更通用，同时解决调度性能问题。Apache
Slider就是这其中的一个AM具体实现。但Slider进一步做了通用化，可以用于调度长运行(long-running)的分布式应用。

为了更好地理解Slider/Yarn，需要思考这样一个问题：在不用Slider/Yarn这种自动部署并管理应用的软件时，我们如何在一个网络环境中部署一个分布式应用？

* 可能需要在目标物理机上创建虚拟容器，指定容器所用的CPU核数、内存数
* 到容器中下载或复制应用运行所需的所有软件包
* 可能需要改写应用所需的各种配置
* 运行应用，输入可能很长的命令行参数

注意这些操作需要在所有需要运行的容器中执行，当然现在也有很多自动部署的工具可以解决这些问题。但是，当应用首次部署运行起来后，继续思考以下问题：

* 某台机器物理原因关机，对应的应用实例不可服务，如何自动发现故障并迁移该实例
* 应用有突发流量，需要基于当前运行中的版本做扩容
* 应用需要更新

## 架构

看一下yarn的总体架构：

![](/assets/res/yarn.png)
<!-- more -->
yarn管理的每台机器上都会部署Node Manager (简称NM)，NM主要用于创建容器，用户的应用运行在这个容器中。一台机器可能会跑多个应用的实例(Instance)。Resource Manager
(简称RM)用于管理整个集群的资源，例如CPU、内存。App Master(Manager) (简称AM) 用于管理容器中用户的应用。AM本身也运行在容器中。

通过Client提交AM的请求到RM中，RM找到一个可用的NM并启动该AM。随后，AM与RM交互，为应用请求各种资源，并发出应用的部署请求。在运行期间，AM会监视应用每个实例的正确性，以在假设有机器挂掉后，申请新的资源来自动恢复该实例。

为了更具体地了解这个过程，可以先参考[Writing YARN Applications](https://hadoop.apache.org/docs/stable/hadoop-yarn/hadoop-yarn-site/WritingYarnApplications.html)。

Slider是AM的一种实现，接下来从以下几个方面来了解Slider：

* Slider架构
* 如何描述一个应用
* 使用流程及主要接口
* 如何定制
* 其他细节

## Slider架构

借图([Slider设计理念与基本架构](http://www.weixinnu.com/tag/article/2086961513))：

![](/assets/res/slider.jpeg)

作为一个Yarn AM其结构与之前描述的相差无几。Slider Client是一个命令行程序，它直接与RM交互，提交一个Slider AM包给RM。RM分配资源并配合NM启动Slider AM这个服务程序。Slider AM在启动目标应用时，通常会在目标容器中部署一个Slider
Agent。这个Agent实现了一套与不同应用之间的交互协议，例如：INSTALL/CONFIGURE/START/STOP/STATUS，应用一般通过Python脚本实现这些协议命令，就可以被Slider部署起来。

## 如何描述一个应用

完整地描述一个应用，就可以让第三方调度器，例如Slider，自动地部署应用、迁移应用。在Slider中描述一个应用，主要分为3部分内容：

* 资源描述，resources.json，例如单实例所需要的CPU核数、内存数，总共需要多少实例
* 应用特定的配置描述，appConfig.json，例如Java应用JVM的内存配置
* 应用适配协议，这个不是配置文件，一般是Python脚本，实现一个应用实例如何安装、如何启动

除了以上内容外，Slider认为一个完整的分布式应用可能包含多个组件(Component)，例如HBase包含Master、Worker。应用描述还应该包含各个组件的描述，例如每个组件可以有自己的资源需求。Component也被称为Role(可能不准确，但意思接近)。当有多个Component时，可以配置每个Component的优先级，高优先级的Component优先得到资源分配。

例如，一个`resource.json`例子，主要就是指定各个Component的资源：

```
{
  "schema": "http://example.org/specification/v2.0.0",

  "metadata": {
    "description": "example of a resources file"
  },

  "global": {
    "yarn.vcores": "1",
    "yarn.memory": "512"
  },

  "components": {
    "master": {
      "instances": "1",
      "yarn.vcores": "1",
      "yarn.memory": "1024"
    },
    "worker": {
      "instances":"5",
      "yarn.vcores": "1",
      "yarn.memory": "512"
    }
  }
}
```

`appConfig.json`主要就是应用相关的配置参数：

```
{
  "schema": "http://example.org/specification/v2.0.0",

  "global": {

    "zookeeper.port": "2181",
    "zookeeper.path": "/yarnapps_small_cluster",
    "zookeeper.hosts": "zoo1,zoo2,zoo3",
  },
  "components": {
    "worker": {
      "jvm.heapsize": "512M"
    },
    "master": {
      "jvm.heapsize": "512M"
    }
  }
  "credentials" {
  }
}
```

在Slider中，应用需要将这些配置信息以及应用自己部署所需要的各种软件包，按照规范打成一个压缩包。然后使用slider工具提交，slider工具会将包上传至HDFS上。

可以通过[Hello World Slider App](http://slider.incubator.apache.org/docs/slider_specs/hello_world_slider_app.html)获得直观的印象。

## 使用流程及主要接口

使用Slider主要就是使用其客户端工具`slider`。要通过Slider启动一个应用，主要步骤如下：

* 准备好应用包，配置资源描述resources.json、应用配置appConfig.json、开发适配协议脚本。
* 打包并上传，通过`slider install-package`完成
* 提交并部署，通过`slider create`完成

其中，应用的部署和AM自身的部署是一起提交的。在应用部署好后，后续的运维操作都可以通过`slider`工具完成，例如：

* 对应用做扩缩容: `./slider flex cl1 --component worker 5`
* 对应用做更新：`slider upgrade MyHBase_Facebook_Finance --components HBASE_MASTER HBASE_REGIONSERVER`

对应用做更新时，Slider文档中指出不可以同时做扩缩容。另外，如果更新过程中有部分容器坏掉自动替换，可能会自动更新为新版本。在更新过程中，Slider并不做更新过程的维护，即用户需要自己指定当前希望哪些容器得到更新（或全部更新），用户通过slider工具检查这些容器的版本是否达到预期，并继续更新下一批容器。过程大体如下：

```
# 上传更新包
slider package --install --name MyHBase_Facebook --version 2.0 --package ~/slider-hbase-app-package_v2.0.zip
# upgrades the internal state 
slider upgrade MyHBase_Facebook_Finance --template ~/myHBase_appConfig_v2.0.json --resources ~/myHBase_resources_v2.0.json
# 重复以下步骤，根据应用的需求更新各个容器
slider upgrade MyHBase_Facebook_Finance --containers id1 id2 .. idn
```

如果应用有多个Component，Component之间的更新一般是有顺序的，这里Slider交给用户自己去控制。用户也可以控制容器之间的更新间隔。

更新过程的细节参考[Rolling Upgrade](http://slider.incubator.apache.org/docs/slider_specs/application_pkg_upgrade.html)。

## 如何定制

Slider中有一个概念叫`Provider`。provider可以理解为为了支持特定应用类型而开发的插件，以让Slider部署这些特殊的应用。默认的provider就是前面提到的slider agent。这个agent是一堆Python脚本，定义了与应用交互的各种协议。实现自己的provider，需要实现client端和server端。client端会被slider client (前面提到的`slider`工具)调用，可以用于添加应用所需要的特殊包，以提交为Slider AM。而server端主要指的是Slider AM端，可以定制具体部署应用时的行为，例如部署自己定制的agent。

具体provider例子可以参考源码中slider-providers子项目。

## 其他细节

以下细节仅供记录，未深入了解。

### 服务发现

服务发现用于解决分布式系统中上游服务如何发现下游服务实例，以发出RPC调用。Slider中依靠Yarn的服务发现机制，目前主要是通过zookeeper来自动对服务做注册。参考[The Yarn Service Registry](http://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/registry/yarn-registry.html)。

### 资源分配策略

Slider在请求yarn分配容器时，可以配置不同的策略，这个称为`Placement Policy`。例如是否优先跑在打有特殊标签的机器上，或者跑在特定的机架(rack)上。这里的资源标签就是一些普通的文本，例如给一个机器打上`gpu`标签，而分配容器时，也只是简单的匹配，并没有看到互斥、多标签组合等功能。分配策略可以解决带数据应用的机器亲近性，当应用实例发生迁移时，优先在有历史数据的机器上部署，可以获得更快的启动速度。

具体参考[Apache Slider Placement](https://slider.incubator.apache.org/docs/placement.html)。

## 总结

翻看了Slider的文档及部分源码，主要功能了解得七七八八。Slider虽然可以自动调度起一个应用，但是一个用于生产环境的调度器还要在很多细节上做得出色，例如：

* 需要与服务发现深度结合。应用实例在服务发现中的状态能够参与到调度器的调度中，例如是否能做到对上游应用透明地更新
* 应用实例与agent交互时，STATUS需要表达应用确实可提供服务，并且在运行期间持续透出可服务状态
* 调度整个集群时，是否能对失败节点做容错，是否会自动recover这些失败节点，也就是我们说的基于目标式的调度实现(level-triggered)
* 应用的更新是日常运维的常态，更新语义应该基于百分比，而不是基于容器；更新既然是常态，调度器就该处理好在这期间集群里可能发生的任何事情，例如有容器被自动替换

