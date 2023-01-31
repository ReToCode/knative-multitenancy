# Serverless Multi-Tenancy based on Istio (Service Mesh) functionality

# Architecture
![Architecture](https://raw.githubusercontent.com/ReToCode/diagrams/main/multi-tenancy/multitenancy-service-mesh.drawio.svg)

# Setup (K8S with Kind)

## Prerequisites
* A `kubernetes` cluster with `kubectl` configured that can provide services with type `LoadBalancer`
* Installed the following components:

```bash
# Knative Serving
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.8.3/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.8.3/serving-core.yaml

# Istio as networking layer
# Install istioctl based on https://knative.dev/docs/install/installing-istio/#installing-istio-without-sidecar-injection
istioctl install -y

# Enable proxies in knative-serving
kubectl label namespace knative-serving istio-injection=enabled

# Restart containers to pick up the proxy
kubectl delete pod --all -n knative-serving

# Install the net-istio controller
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.8.1/net-istio.yaml

kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"172.18.255.200.sslip.io":""}}'
```

# Tenant setup
```bash
# Creating tenants
kubectl create ns tenant-1
kubectl create ns tenant-2
kubectl label namespace tenant-1 istio-injection=enabled
kubectl label namespace tenant-2 istio-injection=enabled

# Apply istio securing config
kubectl apply -f config 

# Create kservices
kubectl apply -f services/tenant-1
kubectl apply -f services/tenant-2
```

# Verification
Use the script to verify the configuration 
```bash
./hack/verify.sh
```

# Testing

## [tenant-2] -> [direct] -> [K8S service in tenant-1]
``` bash
# Send requests to private service, to avoid activator
kubectl get svc svc-always-scaled-00001-private -n tenant-1

NAME                              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                              AGE
svc-always-scaled-00001-private   ClusterIP   10.96.128.175   <none>        80/TCP,443/TCP,9090/TCP,9091/TCP,8022/TCP,8012/TCP   3d4h

kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://svc-always-scaled-00001-private.tenant-1.svc.cluster.local/headers

* Mark bundle as not supporting multiuse
< HTTP/1.1 403 Forbidden
HTTP/1.1 403 Forbidden
<
* Connection #0 to host svc-always-scaled-00001-private.tenant-1.svc.cluster.local left intact
RBAC: access denied

# Logs of pod in tenant-1
2023-01-31T08:02:58.858375Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-always-scaled-00001-private.tenant-1.svc.cluster.local, sourceIP: 10.244.2.7:42808, directRemoteIP: 10.244.2.7:42808, remoteIP: 10.244.2.7:42808,localAddress: 10.244.2.4:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-always-scaled-00001-private.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', 'f658c7e7-f251-44ba-8f43-d60e3615fa93'
'x-envoy-attempt-count', '1'
'x-b3-traceid', '483f28725e5d2b14c11b2dd639646df3'
'x-b3-spanid', 'c11b2dd639646df3'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=d8f0a8ab8f11c5bed5bddbc8d97ea9ce68e500d62ee7489f789f17e6b6b3302e;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T08:02:58.858503Z     debug   envoy rbac      enforced denied, matched policy none
```

## [tenant-2] -> [direct] -> [pod ip in tenant-1]
```bash
POD_IP=$(kubectl get pod  -l serving.knative.dev/configuration=svc-always-scaled -n tenant-1 -o jsonpath="{.items[0].status.podIP}")

kubectl exec deployment/curl -n tenant-2 -it -- curl -siv "http://${POD_IP}/headers" -H 'Host: svc-always-scaled-00001-private.tenant-1.svc.cluster.local'

* Mark bundle as not supporting multiuse
< HTTP/1.1 403 Forbidden
HTTP/1.1 403 Forbidden
<
* Connection #0 to host 10.244.2.4 left intact
RBAC: access denied

# Logs of pod in tenant-1
2023-01-31T08:04:50.113014Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-always-scaled-00001-private.tenant-1.svc.cluster.local, sourceIP: 10.244.2.7:42808, directRemoteIP: 10.244.2.7:42808, remoteIP: 10.244.2.7:42808,localAddress: 10.244.2.4:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-always-scaled-00001-private.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', '6efbe556-8681-49e3-9dc3-47389a23e6fa'
'x-envoy-attempt-count', '1'
'x-b3-traceid', 'cd1e76ed4d847315fb4648a778d48778'
'x-b3-spanid', 'fb4648a778d48778'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=d8f0a8ab8f11c5bed5bddbc8d97ea9ce68e500d62ee7489f789f17e6b6b3302e;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T08:04:50.113039Z     debug   envoy rbac      enforced denied, matched policy none
```

## [tenant-1] -> [activator] -> [tenant-1]
```bash
# svc-activator-in-path has activator always in path
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://svc-activator-in-path.tenant-1.svc.cluster.local/headers

{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=127.0.0.6;proto=http",
    "Host": "svc-activator-in-path.tenant-1.svc.cluster.local",
    "K-Proxy-Request": "activator",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "451cf6b64b7b11f1",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "cf03a76789f08ca2",
    "X-B3-Traceid": "9b8c23e52224ea19f58b0761e9cdb97b",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=06d0f862e6fd488dd073f745b4af941d6ae6c61ec2f66446af19209a64962dc0;Subject=\"\";URI=spiffe://cluster.local/ns/knative-serving/sa/controller"
  }
}

# Logs of pod in tenant-1
2023-01-31T08:09:38.162458Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-activator-in-path-00001-private.tenant-1.svc.cluster.local, sourceIP: 10.244.1.2:35592, directRemoteIP: 10.244.1.2:35592, remoteIP: 127.0.0.6:0,localAddress: 10.244.3.13:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/knative-serving/sa/controller, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', '10.96.204.52:80'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'k-original-host', 'svc-activator-in-path.tenant-1.svc.cluster.local'
'k-proxy-request', 'activator'
'x-envoy-attempt-count', '1'
'x-forwarded-for', '127.0.0.6'
'x-forwarded-proto', 'http'
'x-request-id', 'b210a1e7-82ae-462b-9065-4bf0bbbcc42e'
'x-b3-traceid', '9b8c23e52224ea19f58b0761e9cdb97b'
'x-b3-spanid', '451cf6b64b7b11f1'
'x-b3-parentspanid', 'fb09dac8fc6a357d'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=06d0f862e6fd488dd073f745b4af941d6ae6c61ec2f66446af19209a64962dc0;Subject="";URI=spiffe://cluster.local/ns/knative-serving/sa/controller'
, dynamicMetadata:
2023-01-31T08:09:38.162528Z     debug   envoy rbac      enforced allowed, matched policy ns[tenant-1]-policy[allow-traffic-to-tenant-1]-rule[0]
```

## [tenant-2] -> [activator] -> [tenant-2]
```bash
# svc-activator-in-path has activator always in path
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://svc-activator-in-path.tenant-2.svc.cluster.local/headers
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=127.0.0.6;proto=http",
    "Host": "svc-activator-in-path.tenant-2.svc.cluster.local",
    "K-Proxy-Request": "activator",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "169fbb304fe3b2d3",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "4e056ffa9f5e4228",
    "X-B3-Traceid": "3d7495e33f9f23c36c47b03b898d442e",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-2/sa/default;Hash=06d0f862e6fd488dd073f745b4af941d6ae6c61ec2f66446af19209a64962dc0;Subject=\"\";URI=spiffe://cluster.local/ns/knative-serving/sa/controller"
  }
}
```

## [tenant-2] -> [activator] -> [tenant-1]
```bash
# svc-activator-in-path has activator always in path
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://svc-activator-in-path.tenant-1.svc.cluster.local/headers

* Mark bundle as not supporting multiuse
< HTTP/1.1 403 Forbidden
HTTP/1.1 403 Forbidden
< content-length: 19
content-length: 19
< content-type: text/plain
content-type: text/plain
< date: Tue, 31 Jan 2023 08:12:54 GMT
date: Tue, 31 Jan 2023 08:12:54 GMT
< server: envoy
server: envoy
< x-envoy-upstream-service-time: 0
x-envoy-upstream-service-time: 0

<
* Connection #0 to host svc-activator-in-path.tenant-1.svc.cluster.local left intact
RBAC: access denied

# Logs in activator
2023-01-31T08:12:54.628069Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-activator-in-path-00001.tenant-1.svc.cluster.local, sourceIP: 10.244.2.7:45142, directRemoteIP: 10.244.2.7:45142, remoteIP: 10.244.2.7:45142,localAddress: 10.244.1.2:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-activator-in-path.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', '0d2467d3-47d2-405b-951d-dbc1d410ad80'
'x-envoy-attempt-count', '1'
'knative-serving-namespace', 'tenant-1'
'knative-serving-revision', 'svc-activator-in-path-00001'
'x-b3-traceid', 'e608bba6fcc1bfa4492345a5e102959b'
'x-b3-spanid', '492345a5e102959b'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/knative-serving/sa/controller;Hash=d8f0a8ab8f11c5bed5bddbc8d97ea9ce68e500d62ee7489f789f17e6b6b3302e;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T08:12:54.628114Z     debug   envoy rbac      enforced denied, matched policy none
```

## [tenant-1] -> [ingress-gateway] -> [activator] -> [tenant-1]
```bash
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://svc-always-scaled.tenant-1.svc.cluster.local/headers
```

## [tenant-2] -> [ingress-gateway] -> [activator] -> [tenant-2]
```bash
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-activator-in-path.tenant-1.svc.cluster.local'



# Logs in activator
2023-01-31T09:25:09.579076Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-activator-in-path-00001.tenant-1.svc.cluster.local, sourceIP: 10.244.2.7:45142, directRemoteIP: 10.244.2.7:45142, remoteIP: 10.244.2.7:45142,localAddress: 10.244.1.2:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-activator-in-path.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', 'f4ce0be0-029d-4499-ad96-658c0160e87b'
'x-envoy-attempt-count', '1'
'knative-serving-namespace', 'tenant-1'
'knative-serving-revision', 'svc-activator-in-path-00001'
'x-b3-traceid', '2180e2cf0d1b08339e01c60da9b0cd0f'
'x-b3-spanid', '9e01c60da9b0cd0f'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/knative-serving/sa/controller;Hash=d8f0a8ab8f11c5bed5bddbc8d97ea9ce68e500d62ee7489f789f17e6b6b3302e;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T09:25:09.579108Z     debug   envoy rbac      enforced denied, matched policy none
``` 

## [tenant-2] -> [ingress-controller] -> [direct] -> [tenant-1]
```bash
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-activator-in-path.tenant-1.svc.cluster.local'


```