# Issues found with this setup

## Use case [tenant-1] -> [istio-ingress-gateway]

### Setup
```yaml
  kind: AuthorizationPolicy
  metadata:
    annotations:
    name: allow-traffic-to-istio-system
    namespace: istio-system
  spec:
    action: ALLOW
    rules:
    - from:
      - source:
          namespaces:
          - istio-system
          - tenant-1
          - tenant-2
    selector:
      matchLabels:
        app: istio-ingressgateway
```
```yaml
  apiVersion: security.istio.io/v1beta1
  kind: PeerAuthentication
  metadata:
    name: default
    namespace: istio-system
  spec:
    mtls:
      mode: STRICT
```

### Test case
```bash
kubectl exec deployment/curl -n tenant-1 -it -- curl -siv http://istio-ingressgateway.istio-system.svc.cluster.local
# RBAC: access denied

# Logs on istio-ingressgateway
 2023-01-27T10:19:14.467755Z    debug    envoy rbac    checking request: requestedServerName: , sourceIP: 10.244.3.32:40364, directRemoteIP: 10.244.3.32:40364, remoteIP: 10.244.3.32:40364,localAddress: 10.244.3.36:8080, ssl: none, head │
│ ':path', '/'                                                                                                                                                                                                                               │
│ ':method', 'GET'                                                                                                                                                                                                                           │
│ ':scheme', 'http'                                                                                                                                                                                                                          │
│ 'user-agent', 'curl/7.87.0-DEV'                                                                                                                                                                                                            │
│ 'accept', '*/*'                                                                                                                                                                                                                            │
│ 'x-forwarded-proto', 'http'                                                                                                                                                                                                                │
│ 'x-request-id', '88c722b9-f22e-491e-b034-2787e973a41d'                                                                                                                                                                                     │
│ 'x-envoy-decorator-operation', 'istio-ingressgateway.istio-system.svc.cluster.local:80/*'                                                                                                                                                  │
│ 'x-envoy-attempt-count', '1'                                                                                                                                                                                                               │
│ 'x-b3-traceid', '172984dc4b2f0bd360fa2f391b1c0d81'                                                                                                                                                                                         │
│ 'x-b3-spanid', '60fa2f391b1c0d81'                                                                                                                                                                                                          │
│ 'x-b3-sampled', '0'                                                                                                                                                                                                                        │
│ 'x-forwarded-for', '10.244.3.32'                                                                                                                                                                                                           │
│ 'x-envoy-internal', 'true'                                                                                                                                                                                                                 │
│ 'x-envoy-peer-metadata', 'ChQKDkFQUF9DT05UQUlORVJTEgIaAAoaCgpDTFVTVEVSX0lEEgwaCkt1YmVybmV0ZXMKHQoMSU5TVEFOQ0VfSVBTEg0aCzEwLjI0NC4zLjM2ChkKDUlTVElPX1ZFUlNJT04SCBoGMS4xNi4xCpwDCgZMQUJFTFMSkQMqjgMKHQoDYXBwEhYaFGlzdGlvLWluZ3Jlc3NnYXRld2F5 │
│ 'x-envoy-peer-metadata-id', 'router~10.244.3.36~istio-ingressgateway-6785fcd48-qmq8g.istio-system~istio-system.svc.cluster.local'                                                                                                          │
│ , dynamicMetadata:                                                                                                                                                                                                                         │
│ 2023-01-27T10:19:14.467862Z    debug    envoy rbac    enforced denied, matched policy none 
```

**Findings**
* We do net get istio mTLS from `tenant-1` to `istio-ingressgateway` even when mTLS is on `STRICT`
* We cannot use `namespace` or `principal` matches in `istio-system`
