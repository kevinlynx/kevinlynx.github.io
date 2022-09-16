---
layout: post
title: "使用Kubeadm在CentOS部署Kubernets 1.8.7"
category: 弹性调度
tags: [kubernetes]
comments: true
---

主要参考：

* [官方文档](https://v1-8.docs.kubernetes.io/docs/setup/independent/create-cluster-kubeadm/)
* [如何在国内愉快的安装 Kubernetes](https://my.oschina.net/xdatk/blog/895645)
* [kubernetes 1.8.7 国内安装(kubeadm)](https://my.oschina.net/andylo25/blog/1618342)

建议都大致浏览下。这里我也是简单地记录，估计每个人遇到的细节问题不一样。

## 环境准备

我拿到手的环境docker已经ready：

* docker (alidocker-1.12.6.22)
* CentOS 7

上面博客提到的一些系统设置可以先做掉：

```
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl -p /etc/sysctl.d/k8s.conf
```

其他一些设置：

* 防火墙最好关闭
* swap最好关闭
* `setenforce 0`
<!-- more -->
## 软件包及镜像

众所周知的局域网问题，官方的很多软件包和镜像无法获取。解决这个问题主要靠阿里云：

* 配置yum源，由于阿里云yum源相对官方有滞后，并且各个软件包版本匹配我没有找到，所以就按照上面博客提到的，安装1.8.7，避免版本问题：

```
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
```

可以把包下到本地以备不时之需：

```
yum install -y --downloadonly --downloaddir=./ kubelet-1.8.7 kubeadm-1.8.7 kubectl-1.8.7 kubernetes-cni-0.5.1
yum install -y *.rpm
```

* docker镜像问题后来我发现可以从阿里云直接拉，拉下来后通过打tag避免后续部署从google官方拉

以下脚本内容未验证，主要注意镜像得提前拉全(上面链接的博客有写漏了)

```
#!/bin/sh

images=(kube-scheduler-amd64:v1.8.7 \
kube-proxy-amd64:v1.8.7 \
kube-apiserver-amd64:v1.8.7 \
etcd-amd64:3.0.17 \
pause-amd64:3.0 \
k8s-dns-sidecar-amd64:1.14.5 \
k8s-dns-kube-dns-amd64:1.14.5 \
k8s-dns-dnsmasq-nanny-amd64:1.14.5 \
kubernetes-dashboard-amd64:v1.8.1)

for imageName in ${images[@]} ; do
  docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName
  docker tag registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName gcr.io/google_containers/$imageName
  docker rmi registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName
done

# 注意这个镜像最好提前拉，看flannel的yaml描述里会用到
docker pull quay.io/coreos/flannel:v0.9.1-amd64
```

贴个我部署好后的镜像列表(自行忽略多余的)，方便对比：

```
$sudo docker images
REPOSITORY                                                                          TAG                 IMAGE ID            CREATED             SIZE
registry.cn-hangzhou.aliyuncs.com/google_containers/kubernetes-dashboard-amd64      v1.8.3              0c60bcf89900        3 weeks ago         102.3 MB
gcr.io/google_containers/kubernetes-dashboard-amd64                                 v1.8.1              63c78846e37b        4 weeks ago         120.7 MB
gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64                                1.14.5              6d7cc6e484b3        4 weeks ago         41.42 MB
gcr.io/google_containers/k8s-dns-kube-dns-amd64                                     1.14.5              33072cb8c892        4 weeks ago         49.38 MB
gcr.io/google_containers/k8s-dns-sidecar-amd64                                      1.14.5              e1414b167ca6        4 weeks ago         41.81 MB
gcr.io/google_containers/pause-amd64                                                3.0                 8ca66ae4813a        4 weeks ago         746.9 kB
gcr.io/google_containers/etcd-amd64                                                 3.0.17              10010bfa0a74        4 weeks ago         168.9 MB
gcr.io/google_containers/kube-scheduler-amd64                                       v1.8.7              906029e1500b        4 weeks ago         55.13 MB
gcr.io/google_containers/kube-apiserver-amd64                                       v1.8.7              c3bb648343de        4 weeks ago         194.7 MB
gcr.io/google_containers/kube-proxy-amd64                                           v1.8.7              125dec6bd8f2        7 weeks ago         93.36 MB
registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy-amd64                v1.8.7              125dec6bd8f2        7 weeks ago         93.36 MB
gcr.io/google_containers/kube-controller-manager-amd64                              v1.8.7              d8df883aabf9        7 weeks ago         129.6 MB
registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager-amd64   v1.8.7              d8df883aabf9        7 weeks ago         129.6 MB
quay.io/coreos/flannel                                                              v0.9.1-amd64        2b736d06ca4c        3 months ago        51.31 MB

```

## 启动master

```
systemctl enable kubelet
systemctl start kubelet
```

注意，这里官方文档也提到了，需要确认docker的cgroup配置与kubelet的一致：

```
docker info | grep -i cgroup
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

不一致改成一致。例如：

```
sed -i "s/cgroup-driver=systemd/cgroup-driver=cgroupfs/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

配置有变更需要重启kubelet：

```
systemctl daemon-reload
systemctl restart kubelet
```

`systemctl status kubelet`查看日志会发现里面有warning/error级别的日志，所以出问题时很容易被误解。

按照官方文档，在这一步时，kubelet会不断重启，所以这个时候可以继续，准备初始化master：

```
#!/bin/bash
kubeadm init --kubernetes-version=v1.8.7 --pod-network-cidr 10.244.0.0/16

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
```

注意上面flannel的版本与前面的链接不同，v0.9.1测试可用。当flannel启动后，kubelet就会发现这个CNI实现，从而趋于成功运行状态。

可以通过以下命令来确认master是否真的初始化成功：

```
$sudo kubectl get node
NAME                 STATUS    ROLES     AGE       VERSION
v101083237zsqazzmf   Ready     master    12m       v1.8.7

$sudo kubectl get pod --all-namespaces
NAMESPACE     NAME                                         READY     STATUS    RESTARTS   AGE
kube-system   etcd-v101083237zsqazzmf                      1/1       Running   0          11m
kube-system   kube-apiserver-v101083237zsqazzmf            1/1       Running   0          11m
kube-system   kube-controller-manager-v101083237zsqazzmf   1/1       Running   0          11m
kube-system   kube-dns-545bc4bfd4-f7hsx                    3/3       Running   0          11m
kube-system   kube-flannel-ds-d6z78                        1/1       Running   5          6m
kube-system   kube-proxy-z88cd                             1/1       Running   0          11m
kube-system   kube-scheduler-v101083237zsqazzmf            1/1       Running   0          11m

$sudo kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok                   
scheduler            Healthy   ok                   
etcd-0               Healthy   {"health": "true"}  

```

master初始成功会返回加入node的token，例如：

```
kubeadm join --token 795c0c.c5a1b252c2d23a0c 10.101.83.237:6443 --discovery-token-ca-cert-hash sha256:1c7760c9f02e2f058de3f6bc759e85316b65376cfcc83d975ea6c64ac2175ecc
```

注意token默认24小时过期。如果在这个过程中始终有问题，可以做reset回到干净状态：

```
kubeadm reset
```

## 部署node及加入

* 系统设置同上
* 前面提到的软件需要安装
* 镜像只需要部分
* 运行kubelet的cgroup设置参考前面

```
images=(kube-proxy-amd64:v1.8.7 \
pause-amd64:3.0 \
kubernetes-dashboard-amd64:1.8.1)
images=(kube-proxy-amd64:v1.8.7)
for imageName in ${images[@]} ; do
  docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName
  docker tag registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName gcr.io/google_containers/$imageName
  docker rmi registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName
done
```

贴下镜像列表：

```
$sudo docker images
REPOSITORY                                                                       TAG                 IMAGE ID            CREATED             SIZE
registry.cn-hangzhou.aliyuncs.com/google_containers/kubernetes-dashboard-amd64   v1.8.3              0c60bcf89900        3 weeks ago         102.3 MB
gcr.io/google_containers/kube-proxy-amd64                                        v1.8.7              263b722c47c1        4 weeks ago         93.36 MB
gcr.io/google_containers/pause-amd64                                             3.0                 8ca66ae4813a        4 weeks ago         746.9 kB
gcr.io/google_containers/kubernetes-dashboard-amd64                              1.8.1               758ae6af38ca        5 weeks ago         120.7 MB
quay.io/coreos/flannel                                                           v0.9.1-amd64        2b736d06ca4c        3 months ago        51.31 MB
```

最后使用`kubeadm join xxxx` (部署master时会返回)加入网络。加入后在master端可以确认：

```
$sudo kubectl get nodes
NAME                 STATUS    ROLES     AGE       VERSION
v101083225zsqazzmf   Ready     <none>    2h        v1.8.7
v101083237zsqazzmf   Ready     master    3h        v1.8.7
```

## 部署dashboard

高版本的dashboard出于安全考虑，访问方式发生了变更，需要处理鉴权相关的问题。验证token的方式测试不成功，使用HTTP协议的方式也不成功。最后成功的方式如下：

```
# commit 9159b005f65b21bd6b7156ccabd92f9e50c11333
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
```

**注意** 替换里面的镜像地址，可以直接在阿里云找对应镜像。

参考[stackoverflow](https://stackoverflow.com/questions/46664104/how-to-sign-in-kubernetes-dashboard) 最后一种方法：

```
$ cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard
  labels:
    k8s-app: kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: kubernetes-dashboard
  namespace: kube-system
EOF
```

最后启动proxy，默认端口8001：

```
# 不加disable-filter浏览器端无法访问
kubectl proxy --address `hostname -i` --disable-filter=true
```

浏览器端即可访问：`http://10.101.83.237:8001/ui` 会重定向到新的URI。

## 测试

可以参考官方的例子[stateless application sample](https://v1-8.docs.kubernetes.io/docs/tasks/run-application/run-stateless-application-deployment/) 进行测试。这一步很顺利没有什么问题。同样，注意配置中镜像地址的修改。


