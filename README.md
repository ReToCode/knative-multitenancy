# Serverless multi-tenancy based on Istio (Service Mesh) functionality
The basic idea of this setup is to use Istio (Service Mesh) features to leverage a `network based` isolation 
for multiple tenants. 

# Architecture
![Architecture](https://raw.githubusercontent.com/ReToCode/diagrams/main/knative/multi-tenancy-service-mesh.drawio.svg)

# High level overview
* The setup is enforcing `istio mTLS` while using `AuthorizationPolicies` to isolate workloads.
* As `Knative` has different `data-paths` (via ingress-gateway, via activator, via ingress-gateway and activator or directly through the mesh) network isolation must be enforced on multiple places.
* `PeerAuthentication` is used to enforce `mTLS` on all relevant namespaces.
* `knative-local-gateway` is patched to enforce `istio mTLS`.
* `AuthorizationPolicy` are in place to only allow tenant traffic. The namespace `knative-serving` has additional rules that filter traffic based on `source namespaces` and `target hosts`. 

# Setup (K8S with Kind)

## Prerequisites
* A `kubernetes` cluster with `kubectl` configured
* Installed the following components:

```bash
# Knative Serving
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.8.3/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.8.3/serving-core.yaml

# Istio as networking layer
kubectl apply -l knative.dev/crd-install=true -f https://github.com/knative/net-istio/releases/download/knative-v1.8.1/istio.yaml
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.8.1/istio.yaml

# Enable proxies in knative-serving
kubectl label namespace knative-serving istio-injection=enabled

# Restart containers to pick up the proxy
kubectl delete pod --all -n knative-serving

# Install the net-istio controller
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.8.1/net-istio.yaml
```

## Tenant setup (on Kind)
```bash
# Creating tenants
kubectl create ns tenant-1
kubectl create ns tenant-2
kubectl label namespace tenant-1 istio-injection=enabled
kubectl label namespace tenant-2 istio-injection=enabled

# Apply secured config
kubectl apply -f kind/config 

# Create kservices
kubectl apply -f kind/services/tenant-1
kubectl apply -f kind/services/tenant-2
```

# Setup (OpenShift)
```bash
# Install Service Mesh
oc apply -f openshift/mesh-operators
oc apply -f openshift/mesh-config

# Install Serverless Operator
oc apply -f openshift/serverless-operator
oc apply -f openshift/serverless-config

# Integrate Service Mesh and Serverless
oc apply -f openshift/serverless-mesh-integration
```

## Tenant setup (on OpenShift)
```bash
# Creating tenants
oc new-project tenant-1
oc new-project tenant-2

# Apply secured config
oc apply -f openshift/securing-config

# Create kservices
oc apply -f openshift/services/tenant-1
oc apply -f openshift/services/tenant-2
```

# Verification
Use the script to verify the configuration 
```bash
./hack/verify.sh
```
Example output
```text
Testing same tenant directly
Call to svc-always-scaled-00001-private.tenant-1.svc.cluster.local/headers succeeded
Call to 10.244.3.11/headers succeeded
Testing cross tenant directly (should fail)
Call to svc-always-scaled-00001-private.tenant-1.svc.cluster.local/headers succeeded
Call to 10.244.3.11/headers succeeded
Testing same tenant via activator
Call to svc-activator-in-path.tenant-1.svc.cluster.local/headers succeeded
Call to svc-activator-in-path.tenant-2.svc.cluster.local/headers succeeded
Testing cross tenant via activator (should fail)
Call to svc-activator-in-path.tenant-1.svc.cluster.local/headers succeeded
Testing same tenant via ingress-gateway and activator
Call to knative-local-gateway.istio-system.svc.cluster.local/headers succeeded
Call to knative-local-gateway.istio-system.svc.cluster.local/headers succeeded
Testing cross tenant via ingress-gateway and activator (should fail)
Call to knative-local-gateway.istio-system.svc.cluster.local/headers succeeded
Testing same tenant via ingress-gateway no activator
Call to knative-local-gateway.istio-system.svc.cluster.local/headers succeeded
Call to knative-local-gateway.istio-system.svc.cluster.local/headers succeeded
Testing cross tenant via ingress-gateway no activator (should fail)
Call to knative-local-gateway.istio-system.svc.cluster.local/headers succeeded
✅  All tests completed successfully
```

# Testing

## Testing same tenant directly
### [tenant-1] -> [tenant-1]
```bash
# Directly via k8s private service
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://svc-always-scaled-00001-private.tenant-1.svc.cluster.local/headers
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "proto=http",
    "Host": "svc-always-scaled-00001-private.tenant-1.svc.cluster.local",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "2a8f1b2cb0ca6bf9",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "83529b99ef1980e7",
    "X-B3-Traceid": "583952dce1087bed2a8f1b2cb0ca6bf9",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=c838e811068f18ec3292b88311c1b1c4944ba34e8a0a53ed8efd1db6a9e78b01;Subject=\"\";URI=spiffe://cluster.local/ns/tenant-1/sa/default"
  }
}

# Directly via pod ip
POD_IP=$(kubectl get pod -l serving.knative.dev/configuration=svc-always-scaled -n tenant-1 -o jsonpath="{.items[0].status.podIP}")
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv "http://${POD_IP}/headers" -H 'Host: svc-always-scaled-00001-private.tenant-1.svc.cluster.local'
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "proto=http",
    "Host": "svc-always-scaled-00001-private.tenant-1.svc.cluster.local",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "ac4fa8ff5da2e6f1",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "50d4b124d5139390",
    "X-B3-Traceid": "d34f058a010a7592ac4fa8ff5da2e6f1",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=c838e811068f18ec3292b88311c1b1c4944ba34e8a0a53ed8efd1db6a9e78b01;Subject=\"\";URI=spiffe://cluster.local/ns/tenant-1/sa/default"
  }
}
```

## Testing cross tenant directly (should fail)
### [tenant-2] -> [tenant-1]
```bash
# Directly via k8s private service
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://svc-always-scaled-00001-private.tenant-1.svc.cluster.local/headers
# HTTP/1.1 403 Forbidden
# RBAC: access denied

# The request was denied in the istio-proxy in tenant-1
2023-01-31T12:35:25.789968Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-always-scaled-00001-private.tenant-1.svc.cluster.local, sourceIP: 10.244.2.5:48626, directRemoteIP: 10.244.2.5:48626, remoteIP: 10.244.2.5:48626,localAddress: 10.244.3.8:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-always-scaled-00001-private.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', '2a9b8705-50d8-4ad8-9c63-f0e6d675134a'
'x-envoy-attempt-count', '1'
'x-b3-traceid', '369e395e39048b55b9adf569231d5a3a'
'x-b3-spanid', 'b9adf569231d5a3a'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=587068c5492cbbde398f042b499fbe7d2a5c10d89d353e0ecb1af58293beac13;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T12:35:25.789994Z     debug   envoy rbac      enforced denied, matched policy none


# Directly via pod ip
POD_IP=$(kubectl get pod -l serving.knative.dev/configuration=svc-always-scaled -n tenant-1 -o jsonpath="{.items[0].status.podIP}")
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv "http://${POD_IP}/headers" -H 'Host: svc-always-scaled-00001-private.tenant-1.svc.cluster.local'
# HTTP/1.1 403 Forbidden
# RBAC: access denied

# The request was denied in the istio-proxy in tenant-1
2023-01-31T12:36:00.398043Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-always-scaled-00001-private.tenant-1.svc.cluster.local, sourceIP: 10.244.2.5:48626, directRemoteIP: 10.244.2.5:48626, remoteIP: 10.244.2.5:48626,localAddress: 10.244.3.8:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-always-scaled-00001-private.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', '309d8aaa-e0da-4ad3-a262-a0aa5084e5bb'
'x-envoy-attempt-count', '1'
'x-b3-traceid', 'a38d543371352fddd061c800434ec310'
'x-b3-spanid', 'd061c800434ec310'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=587068c5492cbbde398f042b499fbe7d2a5c10d89d353e0ecb1af58293beac13;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T12:36:00.398225Z     debug   envoy rbac      enforced denied, matched policy none
```

## Testing same tenant via activator
### [tenant-1] -> [activator] -> [tenant-1]
```bash
# Note: this is routed directly to the activator, even though the service points (CNAME) to knative-local-gateway.
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://svc-activator-in-path.tenant-1.svc.cluster.local/headers
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=127.0.0.6;proto=http",
    "Host": "svc-activator-in-path.tenant-1.svc.cluster.local",
    "K-Proxy-Request": "activator",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "b12e83377ddc9f54",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "c6f2e9788ef0bf45",
    "X-B3-Traceid": "d42f69aa2fb623640c0968ddc6e61159",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=e1521c5650156cbfd7e8c99305cb4a8fa929196e46fa34b4dd1f91c3ccd8dcf5;Subject=\"\";URI=spiffe://cluster.local/ns/knative-serving/sa/controller"
  }
}
```

## Testing cross tenant via activator (should fail)
### [tenant-2] -> [activator] -> [tenant-1]
```bash
# Note: this is routed directly to the activator, even though the service points (CNAME) to knative-local-gateway.
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://svc-activator-in-path.tenant-1.svc.cluster.local/headers
# HTTP/1.1 403 Forbidden
# RBAC: access denied

# The request was denied in the istio-proxy in activator
2023-01-31T12:39:53.827806Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-activator-in-path-00001.tenant-1.svc.cluster.local, sourceIP: 10.244.2.5:40768, directRemoteIP: 10.244.2.5:40768, remoteIP: 10.244.2.5:40768,localAddress: 10.244.3.10:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-activator-in-path.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', 'b6b7f318-3cd1-4d01-9d16-c54ed64feea8'
'x-envoy-attempt-count', '1'
'knative-serving-namespace', 'tenant-1'
'knative-serving-revision', 'svc-activator-in-path-00001'
'x-b3-traceid', '526528972e4e218e0b91361d0ced09c6'
'x-b3-spanid', '0b91361d0ced09c6'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/knative-serving/sa/controller;Hash=587068c5492cbbde398f042b499fbe7d2a5c10d89d353e0ecb1af58293beac13;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T12:39:53.827878Z     debug   envoy rbac      enforced denied, matched policy none
```

## Testing same tenant via ingress-gateway and activator
### [tenant-1] -> [istio-ingressgateway] -> [activator] -> [tenant-1]
```bash
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-activator-in-path.tenant-1.svc.cluster.local'
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=127.0.0.6;proto=http",
    "Host": "svc-activator-in-path.tenant-1.svc.cluster.local",
    "K-Proxy-Request": "activator",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "2f2c43bcd2bac779",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "7c81319d6bcc29e3",
    "X-B3-Traceid": "70655bc454f33ee72e412696e00bce2b",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=e1521c5650156cbfd7e8c99305cb4a8fa929196e46fa34b4dd1f91c3ccd8dcf5;Subject=\"\";URI=spiffe://cluster.local/ns/knative-serving/sa/controller"
  }
}
```

## Testing cross tenant via ingress-gateway and activator (should fail)
### [tenant-2] -> [istio-ingressgateway] -> [activator] -> [tenant-1]
```bash
# Note: we must explicitly set the destination to knative-local-gateway, otherwise this would be routed to the activator by istio.
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-activator-in-path.tenant-1.svc.cluster.local'
# HTTP/1.1 403 Forbidden
# RBAC: access denied

# The request was denied in the istio-proxy in activator
2023-01-31T12:42:27.387460Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-activator-in-path-00001.tenant-1.svc.cluster.local, sourceIP: 10.244.2.5:40754, directRemoteIP: 10.244.2.5:40754, remoteIP: 10.244.2.5:40754,localAddress: 10.244.3.10:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-activator-in-path.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', 'b6c569ad-d5c2-476e-a929-f2b7c18d9917'
'x-envoy-attempt-count', '1'
'knative-serving-namespace', 'tenant-1'
'knative-serving-revision', 'svc-activator-in-path-00001'
'x-b3-traceid', '118a47cd6fccbdd0a7aa692ae1070d0c'
'x-b3-spanid', 'a7aa692ae1070d0c'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/knative-serving/sa/controller;Hash=587068c5492cbbde398f042b499fbe7d2a5c10d89d353e0ecb1af58293beac13;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T12:42:27.387491Z     debug   envoy rbac      enforced denied, matched policy none
```

## Testing same tenant via ingress-gateway no activator
### [tenant-1] -> [istio-ingressgateway] -> [tenant-1]
```bash
# Note: we must explicitly set the destination to knative-local-gateway, otherwise this would be routed to the activator by istio.
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-always-scaled.tenant-1.svc.cluster.local'
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "proto=http",
    "Host": "svc-always-scaled.tenant-1.svc.cluster.local",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "92488bf0eb97b2c4",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "abb15c5e3b784c4c",
    "X-B3-Traceid": "7bd3323e2a4e56e892488bf0eb97b2c4",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=c838e811068f18ec3292b88311c1b1c4944ba34e8a0a53ed8efd1db6a9e78b01;Subject=\"\";URI=spiffe://cluster.local/ns/tenant-1/sa/default"
  }
}
```

## Testing cross tenant via ingress-gateway no activator (should fail)
### [tenant-2] -> [istio-ingressgateway] -> [tenant-1]
```bash
# Note: we must explicitly set the destination to knative-local-gateway, otherwise this would be routed to the activator by istio.
kubectl exec deployment/curl -n tenant-2 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-always-scaled.tenant-1.svc.cluster.local'
# HTTP/1.1 403 Forbidden
# RBAC: access denied

# The request was denied in the istio-proxy in tenant-1
2023-01-31T12:44:54.419393Z     debug   envoy rbac      checking request: requestedServerName: outbound_.80_._.svc-always-scaled-00001.tenant-1.svc.cluster.local, sourceIP: 10.244.2.5:48640[0/9633]RemoteIP: 10.244.2.5:48640, remoteIP: 10.244.2.5:48640,localAddress: 10.244.3.8:8012, ssl: uriSanPeerCertificate: spiffe://cluster.local/ns/tenant-2/sa/default, dnsSanPeerCertificate: , subjectPeerCertificate: , headers: ':authority', 'svc-always-scaled.tenant-1.svc.cluster.local'
':path', '/headers'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/7.87.0-DEV'
'accept', '*/*'
'x-forwarded-proto', 'http'
'x-request-id', '7188b123-3f5c-4773-90f1-58364c786733'
'x-envoy-attempt-count', '1'
'knative-serving-namespace', 'tenant-1'
'knative-serving-revision', 'svc-always-scaled-00001'
'x-b3-traceid', '40ae8af4ab0d2fe184f385c2297926a7'
'x-b3-spanid', '84f385c2297926a7'
'x-b3-sampled', '0'
'x-forwarded-client-cert', 'By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=587068c5492cbbde398f042b499fbe7d2a5c10d89d353e0ecb1af58293beac13;Subject="";URI=spiffe://cluster.local/ns/tenant-2/sa/default'
, dynamicMetadata:
2023-01-31T12:44:54.419427Z     debug   envoy rbac      enforced denied, matched policy none
```
