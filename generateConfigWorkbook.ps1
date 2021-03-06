﻿# generate configWorkbook
# Steps:
# - Connect to VIserver
# - Execute Script
# Note: Make sure Hashtable.csv is on the same directory

function ReturnNIC-FWDriver ($VMHost)
{
    $report = @()
    $vmnics = $VMHost | Get-VMHostNetworkAdapter | where {$_.Name -like 'vmnic*'}
    $esxcli = $VMHost | Get-esxCli -v2
    foreach ($vmnic in $vmnics)
    {
        
        $info = $esxcli.network.nic.get.Invoke(@{nicname = $vmnic.Name})
        $data = "" | Select VMHost, VMNic, Driver, DriverVersion, FirmwareVersion
        $data.VMHost = $VMhost.Name
        $data.VMNic = $vmnic.Name
        $data.Driver = $info.DriverInfo.Driver
        $data.DriverVersion = $info.DriverInfo.Version
        $data.FirmwareVersion = $info.DriverInfo.FirmwareVersion
        $report += $data
    }
    return $report
}

function ReturnLocalDatastoreSize ($VMhost)
{
    $dsLocal = $VMHost | Get-Datastore | get-view | where {$_.Summary.MultipleHostAccess -eq $false}
    if ($dsLocal -eq $null)
    {
        return 0        
    }
    elseif ($dsLocal -is [array])
    {
        # multiple local Drive, return first one
        return $dsLocal[0].Summary.Capacity/1GB
    }
    else
    {
        return $dsLocal.Summary.Capacity/1GB
    }    
}

function ReturnHWPackage ($VMHost)
{
    return $VMHost | get-view | Select $_.Hardware
}

function ReturnVMK ($VMHost)
{
    return ($VMHost | Get-VMHostNetworkAdapter | where {$_.DeviceName -like "vmk*"})
}

$objList = @()

# build-up the Column Names
# iterate per each row property using
# $text2[5].Host1 = "RAID 10"

$report = @()
$report = import-csv $PSScriptRoot\hashTable.csv

#import as HashTable for easy key-value pair in the array
$hash = $report | Group-Object -AsHashTable -Property Hostname

#build-up per item

