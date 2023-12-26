<#PSScriptInfo
.VERSION 1.1
.AUTHOR Yesua Menchón
.COPYRIGHT
.RELEASENOTES
Version 1.0: Initial version.
.PRIVATEDATA
#>

Param()


# If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64")
{
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe")
    {
        & "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy bypass -File "$PSCommandPath"
        Exit $lastexitcode
    }
}

# Create a tag file just so Intune knows this was installed
if (-not (Test-Path "$($env:ProgramData)\Microsoft\RenameComputer"))
{
    Mkdir "$($env:ProgramData)\Microsoft\RenameComputer"
}
Set-Content -Path "$($env:ProgramData)\Microsoft\RenameComputer\RenameComputer.ps1.tag" -Value "Installed"

# Initialization
$dest = "$($env:ProgramData)\Microsoft\RenameComputer"
if (-not (Test-Path $dest))
{
    mkdir $dest
}
Start-Transcript "$dest\RenameComputer.log" -Append

# See if we are AD or AAD joined
$details = Get-ComputerInfo
$isAD = $false
$isAAD = $false
if ($details.CsPartOfDomain) {
    Write-Host "Device is joined to AD domain: $($details.CsDomain)"
    $isAD = $true
    $goodToGo = $false
} else {
    $goodToGo = $true
    $subKey = Get-Item "HKLM:/SYSTEM/CurrentControlSet/Control/CloudDomainJoin/JoinInfo"
    $guids = $subKey.GetSubKeyNames()
    foreach($guid in $guids) {
        $guidSubKey = $subKey.OpenSubKey($guid);
        $tenantId = $guidSubKey.GetValue("TenantId");
    }
    if ($null -ne $tenantID) {
        Write-Host "Device is joined to AAD tenant: $tenantID"
        $isAAD = $true
    } else {
        Write-Host "Not part of a AAD or AD, in a workgroup."
    }
}

# Make sure we have connectivity
$goodToGo = $true
if ($isAD) {
    $dcInfo = [ADSI]"LDAP://RootDSE"
    if ($null -eq $dcInfo.dnsHostName)
    {
        Write-Host "No connectivity to the domain, unable to rename at this point."
        $goodToGo = $false
    }
}

# Good to go, we can rename the computer
if ($goodToGo)
{
    # Remove the scheduled task (if it exists)
    Disable-ScheduledTask -TaskName "RenameComputer" -ErrorAction Ignore
    Unregister-ScheduledTask -TaskName "RenameComputer" -Confirm:$false -ErrorAction Ignore
    Write-Host "Scheduled task unregistered."

    # Get the new computer name: use the asset tag (maximum of 13 characters), or the 
    # serial number if no asset tag is available (replace this logic if you want)
    function SO-Versiof ()
{
    $infoEquip = Get-ComputerInfo
    if (($infoEquip).OSName -like '*Windows 11*')
    {
        $SOversio = "W11"
    }
    else
    {
        $SOversio = "W10"
    }

    return $SOversio
}

    # Obtener el modelo del sistema
    $modelo = (Get-WmiObject -Class Win32_ComputerSystem).Model

    # Verificar si el modelo está en la lista de modelos de portátiles
    $portatiles = @("HP EliteBook 820 G3", "HP EliteBook 840 G3", "HP EliteBook 840 G4", "HP EliteBook 840 G5", "HP ProBook 450 15.6 inch G10 Notebook PC", "HP ProBook 450 15.6 inch G9 Notebook PC", "HP ProBook 450 G7","HP ProBook 450 G8 Notebook PC", "HP ProBook 640 G2")
    $TipoEquipo = ""

    if ($portatiles -contains $modelo) {
    $TipoEquipo = "PT"
}

    # Is the computer name already set?  If so, bail out
    if ($newName -ieq $details.CsName) {
        Write-Host "No need to rename computer, name is already set to $newName"
        Stop-Transcript
        Exit 0
    }
    # Obtener todos los procesos en ejecución
    $procesos = Get-Process -IncludeUserName

    # Buscar el primer proceso cuyo usuario no sea "NT AUTHORITY\SYSTEM"
    foreach ($proceso in $procesos) {
    $usuarioLogeado = $proceso.UserName
    if ($usuarioLogeado -ne "NT AUTHORITY\SYSTEM") {
        # Utilizar una expresión regular para extraer solo el nombre de usuario
        $nombreUsuario = $usuarioLogeado -replace '^.*\\'
        
        Write-Output "Usuario Logeado: $nombreUsuario"
        break  # Salir del bucle cuando se encuentra un usuario distinto a "NT AUTHORITY\SYSTEM"
    }
}



# Function to check if a computer name already exists in the domain
function Test-ComputerName {
    param (
        [string]$computerName
    )

    try {
        $null = [System.Net.Dns]::GetHostAddresses($computerName)
        return $true
    } catch {
        return $false
    }
}

# Set the computer name
Write-Host "Renaming computer to $($hostname)"

$proposedName = (SO-Versiof) + $nombreUsuario + $TipoEquipo

# Function to get a unique computer name
function Get-UniqueComputerName {
    param (
        [string]$proposedName
    )

    $index = 1
    $originalName = $proposedName

    while (Test-ComputerName -computerName $proposedName) {
        $proposedName = $originalName + $index
        $index++
    }

    return $proposedName
}

# If the computer is joined to AD, ensure the proposed name is unique in the domain
if ($isAD) {
    try {
        $newName = Get-UniqueComputerName -proposedName $proposedName
        Rename-Computer -NewName $newName
    } catch {
        Write-Host "Error renaming computer. Attempting to append '1' to the name."
        $newName = Get-UniqueComputerName -proposedName ($proposedName + "1")
        Rename-Computer -NewName $newName
    }
} 

else {
    Rename-Computer -NewName $proposedName
}
}
else
{
    # Check to see if already scheduled
    $existingTask = Get-ScheduledTask -TaskName "RenameComputer" -ErrorAction SilentlyContinue
    if ($existingTask -ne $null)
    {
        Write-Host "Scheduled task already exists."
        Stop-Transcript
        Exit 0
    }

    # Copy myself to a safe place if not already there
    if (-not (Test-Path "$dest\RenameComputer.ps1"))
    {
        Copy-Item $PSCommandPath "$dest\RenameComputer.PS1"
    }

    # Create the scheduled task action
    $action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-NoProfile -ExecutionPolicy bypass -WindowStyle Hidden -File $dest\RenameComputer.ps1"

    # Create the scheduled task trigger
    $timespan = New-Timespan -minutes 5
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -Daily -At 9am
    $triggers += New-ScheduledTaskTrigger -AtLogOn -RandomDelay $timespan
    $triggers += New-ScheduledTaskTrigger -AtStartup -RandomDelay $timespan
    
    # Register the scheduled task
    Register-ScheduledTask -User SYSTEM -Action $action -Trigger $triggers -TaskName "RenameComputer" -Description "RenameComputer" -Force
    Write-Host "Scheduled task created."
}

Stop-Transcript
