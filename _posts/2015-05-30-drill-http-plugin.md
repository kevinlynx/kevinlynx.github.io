---
layout: post
title: "Drill中实现HTTP storage plugin"
category: java
tags: drill
comments: true
---

Apache Drill可用于大数据的实时分析，引用一段介绍：

> 受到Google Dremel启发，Apache的Drill项目是对大数据集进行交互式分析的分布式系统。Drill并不会试图取代已有的大数据批处理框架（Big Data batch processing framework），如Hadoop MapReduce或流处理框架（stream processing framework），如S4和Storm。相反，它是要填充现有空白的——对大数据集的实时交互式处理

简单来说，Drill可接收SQL查询语句，然后后端从多个数据源例如HDFS、MongoDB等获取数据并分析产出分析结果。在一次分析中，它可以汇集多个数据源的数据。而且基于分布式的架构，可以支持秒级查询。

Drill在架构上是比较灵活的，它的前端可以不一定是SQL查询语言，后端数据源也可以接入Storage plugin来支持其他数据来源。这里我就实现了一个从HTTP服务获取数据的Storage plugin demo。这个demo可以接入基于GET请求，返回JSON格式的HTTP服务。源码可从我的Github获取：[drill-storage-http](https://github.com/kevinlynx/drill-storage-http)

例子包括：

    select name, length from http.`/e/api:search` where $p=2 and $q='avi'
    select name, length from http.`/e/api:search?q=avi&p=2` where length > 0 

## 实现

要实现一个自己的storage plugin，目前Drill这方面文档几乎没有，只能从已有的其他storage plugin源码入手，例如mongodb的，参考Drill子项目`drill-mongo-storage`。实现的storage plugin打包为jar放到`jars`目录，Drill启动时会自动载入，然后web上配置指定类型即可。

主要需要实现的类包括：

    AbstractStoragePlugin
    StoragePluginConfig
    SchemaFactory
    BatchCreator
    AbstractRecordReader
    AbstractGroupScan
<!-- more -->
### AbstraceStoragePlugin

`StoragePluginConfig`用于配置plugin，例如：

    {
      "type" : "http",
      "connection" : "http://xxx.com:8000",
      "resultKey" : "results",
      "enabled" : true
    }

它必须是可JSON序列化/反序列化的，Drill会把storage配置存储到`/tmp/drill/sys.storage_plugins`中，例如windows下`D:\tmp\drill\sys.storage_plugins`。

`AbstractStoragePlugin` 是plugin的主类，它必须配合`StoragePluginConfig`，实现这个类时，构造函数必须遵循参数约定，例如：

    public HttpStoragePlugin(HttpStoragePluginConfig httpConfig, DrillbitContext context, String name)

Drill启动时会自动扫描`AbstractStoragePlugin`实现类(`StoragePluginRegistry`)，并建立`StoragePluginConfig.class`到`AbstractStoragePlugin constructor`的映射。`AbstractStoragePlugin`需要实现的接口包括：

{% highlight java %}
    // 相应地需要实现AbstraceGroupScan
    // selection包含了database name和table name，可用可不用
    public AbstractGroupScan getPhysicalScan(String userName, JSONOptions selection) 

    // 注册schema
    public void registerSchemas(SchemaConfig schemaConfig, SchemaPlus parent) throws IOException

    // StoragePluginOptimizerRule 用于优化Drill生成的plan，可实现也可不实现
    public Set<StoragePluginOptimizerRule> getOptimizerRules() 
{% endhighlight %}

Drill中的schema用于描述一个database，以及处理table之类的事务，必须要实现，否则任意一个SQL查询都会被认为是找不到对应的table。`AbstraceGroupScan`用于一次查询中提供信息，例如查询哪些columns。

Drill在查询时，有一种中间数据结构(基于JSON)叫Plan，其中又分为Logic Plan和Physical Plan。Logic Plan是第一层中间结构，用于完整表达一次查询，是SQL或其他前端查询语言转换后的中间结构。完了后还要被转换为Physical Plan，又称为Exectuion Plan，这个Plan是被优化后的Plan，可用于与数据源交互进行真正的查询。`StoragePluginOptimizerRule`就是用于优化Physical Plan的。这些Plan最终对应的结构有点类似于语法树，毕竟SQL也可以被认为是一种程序语言。`StoragePluginOptimizerRule`可以被理解为改写这些语法树的。例如Mongo storage plugin就实现了这个类，它会把`where`中的filter转换为mongodb自己的filter(如{'$gt': 2})，从而优化查询。

这里又牵扯出Apache的另一个项目：[calcite](https://github.com/apache/incubator-calcite)，前身就是OptiQ。Drill中整个关于SQL的执行，主要是依靠这个项目。要玩转Plan的优化是比较难的，也是因为文档欠缺，相关代码较多。

### SchemaFactory

`registerSchemas`主要还是调用`SchemaFactory.registerSchemas`接口。Drill中的Schema是一种树状结构，所以可以看到`registerSchemas`实际就是往parent中添加child：

{% highlight java %}
    public void registerSchemas(SchemaConfig schemaConfig, SchemaPlus parent) throws IOException {
        HttpSchema schema = new HttpSchema(schemaName);
        parent.add(schema.getName(), schema);
    }
{% endhighlight %}

`HttpSchema`派生于`AbstractSchema`，主要需要实现接口`getTable`，因为我这个http storage plugin中的table实际就是传给HTTP service的query，所以table是动态的，所以`getTable`的实现比较简单：

{% highlight java %}
    public Table getTable(String tableName) { // table name can be any of string
        HttpScanSpec spec = new HttpScanSpec(tableName); // will be pass to getPhysicalScan
        return new DynamicDrillTable(plugin, schemaName, null, spec);
    }
{% endhighlight %}

这里的`HttpScanSpec`用于保存查询中的一些参数，例如这里保存了table name，也就是HTTP service的query，例如`/e/api:search?q=avi&p=2`。它会被传到`AbstraceStoragePlugin.getPhysicalScan`中的`JSONOptions`：

{% highlight java %}
    public AbstractGroupScan getPhysicalScan(String userName, JSONOptions selection) throws IOException {
        HttpScanSpec spec = selection.getListWith(new ObjectMapper(), new TypeReference<HttpScanSpec>() {});
        return new HttpGroupScan(userName, httpConfig, spec);
    }
{% endhighlight %}

`HttpGroupScan`后面会看到用处。

### AbstractRecordReader

`AbstractRecordReader`负责真正地读取数据并返回给Drill。`BatchCreator`则是用于创建`AbstractRecordReader`。

{% highlight java %}
    public class HttpScanBatchCreator implements BatchCreator<HttpSubScan> {

      @Override
      public CloseableRecordBatch getBatch(FragmentContext context,
          HttpSubScan config, List<RecordBatch> children)
          throws ExecutionSetupException {
        List<RecordReader> readers = Lists.newArrayList();
        readers.add(new HttpRecordReader(context, config));
        return new ScanBatch(config, context, readers.iterator());
      }
    }
{% endhighlight %}

既然`AbstractRecordReader`负责真正读取数据，那么它肯定是需要知道传给HTTP service的query的，但这个query最早是在`HttpScanSpec`中，然后传给了`HttpGroupScan`，所以马上会看到`HttpGroupScan`又把参数信息传给了`HttpSubScan`。

Drill也会自动扫描`BatchCreator`的实现类，所以这里就不用关心`HttpScanBatchCreator`的来历了。

`HttpSubScan`的实现比较简单，主要是用来存储`HttpScanSpec`的：

    public class HttpSubScan extends AbstractBase implements SubScan // 需要实现SubScan

回到`HttpGroupScan`，必须实现的接口：

{% highlight java %}
      public SubScan getSpecificScan(int minorFragmentId) { // pass to HttpScanBatchCreator
        return new HttpSubScan(config, scanSpec); // 最终会被传递到HttpScanBatchCreator.getBatch接口
      }
{% endhighlight %}

最终query被传递到`HttpRecordReader`，该类需要实现的接口包括：`setup`和`next`，有点类似于迭代器。`setup`中查询出数据，然后`next`中转换数据给Drill。转换给Drill时可以使用到`VectorContainerWriter`和`JsonReader`。这里也就是Drill中传说的vector数据格式，也就是列存储数据。

### 总结

以上，就包含了plugin本身的创建，及查询中query的传递。查询中类似`select titile, name` 中的columns会被传递到`HttpGroupScan.clone`接口，只不过我这里并不关注。实现了这些，就可以通过Drill查询HTTP service中的数据了。

而`select * from xx where xx`中的`where` filter，Drill自己会对查询出来的数据做过滤。如果要像mongo plugin中构造mongodb的filter，则需要实现`StoragePluginOptimizerRule`。

我这里实现的HTTP storage plugin，本意是觉得传给HTTP service的query可能会动态构建，例如：

    select name, length from http.`/e/api:search` where $p=2 and $q='avi' # p=2&q=avi 就是动态构建，其值可以来源于其他查询结果
    select name, length from http.`/e/api:search?q=avi&p=2` where length > 0  # 这里就是静态的

第一条查询就需要借助`StoragePluginOptimizerRule`，它会收集所有where中的filter，最终作为HTTP serivce的query。但这里的实现还不完善。

总体而言，由于Drill项目相对较新，要进行扩展还是比较困难的。尤其是Plan优化部分。

