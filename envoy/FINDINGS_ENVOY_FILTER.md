# Using envoys use_remote_address option
An [upstream user pointed](https://github.com/knative/serving/issues/12466#issuecomment-1006288116) out their solution using envoys `use_remote_address` option.
This document contains the findings.

## Responses without the setting enabled
```bash
# Response from a request via activator
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://svc-activator-in-path.tenant-1.svc.cluster.local/headers
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=127.0.0.6;proto=http",
    "Host": "svc-activator-in-path.tenant-1.svc.cluster.local",
    "K-Proxy-Request": "activator",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "d572639cc6d75b2b",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "ec858f0875b91408",
    "X-B3-Traceid": "7440c4dab4067e545a23fce413865cdc",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=1d201bda2e513b56e2c883da4ceb560ca160e7f2025043d6aa6cadc11c489bdf;Subject=\"\";URI=spiffe://cluster.local/ns/knative-serving/sa/controller"
  }
}

# Response from a request via ingress-gateway -> activator
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-activator-in-path.tenant-1.svc.cluster.local'
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=127.0.0.6;proto=http",
    "Host": "svc-activator-in-path.tenant-1.svc.cluster.local",
    "K-Proxy-Request": "activator",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "4feb4353d38f2fbf",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "cbf5dec2528d60d3",
    "X-B3-Traceid": "6343651a63fd337572c3b8c3a3cdafad",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=1d201bda2e513b56e2c883da4ceb560ca160e7f2025043d6aa6cadc11c489bdf;Subject=\"\";URI=spiffe://cluster.local/ns/knative-serving/sa/controller"
  }
}

# Response from a request via ingress-gateway (no activator) -> pod
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-always-scaled.tenant-1.svc.cluster.local'
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "proto=http",
    "Host": "svc-always-scaled.tenant-1.svc.cluster.local",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "c9c0ba3c61793a64",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "0251b11430e2a568",
    "X-B3-Traceid": "b71b7a2e600ae1c2c9c0ba3c61793a64",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=015f0a6cde2fdfaa65b3dd14ba0a5b6c213e3aa23a513146861fc126ea3a7e8e;Subject=\"\";URI=spiffe://cluster.local/ns/tenant-1/sa/default"
  }
}
```

## Responses with the setting enabled
```bash
# Enable the setting
kubectl apply -f envoy/envoy-forward-filter.yaml

# Response from a request via activator
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://svc-activator-in-path.tenant-1.svc.cluster.local/headers
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=10.244.3.8;proto=http, for=127.0.0.6, for=10.244.1.5, for=10.244.1.5",
    "Host": "svc-activator-in-path.tenant-1.svc.cluster.local",
    "K-Proxy-Request": "activator",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "1399d1a0ca9a00d5",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "4d3eb2379ecda6c1",
    "X-B3-Traceid": "5d8295d3d837f2614b73791c37fd2cac",
    "X-Envoy-Attempt-Count": "1",
    "X-Envoy-External-Address": "10.244.3.8",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=1d201bda2e513b56e2c883da4ceb560ca160e7f2025043d6aa6cadc11c489bdf;Subject=\"\";URI=spiffe://cluster.local/ns/knative-serving/sa/controller"
  }
}

# Response from a request via ingress-gateway -> activator
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-activator-in-path.tenant-1.svc.cluster.local'
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=10.244.3.8;proto=http, for=10.244.3.8, for=127.0.0.6, for=10.244.1.5, for=10.244.1.5",
    "Host": "svc-activator-in-path.tenant-1.svc.cluster.local",
    "K-Proxy-Request": "activator",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "51b9982ccd889e52",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "67f7e59ac110788c",
    "X-B3-Traceid": "9bd319525ed239d55c449381d44bf448",
    "X-Envoy-Attempt-Count": "1",
    "X-Envoy-External-Address": "10.244.3.8",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=1d201bda2e513b56e2c883da4ceb560ca160e7f2025043d6aa6cadc11c489bdf;Subject=\"\";URI=spiffe://cluster.local/ns/knative-serving/sa/controller"
  }
}

# Response from a request via ingress-gateway (no activator) -> pod
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://knative-local-gateway.istio-system.svc.cluster.local/headers -H 'Host: svc-always-scaled.tenant-1.svc.cluster.local'
{
  "headers": {
    "Accept": "*/*",
    "Forwarded": "for=10.244.3.8;proto=http, for=10.244.3.8",
    "Host": "svc-always-scaled.tenant-1.svc.cluster.local",
    "User-Agent": "curl/7.87.0-DEV",
    "X-B3-Parentspanid": "c92d8a9075a9512b",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "22e7a731417ea386",
    "X-B3-Traceid": "e6a2a69e7a903829c92d8a9075a9512b",
    "X-Envoy-Attempt-Count": "1",
    "X-Envoy-External-Address": "10.244.3.8",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/tenant-1/sa/default;Hash=015f0a6cde2fdfaa65b3dd14ba0a5b6c213e3aa23a513146861fc126ea3a7e8e;Subject=\"\";URI=spiffe://cluster.local/ns/tenant-1/sa/default"
  }
}
```

## Findings
So for all call types, we additionally get the `real source ip` in the `Forwarded` header and an additional header `X-Envoy-External-Address` containing the `real source ip`:
```bash
diff off on
4c4
<     "Forwarded": "for=127.0.0.6;proto=http",
---
>     "Forwarded": "for=10.244.3.8;proto=http, for=127.0.0.6, for=10.244.1.5, for=10.244.1.5",
8a9
>     "X-Envoy-External-Address": "10.244.3.8",
```
