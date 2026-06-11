param(
  [string]$Namespace = "default",
  [string]$PodName = "qmind-product-spike",
  [string]$TargetUrl = "http://frontend/product/OLJCESPC7Z",
  [int]$DurationSeconds = 180,
  [int]$SleepSeconds = 1
)

Write-Host "=== Quantik Mind Adaptive Entanglement Kubernetes Scenario ==="
Write-Host "Namespace: $Namespace"
Write-Host "Pod: $PodName"
Write-Host "Target URL: $TargetUrl"
Write-Host "Duration: $DurationSeconds sec"
Write-Host "Sleep: $SleepSeconds sec"

kubectl delete pod $PodName -n $Namespace --ignore-not-found | Out-Null

$cmd = "end=`$(date +%s); end=`$((end + $DurationSeconds)); while [ `$(date +%s) -lt `$end ]; do curl -s -o /dev/null $TargetUrl; sleep $SleepSeconds; done"

kubectl run $PodName `
  -n $Namespace `
  --image=curlimages/curl:8.10.1 `
  --restart=Never `
  --command -- sh -c $cmd

Write-Host ""
Write-Host "Scenario pod started."
Write-Host "Wait 60-90 seconds, then run:"
Write-Host "qmind subset --framework playwright"
Write-Host ""
Write-Host "Cleanup:"
Write-Host "kubectl delete pod $PodName -n $Namespace --ignore-not-found"
