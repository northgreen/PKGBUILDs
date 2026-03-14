#!/bin/pwsh
<#
.SYNOPSIS
    PKGBUILD maintenance utility script

.DESCRIPTION
    Helps manage PKGBUILD packages including AUR sync, version checking, and source info updates.

.PARAMETER init
    Initialize git subtree for a package from AUR

.PARAMETER pull
    Pull changes from AUR for a package

.PARAMETER push
    Push changes to AUR for a package

.PARAMETER upcheck
    Check for upstream version updates for a package

.PARAMETER list
    List all available packages in the repository

.PARAMETER package
    Specify which package to operate on (default: all packages)

.PARAMETER help
    Show this help message

.EXAMPLE
    ./utils.ps1 -list
    List all available packages

.EXAMPLE
    ./utils.ps1 -init -package ez2lazer-git
    Initialize ez2lazer-git from AUR

.EXAMPLE
    ./utils.ps1 -pull
    Pull all packages from AUR

.EXAMPLE
    ./utils.ps1 -upcheck -package deep-student-git
    Check for upstream updates for deep-student-git
#>

param(
    [switch] $init,
    [switch] $push,
    [switch] $pull,
    [switch] $upcheck,
    [switch] $list,
    [switch] $help,
    [string] $package = ""
)

# Show help
if($help)
{
    Get-Help $PSCommandPath -Full
    exit 0
}

# ============================================================================
# Utility Functions
# ============================================================================

<#
.SYNOPSIS
    Check if a command exists
#>
function Check-Command($command, [scriptblock] $callback)
{
    $cmd = Get-Command $command -ErrorAction SilentlyContinue
    if($null -eq $cmd)
    {
        Write-Host "❌ Error: $command not found!" -ForegroundColor Red
        if($callback)
        {
            $callback.Invoke($cmd)
        }
        else
        {
            exit 1
        }
    }
    else
    {
        Write-Host "✓ Found: $command" -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Get list of package directories
#>
function Get-Packages
{
    $pkgDirs = Get-ChildItem -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "PKGBUILD")
    }
    return $pkgDirs.Name
}

<#
.SYNOPSIS
    Test if a package exists in the repository
#>
function Test-PackageExists($pkg)
{
    return -not [string]::IsNullOrEmpty($pkg) -and $packages.Contains($pkg)
}

<#
.SYNOPSIS
    Update .SRCINFO for a package
#>
function Update-Srcinfo($pkg)
{
    Write-Host "  → Updating .SRCINFO for $pkg..." -ForegroundColor Yellow
    $pkgDir = Join-Path $workdir $pkg
    Set-Location $pkgDir
    $result = makepkg --printsrcinfo > .SRCINFO 2>&1
    if($LASTEXITCODE -ne 0)
    {
        Write-Host "    ❌ Failed to update .SRCINFO" -ForegroundColor Red
        return $false
    }
    Write-Host "    ✓ .SRCINFO updated" -ForegroundColor Green
    Set-Location $workdir
    return $true
}

<#
.SYNOPSIS
    Execute git subtree operation for a package
#>
function Invoke-GitSubtree($pkg, $action, [switch] $UpdateSrcinfo)
{
    $remoteName = "aur-$pkg-origin"
    $cmd = "git subtree $action --prefix=$pkg $remoteName master"

    Write-Host "  → $action $pkg..." -ForegroundColor Yellow
    $result = Invoke-Expression $cmd 2>&1

    if($LASTEXITCODE -ne 0)
    {
        return @{
            Success = $false
            Error = $result
        }
    }

    Write-Host "    ✓ ${action}ed $pkg" -ForegroundColor Green

    if($UpdateSrcinfo)
    {
        Update-Srcinfo $pkg | Out-Null
    }

    return @{
        Success = $true
    }
}

<#
.SYNOPSIS
    Execute operation on package(s)
.PARAMETER Operation
    Scriptblock to execute for each package
.PARAMETER AllowAll
    Allow operation on all packages if none specified
#>
function Invoke-PackageOperation([scriptblock] $Operation, [switch] $AllowAll)
{
    if([string]::IsNullOrEmpty($package))
    {
        if(-not $AllowAll)
        {
            Write-Host "❌ Error: -package parameter required" -ForegroundColor Red
            exit 1
        }

        # Execute on all packages
        foreach($pkg in $packages)
        {
            $Operation.Invoke($pkg)
        }
    }
    else
    {
        if(-not (Test-PackageExists $package))
        {
            Write-Host "❌ Error: Package '$package' not found" -ForegroundColor Red
            exit 1
        }

        # Execute on single package
        $Operation.Invoke($package)
    }
}

<#
.SYNOPSIS
    Check for upstream version updates for a package
