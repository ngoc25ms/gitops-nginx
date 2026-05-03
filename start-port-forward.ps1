# Chay script nay moi lan muon dung ArgoCD UI va nginx app
# Mo PowerShell va chay: .\start-port-forward.ps1

Write-Host "Starting port-forwards..." -ForegroundColor Cyan

# ArgoCD UI -> http://localhost:8888
Start-Process powershell -ArgumentList "-NoExit", "-Command", "kubectl port-forward svc/argocd-server -n argocd 8888:80; Read-Host 'Press Enter to close'"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "  ArgoCD UI  : http://localhost:8888" -ForegroundColor Yellow
Write-Host "  User       : admin" -ForegroundColor Yellow
Write-Host "  Pass       : yPe1l6p0g4qA-daq" -ForegroundColor Yellow
Write-Host "  CLI login  : argocd login argocd-server --port-forward --port-forward-namespace argocd --username admin --password 'yPe1l6p0g4qA-daq' --plaintext --grpc-web" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Green