foreach ($VMHost in Get-VMHost)
{
    write-host "Executing for: $([string] $VMHost.Name) ..."
    
    #$obj = New-Object psobject
    $report | Add-Member -name $VMhost.Name -type NoteProperty -Value $null
    $report[($hash["Manufacturer"].ID)].$([string] $VMHost.Name) = $VMHost.Manufacturer
    $report[($hash["Model"].ID)].$([string] $VMHost.Name) = $VMHost.Model
    $report[($hash["Total Storage (GB)"].ID)].$([string] $VMHost.Name) = ReturnLocalDatastoreSize -VMhost $VMHost
    $report[($hash["Local Storage Present"].ID)].$([string] $VMHost.Name) = if ($report[($hash["Total Storage (GB)"].ID)].$([string] $VMHost.Name) -eq 0) {"No"} else {"Yes"}
    $report[($hash["Local Storage Type"].ID)].$([string] $VMHost.Name) = ""
    $report[($hash["RAID"].ID)].$([string] $VMHost.Name) = ""
    
    # Start Hardware : CPU/ Mem/ Nic
    $report[($hash["Total RAM (GB)"].ID)].$([string] $VMHost.Name) = [math]::Round($VMHost.MemoryTotalGB)
    $hwInfo = ReturnHWPackage -VMHost $VMHost
    $report[($hash["CPU Model"].ID)].$([string] $VMHost.Name) = $hwInfo.Hardware.CpuPkg[0].Description.Split('@')[0]
    $report[($hash["CPU Speed (Ghz)"].ID)].$([string] $VMHost.Name) = $hwInfo.Hardware.CpuPkg[0].Description.Split('@')[1].trim()
    $report[($hash["Processor Sockets"].ID)].$([string] $VMHost.Name) = $hwInfo.Hardware.CpuPkg.Count
    $report[($hash["Processor Cores Per Socket"].ID)].$([string] $VMHost.Name) = $hwInfo.Hardware.CpuInfo.NumCpuCores

    # ESXi Specifics
    $report[($hash["ESXi Build"].ID)].$([string] $VMHost.Name) = $VMHost.Build
    $report[($hash["ESXi Version"].ID)].$([string] $VMHost.Name) = $VMHost.Version
    $report[($hash["Host Cluster"].ID)].$([string] $VMHost.Name) = ($VMHost | Get-Cluster).Name
    $report[($hash["Hostname"].ID)].$([string] $VMHost.Name) = $VMHost.Name
    $vmkNICs = ReturnVMK -VMHost $VMHost
    $report[($hash["Management Network Adapter"].ID)].$([string] $VMHost.Name) = ($vmkNICs | where {$_.ManagementTrafficEnabled}).Name
    $pgName = ($vmkNICs | where {$_.ManagementTrafficEnabled}).PortGroupName
    $report[($hash["VLAN ID"].ID)].$([string] $VMHost.Name) = (Get-VirtualPortGroup -Name $pgName -VMHost $VMHost).VlanId
    $report[($hash["IPv4 Mode"].ID)].$([string] $VMHost.Name) = if (($vmkNICs | where {$_.ManagementTrafficEnabled}).DhcpEnabled){"DHCP"}else{"Static"}
    $report[($hash["IPv4 Address"].ID)].$([string] $VMHost.Name) = ($vmkNICs | where {$_.ManagementTrafficEnabled}).IP
    $report[($hash["IPv4 Subnet Mask"].ID)].$([string] $VMHost.Name) = ($vmks | where {$_.ManagementTrafficEnabled}).SubnetMask


    $VMHostNetwork = $VMHost | get-vmhostnetwork
    $report[($hash["IPv4 Default Gateway"].ID)].$([string] $VMHost.Name) = $VMHostNetwork.VMkernelGateway
    
    # Start DNS Stuff 
    $report[($hash["Primary DNS Server"].ID)].$([string] $VMHost.Name) = $VMHostNetwork.DnsAddress[0]
    $report[($hash["Secondary DNS Server"].ID)].$([string] $VMHost.Name) = $VMHostNetwork.DnsAddress[1]
    $report[($hash["Custom DNS Suffixes"].ID)].$([string] $VMHost.Name) = $VMHostNetwork.SearchDomain[0]

    # Start VMotion Items
    $report[($hash["Used?"].ID)].$([string] $VMHost.Name) = if ($vmkNIcs | where {$_.VMotionEnabled}){"Yes"}else{"No"}
    $report[($hash["Use DHCP"].ID)].$([string] $VMHost.Name) = if (($vmkNICs | where {$_.VMotionEnabled}).DhcpEnabled){"DHCP"}else{"Static"}
    $pgName = ($vmkNICs | where {$_.VMotionEnabled}).PortGroupName
    $report[($hash["vmVLAN ID"].ID)].$([string] $VMHost.Name) = (Get-VirtualPortGroup -Name $pgName -VMHost $VMHost).VlanId
    $report[($hash["vmIPv4 Address"].ID)].$([string] $VMHost.Name) = ($vmkNIcs | where {$_.VMotionEnabled}).IP
    $report[($hash["vmSubnet Mask"].ID)].$([string] $VMHost.Name) = ($vmkNIcs | where {$_.VMotionEnabled}).SubnetMask
	$report[($hash["vmSwitch Name"].ID)].$([string] $VMHost.Name) = (($vmkNIcs | where {$_.VMotionEnabled}) | Get-VirtualSwitch).Name
	$report[($hash["vmvmnic(s)"].ID)].$([string] $VMHost.Name) = ""
    $report[($hash["vmPortgroup"].ID)].$([string] $VMHost.Name) = ""	
    $report[($hash["TCP/IP Stack"].ID)].$([string] $VMHost.Name) = ""	
    $report[($hash["Swap file location"].ID)].$([string] $VMHost.Name) = $VMHost.VMSwapfilePolicy
    $report[($hash["Default VM Compatibility"].ID)].$([string] $VMHost.Name) = ""
    
    # Start NTP Items
    $report[($hash["Time Configuration"].ID)].$([string] $VMHost.Name) = ""
    $report[($hash["NTP Service Start Up Policy"].ID)].$([string] $VMHost.Name) = ($VMHost | get-vmhostService | where {$_.Key -eq "ntpd"}).Policy
    $report[($hash["NTP Servers"].ID)].$([string] $VMHost.Name) = $VMHost | Get-VMHostNTpserver

    # Domain
    $domain = $VMHost | Get-VMHostAuthentication
    if ($domain.Domain -eq $null)
    {
        $report[($hash["Domain"].ID)].$([string] $VMHost.Name) = ""
    }
    else
    {
        $report[($hash["Domain"].ID)].$([string] $VMHost.Name) = $domain.Domain
    }

    #Host Profile
    
    $report[($hash["Host Profile"].ID)].$([string] $VMHost.Name) = ($VMHost | Get-VMHostProfile).Name
        
}

$report | export-csv D:\installers\SCB-DR.csv -NoTypeInformation