#>
function Check-Upstream($pkg)
{
    Write-Host "  → Checking $pkg..." -ForegroundColor Yellow

    $pkgDir = Join-Path $workdir $pkg
    $pkgbuild = Join-Path $pkgDir "PKGBUILD"

    if(-not (Test-Path $pkgbuild))
    {
        Write-Host "    ⚠ PKGBUILD not found" -ForegroundColor Yellow
        return
    }

    # Get current version
    $pkgverLine = Select-String -Path $pkgbuild -Pattern "^pkgver=" | Select-Object -First 1
    $currentVer = ""
    if($pkgverLine)
    {
        $currentVer = ($pkgverLine.Line -split '=')[1].Trim().Trim('"').Trim("'")
        Write-Host "    Current version: $currentVer" -ForegroundColor Gray
    }

    # Try to extract latest version from GitHub URLs
    $latestVer = "unknown"
    $githubUrls = Select-String -Path $pkgbuild -Pattern 'https://github\.com/[^/]+/[^/]+/(releases|archive|tags)' -AllMatches

    if($githubUrls.Matches.Count -gt 0)
    {
        foreach($match in $githubUrls.Matches)
        {
            $url = $match.Value -replace 'archive/.*$', 'refs/tags'
            $url = $url -replace 'releases/.*$', 'releases'

            try
            {
                Write-Host "    Fetching from: $url" -ForegroundColor DarkGray
                $response = curl -s -L --max-time 10 $url 2>&1
                if($LASTEXITCODE -eq 0 -and $response)
                {
                    # Extract version tags
                    $versions = $response | Select-String -Pattern 'v?\d+\.\d+\.\d+' -AllMatches |
                               Select-Object -ExpandProperty Matches |
                               Select-Object -ExpandProperty Value |
                               Sort-Object -Unique

                    if($versions)
                    {
                        $latestVer = $versions | Select-Object -Last 1
                        $latestVer = $latestVer -replace '^v', ''
                        Write-Host "    Latest version: $latestVer" -ForegroundColor Gray
                        break
                    }
                }
            }
            catch
            {
                continue
            }
        }
    }

    # Compare versions
    if($latestVer -ne "unknown" -and $currentVer -ne "")
    {
        if($latestVer -gt $currentVer)
        {
            Write-Host "    ⬆️ Update available: $currentVer → $latestVer" -ForegroundColor Green
        }
        else
        {
            Write-Host "    ✓ Up to date" -ForegroundColor Green
        }
    }
    else
    {
        Write-Host "    ⚠ Could not determine latest version" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Initialize package from AUR
#>
function Initialize-Package($pkg)
{
    $remoteName = "aur-$pkg-origin"
    $aurUrl = "ssh://aur@aur.archlinux.org/$pkg.git"

    Write-Host "  → Adding remote: $aurUrl" -ForegroundColor Yellow
    git remote add $remoteName $aurUrl 2>&1 | Out-Null

    Write-Host "  → Adding subtree..." -ForegroundColor Yellow
    $result = git subtree add --prefix=$pkg $remoteName master 2>&1
    if($LASTEXITCODE -ne 0)
    {
        Write-Host "    ❌ Failed to add subtree" -ForegroundColor Red
        Write-Host $result
        exit 1
    }

    Write-Host "  ✓ Initialized $pkg from AUR" -ForegroundColor Green
}

# ============================================================================
# Initialization
# ============================================================================

Write-Host "`n=== Checking required commands ===" -ForegroundColor Cyan
Check-Command "pacman" { exit 1 }
Check-Command "git" { exit 1 }
Check-Command "makepkg" { exit 1 }
Check-Command "curl" { exit 1 }

# Get work directory
$workdir = $(git rev-parse --show-toplevel 2>&1)
if($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($workdir))
{
    Write-Host "❌ Error: Not in a git repository!" -ForegroundColor Red
    exit 1
}
Set-Location $workdir
Write-Host "✓ Work directory: $workdir" -ForegroundColor Green

# Get package list
$packages = Get-Packages
Write-Host "✓ Found $($packages.Count) packages: $($packages -join ', ')" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Operations
# ============================================================================

# List packages
if($list)
{
    Write-Host "=== Available packages ===" -ForegroundColor Cyan
    foreach($pkg in $packages)
    {
        $pkgDir = Join-Path $workdir $pkg
        $pkgbuild = Join-Path $pkgDir "PKGBUILD"

        if(Test-Path $pkgbuild)
        {
            $pkgver = Select-String -Path $pkgbuild -Pattern "^pkgver=" | Select-Object -First 1
            $pkgrel = Select-String -Path $pkgbuild -Pattern "^pkgrel=" | Select-Object -First 1

            Write-Host "  • $pkg" -ForegroundColor White
            if($pkgver) { Write-Host "    $($pkgver.Line.Trim())" -ForegroundColor Gray }
            if($pkgrel) { Write-Host "    $($pkgrel.Line.Trim())" -ForegroundColor Gray }
        }
    }
    exit 0
}

# Initialize package from AUR
if($init)
{
    Write-Host "=== Initializing package from AUR ===" -ForegroundColor Cyan
    Invoke-PackageOperation { Initialize-Package $args[0] }
    exit 0
}

# Pull from AUR
if($pull)
{
    Write-Host "=== Pulling from AUR ===" -ForegroundColor Cyan

    Invoke-PackageOperation -AllowAll {
        $pkg = $args[0]
        $result = Invoke-GitSubtree $pkg "pull" -UpdateSrcinfo

        if(-not $result.Success)
        {
            Write-Host "    ⚠ Warning: Failed to pull $pkg" -ForegroundColor Yellow
            Write-Host $result.Error
        }
    }

    exit 0
}

# Push to AUR
if($push)
{
    Write-Host "=== Pushing to AUR ===" -ForegroundColor Cyan

    Invoke-PackageOperation -AllowAll {
        $pkg = $args[0]
        $result = Invoke-GitSubtree $pkg "push" -UpdateSrcinfo

        if(-not $result.Success)
        {
            Write-Host "    ⚠ Warning: Failed to push $pkg" -ForegroundColor Red
            Write-Host $result.Error
        }
    }

    exit 0
}

# Check for upstream updates
if($upcheck)
{
    Write-Host "=== Checking for upstream updates ===" -ForegroundColor Cyan
    Invoke-PackageOperation -AllowAll { Check-Upstream $args[0] }
    exit 0
}

# No operation specified
Write-Host "No operation specified. Use -help for usage information." -ForegroundColor Yellow
exit 1