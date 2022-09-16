---
layout: post
title: "Kubernete APIServer Sample"
category: 弹性调度
tags: [kubernetes]
comments: true
---

kubernetes从apiserver中独立出来了一个项目：[apiserver](https://github.com/kubernetes/apiserver)，可以基于这个库快速实现一个类似kubernetes apiserver的服务。

>> Generic library for building a Kubernetes aggregated API server.

如果直接阅读kubenetes的apiserver源码，会发现很多实现都位于这个项目中。kubenetes源码目录下还有个[sample-apiserver](https://github.com/kubernetes/sample-apiserver)，是用于示例如何使用这个库的。从这个sample可以更快速地了解kubernetes apiserver的实现，以及如何使用。

简单来说，这个apiserver库做了很多抽象，基本上，用户只需要描述自己的资源结构是怎样的，就可以构建出一个类似kubernetes的apiserver，具备资源多版本兼容能力，对外提供json/yaml的http restful接口，并持久化到etcd中。接下来主要讲下大概的用法以及apiserver中的主要概念。

## apiserver简介

apiserver简单来说，可以理解为一个基于etcd，并提供HTTP接口的对象(资源)系统。其提供了针对多种资源的操作，例如CRUD、列表读取、状态读取。kubernetes中POD、Deployment、Service，都是资源，可以说kubernetes所有组件都是围绕着资源运作的。apiserver库本身是不提供任何资源的，它做了很多抽象，使得应用层可以根据自己需要添加各种资源。同时，apiserver支持相同资源多个版本的存在。

为了更容易地理解apiserver的设计，可以先自己思考如何实现出这样一个通用的资源服务框架，例如，可能需要解决以下问题：

* HTTP接口层，根据资源名映射出不同的URI，如何统一地从HTTP请求中创建出不同类型的资源
* 不同的资源支持的操作不同，如何区分  
* 资源的多版本如何实现
* 资源如何统一地序列化存储到etcd中
<!-- more -->
## 核心概念

在看例子代码之前，有必要提一下apiserver中的一些关键概念。

* Storage

Storage连接底层存储etcd与HTTP route。apiserver库中会自动注册各种资源对应的HTTP route。在route的处理中则会调用storage的接口。storage是分类型的，其通过检查是否实现了某个golang接口来确定其类型，例如在apiserver的代码中：

```
//(a *APIInstaller) registerResourceHandlers

creater, isCreater := storage.(rest.Creater)
namedCreater, isNamedCreater := storage.(rest.NamedCreater)
lister, isLister := storage.(rest.Lister)
getter, isGetter := storage.(rest.Getter)
```

通过确定某个资源的storage类型，以确定该资源支持哪些动作，apiserver中叫HTTP verb。

* Scheme

Scheme用于描述一种资源的结构，就像可以用一段JSON描述一个对象的结构一样。Scheme可以描述一种资源如何被创建；资源不同版本间如何转换；某个版本的资源如何向internal资源转换。通常会看到类似的注册：

```
// 注册资源类型
scheme.AddKnownTypes(SchemeGroupVersion,
	&Flunder{},
	&FlunderList{},
	&Fischer{},
	&FischerList{},
)
```

Scheme 会在很多地方被用到，可以理解为其实它就是一种隔离具体数据类型的机制。作为一个库，要支持应用层注册不同类型的资源，就需要与应用层建立资源的契约：应用层如何让框架层知道某个具体的资源长什么样，在诸如存储、编解码、版本转换等问题上如何提供给框架特有的信息。

* Codec

Codec和上面的Scheme密不可分。Codec利用Scheme在HTTP请求及回应中对一个资源做编解码。这其中又会涉及到Serializer之类的概念，主要也是利用Scheme来支持类似yaml/json这些不同的请求格式。Codec基本对应用层透明。

这里把上面3个概念串通：HTTP请求来时，利用Codec基于Scheme将具体的资源反序列化出来，最后交给Storage持久化到etcd中；反之，当读取资源时，通过Storage从etcd中基于Scheme/Codec读取资源，最后Codec到HTTP Response中。

* 版本及Group

apiserver中对不同的资源做了分组，这里暂时不关心。相同资源可以有不同的版本并存。值得注意的是，apiserver内部有一个internal版本的概念。internal版本负责与Storage交互，从而隔离Storage与不同版本资源的依赖。不同版本的资源都可以与internal版本转换，不同版本之间的转换则通过internal版本间接转换。

## 样例

通过[sample-apiserver](https://github.com/kubernetes/sample-apiserver)，可以理解apiserver的接口。看下sample-apiserver的源码结构：

```
// kubernetes/staging/src/k8s.io/sample-apiserver
pkg/
├── admission
├── apis
│   └── wardle
│       ├── install
│       └── v1alpha1
├── apiserver
├── client
├── cmd
│   └── server
└── registry
    └── wardle
        ├── fischer
        └── flunder
```

其中，核心的目录主要包括：

* cmd/apiserver，基本上相当于程序入口，其中会初始化整个框架
* register，Storage相关部分
* apis，定义具体的资源类型，初始化Scheme

要通过apiserver构建出一个类似kubernetes的apiserver，大概要完成以下步骤：

- 初始化框架，可以理解为如何把apiserver跑起来
- Storage，为不同group不同版本定义好Storage，有很多工具类可以直接使用
- Scheme，定义资源的Scheme，告知框架资源长什么样

基于以上过程，接下来看下sample-apiserver如何完成的。

### 启动过程

程序入口从`cmd`包中看，然后会到`apiserver`包。核心的代码主要在apiserver.go中`func (c completedConfig) New() `。其中核心的对象是`genericapiserver.GenericAPIServer`。拿到该对象时，就可以run起来：


```
// cmd/server/start.go

return server.GenericAPIServer.PrepareRun().Run(stopCh)
```

其中，拿到`GenericAPIServer`后最重要的就是安装资源的Storage：


```
// apiserver/apiserver.go

apiGroupInfo := genericapiserver.NewDefaultAPIGroupInfo(wardle.GroupName, registry, Scheme, metav1.ParameterCodec, Codecs)
apiGroupInfo.GroupMeta.GroupVersion = v1alpha1.SchemeGroupVersion
v1alpha1storage := map[string]rest.Storage{}
v1alpha1storage["flunders"] = wardleregistry.RESTInPeace(flunderstorage.NewREST(Scheme, c.GenericConfig.RESTOptionsGetter))
v1alpha1storage["fischers"] = wardleregistry.RESTInPeace(fischerstorage.NewREST(Scheme, c.GenericConfig.RESTOptionsGetter))
apiGroupInfo.VersionedResourcesStorageMap["v1alpha1"] = v1alpha1storage

if err := s.GenericAPIServer.InstallAPIGroup(&apiGroupInfo); err != nil {
	return nil, err
}
```

上面的代码中，`apiGroupInfo`保存了单个Group下多个Version的资源Storage，关键数据成员是`VersionedResourcesStorageMap`，这个例子代码表示：

* 有1个Version: v1alpha1
* 该Version下有2个资源：flunders，fischers
* 为每个资源配置对应的Storage

### Storage

Storage如何构建，就可以继续跟下`wardleregistry.RESTInPeace`。这部分代码主要在`registry`下。核心的实现在`NewRest`中，如：

```
// pkg/registry/wardle/fischer/etcd.go 

store := &genericregistry.Store{
	NewFunc:                  func() runtime.Object { return &wardle.Fischer{} },
	NewListFunc:              func() runtime.Object { return &wardle.FischerList{} },
	PredicateFunc:            MatchFischer,
	DefaultQualifiedResource: wardle.Resource("fischers"),

	CreateStrategy: strategy,
	UpdateStrategy: strategy,
	DeleteStrategy: strategy,
}
```

要构建storage，其实只要使用`genericregistry.Store`即可。这里可以针对一些主要数据成员做下说明。`NewFunc`返回的对象，会被用于响应REST接口，例如通过API获取一个资源时，就会先`NewFunc`获取到一个空的资源对象，然后由具体的存储实现(如etcd)来填充这个资源。举个例子，`genericregistry.Store.Get`会直接被HTTP route调用，其实现大概为：


```
// kubernetes/vendor/k8s.io/apiserver/pkg/registry/generic/registry/store.go

func (e *Store) Get(ctx genericapirequest.Context, name string, options *metav1.GetOptions) (runtime.Object, error) {
	obj := e.NewFunc()
	key, err := e.KeyFunc(ctx, name)
	...
	if err := e.Storage.Get(ctx, key, options.ResourceVersion, obj, false); err != nil {
		return nil, storeerr.InterpretGetError(err, e.qualifiedResourceFromContext(ctx), name)
	}
...
}

```

以上，`e.Storage`就是具体的存储实现，例如etcd2，而`obj`传入进去是作为输出参数。在创建资源时，`NewFunc`出来的对象，也是用于`e.Storage`从etcd存储中读取的对象，作为输出用。


### Scheme

前面看到`apiserver.go`中时，除了创建`GenericAPIServer`外，还存在包的`init`实现，即该包被import时执行的动作。这个动作，主要就是用来处理Scheme相关事宜。


```
// pkg/apiserver/apiserver.go
func init() {
	install.Install(groupFactoryRegistry, registry, Scheme)
	...
}
```

同时注意`apiserver.go` 中定义的全局变量：

```
var (
...
	Scheme               = runtime.NewScheme()
	Codecs               = serializer.NewCodecFactory(Scheme)
)
```

`install.Install`的实现比较典型，kubernetes自身的apiserver中也有很多类似的注册代码。

```
// pkg/apis/wardle/install/install.go

	if err := announced.NewGroupMetaFactory(
		&announced.GroupMetaFactoryArgs{
			GroupName:                  wardle.GroupName,
			RootScopedKinds:            sets.NewString("Fischer", "FischerList"),
			VersionPreferenceOrder:     []string{v1alpha1.SchemeGroupVersion.Version},
			AddInternalObjectsToScheme: wardle.AddToScheme,
		},
		announced.VersionToSchemeFunc{
			v1alpha1.SchemeGroupVersion.Version: v1alpha1.AddToScheme,
		},
	).Announce(groupFactoryRegistry).RegisterAndEnable(registry, scheme); err != nil {
		panic(err)
	}
```

`RegisterAndEnable`最终完成各种资源类型注册到Scheme中。在`install.go`中import里还要注意`register.go`中的init初始化：

```
// pkg/apis/wardle/v1alpha1/register.go

var (
	localSchemeBuilder = &SchemeBuilder
	AddToScheme        = localSchemeBuilder.AddToScheme
)

func init() {
	localSchemeBuilder.Register(addKnownTypes)
}

func addKnownTypes(scheme *runtime.Scheme) error {
	scheme.AddKnownTypes(SchemeGroupVersion,
		&Flunder{},
		&FlunderList{},
		&Fischer{},
		&FischerList{},
	)
	metav1.AddToGroupVersion(scheme, SchemeGroupVersion)
	return nil
}

```

`SchemeBuilder` 其实就是个function列表，在前面的`RegisterAndEnable`中最终会传递Scheme对象到这个函数列表中的每个函数，也就会执行到上面的`addKnownTypes`。除了注册资源类型外，在类似 `zz_generated.conversion.go`文件中还通过init自动注册了各种转换函数。

Scheme的工作原理比较复杂，这个改天有机会讲。回过头来看Scheme的用法，其实主要就是告诉框架层这个对象长什么样，实现上就是传了个空对象指针进去。

### Codec与Scheme

前面的全局变量中就涉及到Codec，可以看出是依赖了Scheme的。可以稍微进去看看底层实现，例如：

```
// k8s.io/apimachinery/pkg/runtime/serializer/codec_factory.go
func NewCodecFactory(scheme *runtime.Scheme) CodecFactory {
	serializers := newSerializersForScheme(scheme, json.DefaultMetaFactory)
	return newCodecFactory(scheme, serializers)
}
```

其中，`newSerializersForScheme` 就根据scheme创建了json/yaml的Serializer，可以理解为用于解析HTTP请求，创建对应的资源。从这里可以看看Serializer是如何工作的，如何与Scheme关联的，例如Serializer必然会被用于解析HTTP请求：

```
// k8s.io/apimachinery/pkg/runtime/serializer/json/json.go

// 可以推测originalData就是HTTP请求内容
func (s *Serializer) Decode(originalData []byte, gvk *schema.GroupVersionKind, into runtime.Object) (runtime.Object, *schema.GroupVersionKind, error) {
	...
	obj, err := runtime.UseOrCreateObject(s.typer, s.creater, *actual, into)
	...
	// 拿到一个空的资源对象后，直接用json解析
	if err := jsoniter.ConfigCompatibleWithStandardLibrary.Unmarshal(data, obj); err != nil {
	...
}

// 这里的ObjectTyper/ObjectCreater都是Scheme
func UseOrCreateObject(t ObjectTyper, c ObjectCreater, gvk schema.GroupVersionKind, obj Object) (Object, error) {
	...
	// 最终根据gvk (group version kind) 创建具体的资源
	return c.New(gvk)
}
```

以上可以看出Scheme其实并没有什么神秘的地方，有点像一种factory的模式，用于避免框架层对应用层具体类型的依赖：

```
objPtr := factory.New()
json.Unmarshal(data, objPtr)
```
## 总结

kubernetes apiserver 库虽然是个独立的library，但是使用起来却不容易，也没有什么文档。所以这里仅仅是通过分析其源码，了解apiserver内部的一些概念，方便阅读kubernetes自己的apiserver实现，以及深入apiserver库的实现。


