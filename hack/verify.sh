#!/usr/bin/env bash

function curl_and_assert() {
  local from_tenant=$1
  local url=$2
  local expected=$3
  local host_header=${4:-""}

  if [[ $host_header != "" ]]; then
    host_header="Host: $host_header"
  fi

  status_code=$(kubectl exec deployment/curl -n "$from_tenant" -it -- curl --write-out "%{http_code}" --silent --output /dev/null -H "${host_header}" "http://${url}")

  if [[ $status_code != "$expected" ]]; then
    echo "⛔️  Call to ${url} did not respond as expected. Got: ${status_code}, want: ${expected}"
    exit 1
  else
    echo "Call to ${url} succeeded"
  fi
}

echo "Testing same tenant directly"
curl_and_assert "tenant-1" "svc-always-scaled-00001-private.tenant-1.svc.cluster.local/headers" 200

POD_IP=$(kubectl get pod -l serving.knative.dev/configuration=svc-always-scaled -n tenant-1 -o jsonpath="{.items[0].status.podIP}")
curl_and_assert "tenant-1" "${POD_IP}/headers" 200 "svc-always-scaled-00001-private.tenant-1.svc.cluster.local"

echo "Testing cross tenant directly (should fail)"
curl_and_assert "tenant-2" "svc-always-scaled-00001-private.tenant-1.svc.cluster.local/headers" 403

POD_IP=$(kubectl get pod -l serving.knative.dev/configuration=svc-always-scaled -n tenant-1 -o jsonpath="{.items[0].status.podIP}")
curl_and_assert "tenant-2" "${POD_IP}/headers" 403 "svc-always-scaled-00001-private.tenant-1.svc.cluster.local"

echo "Testing same tenant via activator"
curl_and_assert "tenant-1" "svc-activator-in-path.tenant-1.svc.cluster.local/headers" 200
curl_and_assert "tenant-2" "svc-activator-in-path.tenant-2.svc.cluster.local/headers" 200

echo "Testing cross tenant via activator (should fail)"
curl_and_assert "tenant-2" "svc-activator-in-path.tenant-1.svc.cluster.local/headers" 403

echo "Testing same tenant via ingress-gateway and activator"
curl_and_assert "tenant-1" "knative-local-gateway.istio-system.svc.cluster.local/headers" 200 "svc-activator-in-path.tenant-1.svc.cluster.local"
curl_and_assert "tenant-2" "knative-local-gateway.istio-system.svc.cluster.local/headers" 200 "svc-activator-in-path.tenant-2.svc.cluster.local"

echo "Testing cross tenant via ingress-gateway and activator (should fail)"
curl_and_assert "tenant-2" "knative-local-gateway.istio-system.svc.cluster.local/headers" 403 "svc-activator-in-path.tenant-1.svc.cluster.local"

echo "Testing same tenant via ingress-gateway no activator"
curl_and_assert "tenant-1" "knative-local-gateway.istio-system.svc.cluster.local/headers" 200 "svc-always-scaled.tenant-1.svc.cluster.local"
curl_and_assert "tenant-2" "knative-local-gateway.istio-system.svc.cluster.local/headers" 200 "svc-always-scaled.tenant-2.svc.cluster.local"

echo "Testing cross tenant via ingress-gateway no activator (should fail)"
curl_and_assert "tenant-2" "knative-local-gateway.istio-system.svc.cluster.local/headers" 403 "svc-always-scaled.tenant-1.svc.cluster.local"

echo "✅  All tests completed successfully"
