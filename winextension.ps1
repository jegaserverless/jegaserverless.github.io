function Test-MachinePath{
    [CmdletBinding()]
    param(
        [string]$PathItem
    )

    $currentPath = Get-MachinePath

    $pathItems = $currentPath.Split(';')

    if($pathItems.Contains($PathItem))
    {
        return $true
    }
    else
    {
        return $false
    }
}

function Set-MachinePath{
    [CmdletBinding()]
    param(
        [string]$NewPath
    )
    Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name Path -Value $NewPath
    return $NewPath
}

function Add-MachinePathItem
{
    [CmdletBinding()]
    param(
        [string]$PathItem
    )

    $currentPath = Get-MachinePath
    $newPath = $PathItem + ';' + $currentPath
    return Set-MachinePath -NewPath $newPath
}

function Get-MachinePath{
    [CmdletBinding()]
    param(

    )
    $currentPath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
    return $currentPath
}

function Get-SystemVariable{
    [CmdletBinding()]
    param(
        [string]$SystemVariable
    )
    $currentPath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name $SystemVariable).$SystemVariable
    return $currentPath
}

function Set-SystemVariable{
    [CmdletBinding()]
    param(
        [string]$SystemVariable,
        [string]$Value
    )
    Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name $SystemVariable -Value $Value
    return $Value
}

function Install-Binary
{
    <#
    .SYNOPSIS
        A helper function to install executables.

    .DESCRIPTION
        Download and install .exe or .msi binaries from specified URL.

    .PARAMETER Url
        The URL from which the binary will be downloaded. Required parameter.

    .PARAMETER Name
        The Name with which binary will be downloaded. Required parameter.

    .PARAMETER ArgumentList
        The list of arguments that will be passed to the installer. Required for .exe binaries.

    .EXAMPLE
        Install-Binary -Url "https://go.microsoft.com/fwlink/p/?linkid=2083338" -Name "winsdksetup.exe" -ArgumentList ("/features", "+", "/quiet")
    #>

    Param
    (
        [Parameter(Mandatory)]
        [String] $Url,
        [Parameter(Mandatory)]
        [String] $Name,
        [String[]] $ArgumentList
    )

    Write-Host "Downloading $Name..."
    $filePath = Start-DownloadWithRetry -Url $Url -Name $Name

    # MSI binaries should be installed via msiexec.exe
    $fileExtension = ([System.IO.Path]::GetExtension($Name)).Replace(".", "")
    if ($fileExtension -eq "msi")
    {
        $ArgumentList = ('/i', $filePath, '/QN', '/norestart')
        $filePath = "msiexec.exe"
    }

    try
    {
        Write-Host "Starting Install $Name..."
        $process = Start-Process -FilePath $filePath -ArgumentList $ArgumentList -Wait -PassThru

        $exitCode = $process.ExitCode
        if ($exitCode -eq 0 -or $exitCode -eq 3010)
        {
            Write-Host "Installation successful"
        }
        else
        {
            Write-Host "Non zero exit code returned by the installation process: $exitCode"
            exit $exitCode
        }
    }
    catch
    {
        Write-Host "Failed to install the $fileExtension ${Name}: $($_.Exception.Message)"
        exit 1
    }
}

function Start-DownloadWithRetry
{
    Param
    (
        [Parameter(Mandatory)]
        [string] $Url,
        [string] $Name,
        [string] $DownloadPath = "${env:Temp}",
        [int] $Retries = 20
    )

    if ([String]::IsNullOrEmpty($Name)) {
        $Name = [IO.Path]::GetFileName($Url)
    }

    $filePath = Join-Path -Path $DownloadPath -ChildPath $Name

    #Default retry logic for the package.
    while ($Retries -gt 0)
    {
        try
        {
            Write-Host "Downloading package from: $Url to path $filePath ."
            (New-Object System.Net.WebClient).DownloadFile($Url, $filePath)
            break
        }
        catch
        {
            Write-Host "There is an error during package downloading:`n $_"
            $Retries--

            if ($Retries -eq 0)
            {
                Write-Host "File can't be downloaded. Please try later or check that file exists by url: $Url"
                exit 1
            }

            Write-Host "Waiting 30 seconds before retrying. Retries left: $Retries"
            Start-Sleep -Seconds 30
        }
    }

    return $filePath
}

# Set TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor "Tls12"

Write-Host "Setup PowerShellGet"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Specifies the installation policy
Set-PSRepository -InstallationPolicy Trusted -Name PSGallery

################################################################################
##  Desc:  Install Azure CLI
################################################################################
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi


################################################################################
##  Desc:  Install PowerShell Core
################################################################################
Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
# about_update_notifications
# While the update check happens during the first session in a given 24-hour period, for performance reasons,
# the notification will only be shown on the start of subsequent sessions.
# Also for performance reasons, the check will not start until at least 3 seconds after the session begins.
[System.Environment]::SetEnvironmentVariable("POWERSHELL_UPDATECHECK", "Off", [System.EnvironmentVariableTarget]::Machine)
Install-Module -Name az -Scope AllUsers -SkipPublisherCheck -Force

################################################################################
##  Desc:  Install DacFramework
################################################################################
$InstallerName = "DacFramework.msi"
$InstallerUrl = "https://go.microsoft.com/fwlink/?linkid=2157201"
Install-Binary -Url $InstallerUrl -Name $InstallerName


# Install Choco install
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# Install git
choco install git.install -y

Add-MachinePathItem "C:\Program Files\Git\bin"

# Add well-known SSH host keys to ssh_known_hosts
ssh-keyscan -t rsa github.com >> "C:\Program Files\Git\etc\ssh\ssh_known_hosts"
ssh-keyscan -t rsa ssh.dev.azure.com >> "C:\Program Files\Git\etc\ssh\ssh_known_hosts"

# Install Git CLI
$GHName = "gh_windows_amd64.msi"
$GHAssets = (Invoke-RestMethod -Uri "https://api.github.com/repos/cli/cli/releases/latest").assets
$GHDownloadUrl = ($GHAssets.browser_download_url -match "windows_amd64.msi") | Select-Object -First 1
Install-Binary -Url $GHDownloadUrl -Name $GHName
Add-MachinePathItem "C:\Program Files (x86)\GitHub CLI"

################################################################################
##  Desc:  Install SQL PowerShell tool
################################################################################
$AdalsqlBaseUrl = "https://download.microsoft.com/download/6/4/6/64677D6E-06EA-4DBB-AF05-B92403BB6CB9/ENU/x64"
$AdalsqlName = "adalsql.msi"
$AdalsqlUrl = "${AdalsqlBaseUrl}/${AdalsqlName}"
Install-Binary -Url $AdalsqlUrl -Name $AdalsqlName
Install-Module -Name SqlServer -RequiredVersion 21.1.18245
