# iis-deploy.ps1
# Called by GitHub Actions. Params injected by the workflow.
param(
    [Parameter(Mandatory)] [string] $Environment,  # dev | test | stage | prod
    [Parameter(Mandatory)] [string] $ArtifactPath, # path to extracted publish folder
    [Parameter(Mandatory)] [string] $Version
)

$envConfig = @{
    dev   = @{ Site = "TESTAPI-dev";   Pool = "TESTAPI-dev";   Port = 8080; Path = "C:\inetpub\wwwroot\TESTAPI-dev"   }
    test  = @{ Site = "TESTAPI-test";  Pool = "TESTAPI-test";  Port = 8081; Path = "C:\inetpub\wwwroot\TESTAPI-test"  }
    stage = @{ Site = "TESTAPI-stage"; Pool = "TESTAPI-stage"; Port = 8082; Path = "C:\inetpub\wwwroot\TESTAPI-stage" }
    prod  = @{ Site = "TESTAPI-prod";  Pool = "TESTAPI-prod";  Port = 8083; Path = "C:\inetpub\wwwroot\TESTAPI-prod"  }
}

$cfg = $envConfig[$Environment]
if (-not $cfg) { Write-Error "Unknown environment: $Environment"; exit 1 }

Write-Host "Deploying v$Version to $Environment ($($cfg.Site) on :$($cfg.Port))" -ForegroundColor Cyan

Import-Module WebAdministration

# Create site + pool if first deploy
if (-not (Test-Path "IIS:\Sites\$($cfg.Site)")) {
    Write-Host "First deploy — creating IIS site and app pool..." -ForegroundColor Yellow

    New-Item -ItemType Directory -Path $cfg.Path -Force | Out-Null

    if (-not (Test-Path "IIS:\AppPools\$($cfg.Pool)")) {
        New-WebAppPool -Name $cfg.Pool
        Set-ItemProperty "IIS:\AppPools\$($cfg.Pool)" -Name managedRuntimeVersion -Value ""
    }

    New-Website -Name $cfg.Site -PhysicalPath $cfg.Path -ApplicationPool $cfg.Pool -Port $cfg.Port -Force | Out-Null

    # Grant app pool read access
    $acl = Get-Acl $cfg.Path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IIS AppPool\$($cfg.Pool)", "ReadAndExecute",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $cfg.Path -AclObject $acl
}

# Stop pool, copy files, start pool
Write-Host "Stopping app pool..." -ForegroundColor Yellow
Stop-WebAppPool -Name $cfg.Pool -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Copying files from $ArtifactPath to $($cfg.Path)..." -ForegroundColor Yellow
robocopy $ArtifactPath $cfg.Path /MIR /NFL /NDL /NJH /NJS /nc /ns /np
if ($LASTEXITCODE -ge 8) { Write-Error "Robocopy failed with exit code $LASTEXITCODE"; exit 1 }

Write-Host "Starting app pool..." -ForegroundColor Yellow
Start-WebAppPool -Name $cfg.Pool

Write-Host "Deploy complete. http://localhost:$($cfg.Port)/swagger" -ForegroundColor Green
