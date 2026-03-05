#!/bin/pwsh
param(
    [switch] $init,
    [switch] $push,
    [switch] $pull,
    [switch] $upcheck,
    [string] $param
)

function Check-Command($command,[scriptblock] $callback)
{
    $cmd = Get-Command $command -ErrorAction SilentlyContinue
    if($null -eq $cmd)
    {
        Write-Host "$command not found!"
        $callback.Invoke($cmd)
    }

}

Check-Command pacman { throw "Pacman not found!" }
Check-command git { throw "Git not found!" }
Check-command makepkg { throw "makepkg not found!" }

$workdir = $(git rev-parse --show-toplevel)
Set-Location $workdir

function Update-Srcinfo($pkg){
    Set-Location $pkg
    makepkg --printsrcinfo > .SRCINFO
    Set-Location $workdir
}



if($init)
{
    Write-Host "Initing Git Subtree..."
    git remote add aur-ez2lazer-git-origin ssh://aur@aur.archlinux.org/ez2lazer-git.git
    git subtree add --prefix=ez2lazer-git aur-ez2lazer-git-origin master
}

if($pull)
{
    Write-Host "Pulling from AUR..."

    git subtree pull --prefix=ez2lazer-git aur-ez2lazer-git-origin master
}

if($push)
{
    Write-Host "Pushing to AUR..."

    git subtree push --prefix=ez2lazer-git aur-ez2lazer-git-origin master
    Update-Srcinfo $workdir/ez2lazer-git
}


if($upcheck)
{
    Write-Host "checking for package: $param"

}
