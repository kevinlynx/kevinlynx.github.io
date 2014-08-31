---
layout: post
title: "基于protobuf的RPC实现"
categories: c/c++
tags: [protobuf, rpc]
comments: true
keywords: [protbuf, rpc]
---

可以对照[使用google protobuf RPC实现echo service](http://www.codedump.info/?p=169)一文看，细节本文不再描述。

google protobuf只负责消息的打包和解包，并不包含RPC的实现，但其包含了RPC的定义。假设有下面的RPC定义：

{% highlight c++ %}
    service MyService {
        rpc Echo(EchoReqMsg) returns(EchoRespMsg) 
    }
{% endhighlight %}

那么要实现这个RPC需要最少做哪些事？总结起来需要完成以下几步：

## 客户端

RPC客户端需要实现`google::protobuf::RpcChannel`。主要实现`RpcChannel::CallMethod`接口。客户端调用任何一个RPC接口，最终都是调用到`CallMethod`。这个函数的典型实现就是将RPC调用参数序列化，然后投递给网络模块进行发送。

{% highlight c++ %}
    void CallMethod(const ::google::protobuf::MethodDescriptor* method,
                  ::google::protobuf::RpcController* controller,
                  const ::google::protobuf::Message* request,
                  ::google::protobuf::Message* response,
                  ::google::protobuf::Closure* done) {
        ...
        DataBufferOutputStream outputStream(...) // 取决于你使用的网络实现
        request->SerializeToZeroCopyStream(&outputStream);
        _connection->postData(outputStream.getData(), ...
        ...
    }
{% endhighlight %}
<!-- more -->
## 服务端

服务端首先需要实现RPC接口，直接实现`MyService`中定义的接口：

{% highlight c++ %}
    class MyServiceImpl : public MyService {
        virtual void Echo(::google::protobuf::RpcController* controller,
            const EchoReqMsg* request,
            EchoRespMsg* response,
            ::google::protobuf::Closure* done) {
            ...
            done->Run();
        }
    }
{% endhighlight %}

## 标示service&method

基于以上，可以看出服务端根本不知道客户端想要调用哪一个RPC接口。从服务器接收到网络消息，到调用到`MyServiceImpl::Echo`还有很大一段距离。

解决方法就是在网络消息中带上RPC接口标识。这个标识可以直接带上service name和method name，但这种实现导致网络消息太大。另一种实现是基于service name和method name生成一个哈希值，因为接口不会太多，所以较容易找到基本不冲突的字符串哈希算法。

无论哪种方法，服务器是肯定需要建立RPC接口标识到protobuf service对象的映射的。

这里提供第三种方法：基于option的方法。

protobuf中option机制类似于这样一种机制：service&method被视为一个对象，其有很多属性，属性包含内置的，以及用户扩展的。用户扩展的就是option。每一个属性有一个值。protobuf提供访问service&method这些属性的接口。

首先扩展service&method的属性，以下定义这些属性的key：

{% highlight c++ %}
    extend google.protobuf.ServiceOptions {
      required uint32 global_service_id = 1000; 
    }
    extend google.protobuf.MethodOptions {
      required uint32 local_method_id = 1000;
    }
{% endhighlight %}

应用层定义service&method时可以指定以上key的值：

{% highlight c++ %}
    service MyService
    {
        option (arpc.global_service_id) = 2302; 

        rpc Echo(EchoReqMsg) returns(EchoRespMsg) 
        {
            option (arpc.local_method_id) = 1;
        }
        rpc Echo_2(EchoReqMsg) returns(EchoRespMsg) 
        {
            option (arpc.local_method_id) = 2;
        }
        ...
    }
{% endhighlight %}

以上相当于在整个应用中，每个service都被赋予了唯一的id，单个service中的method也有唯一的id。

然后可以通过protobuf取出以上属性值：

{% highlight c++ %}
    void CallMethod(const ::google::protobuf::MethodDescriptor* method,
                  ::google::protobuf::RpcController* controller,
                  const ::google::protobuf::Message* request,
                  ::google::protobuf::Message* response,
                  ::google::protobuf::Closure* done) {
        ...
        google::protobuf::ServiceDescriptor *service = method->service();
        uint32_t serviceId = (uint32_t)(service->options().GetExtension(global_service_id));
        uint32_t methodId = (uint32_t)(method->options().GetExtension(local_method_id));
        ...
    }
{% endhighlight %}

考虑到`serviceId` `methodId`的范围，可以直接打包到一个32位整数里：

    uint32_t ret = (serviceId << 16) | methodId;
   
然后就可以把这个值作为网络消息头的一部分发送。

当然服务器端是需要建立这个标识值到service的映射的：


{% highlight c++ %}
    bool MyRPCServer::registerService(google::protobuf::Service *rpcService) {
        const google::protobuf::ServiceDescriptor = rpcService->GetDescriptor();
        int methodCnt = pSerDes->method_count();

        for (int i = 0; i < methodCnt; i++) {
            google::protobuf::MethodDescriptor *pMethodDes = pSerDes->method(i);
            uint32_t rpcCode = PacketCodeBuilder()(pMethodDes); // 计算出映射值
            _rpcCallMap[rpcCode] = make_pair(rpcService, pMethodDes); // 建立映射
        }
        return true;
    }
{% endhighlight %}

服务端收到RPC调用后，取出这个标识值，然后再从`_rpcCallMap`中取出对应的service和method，最后进行调用：


{% highlight c++ %}
    google::protobuf::Message* response = _pService->GetResponsePrototype(_pMethodDes).New();
    // 用于回应的closure
    RPCServerClosure *pClosure = new (nothrow) RPCServerClosure( 
            _channelId, _pConnection, _pReqMsg, pResMsg, _messageCodec, _version);
    RPCController *pController = pClosure->GetRpcController();
    ...
    // protobuf 生成的CallMethod，会自动调用到Echo接口
    _pService->CallMethod(_pMethodDes, pController, _pReqMsg, pResMsg, pClosure);
{% endhighlight %}


## 参考

* [使用google protobuf RPC实现echo service](http://www.codedump.info/?p=169)
* [protobuf extensions](https://developers.google.com/protocol-buffers/docs/proto?hl=zh-cn#extensions)
* [protobuf service](https://developers.google.com/protocol-buffers/docs/proto#services)
* [protobuf options](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.descriptor#MethodDescriptor.options.details)

