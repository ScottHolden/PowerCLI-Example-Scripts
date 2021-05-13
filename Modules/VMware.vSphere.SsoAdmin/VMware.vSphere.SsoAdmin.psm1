# **************************************************************************
#  Copyright 2020 VMware, Inc.
# **************************************************************************

#
# Script module for module 'VMware.vSphere.SsoAdmin'
#
Set-StrictMode -Version Latest

$moduleFileName = 'VMware.vSphere.SsoAdmin.psd1'

# Set up some helper variables to make it easier to work with the module
$PSModule = $ExecutionContext.SessionState.Module
$PSModuleRoot = $PSModule.ModuleBase

# Import the appropriate nested binary module based on the current PowerShell version
$subModuleRoot = $PSModuleRoot

if (($PSVersionTable.Keys -contains "PSEdition") -and ($PSVersionTable.PSEdition -ne 'Desktop')) {
   $subModuleRoot = Join-Path -Path $PSModuleRoot -ChildPath 'netcoreapp3.1'
}
else {
   $subModuleRoot = Join-Path -Path $PSModuleRoot -ChildPath 'net45'
}

$subModulePath = Join-Path -Path $subModuleRoot -ChildPath $moduleFileName
$subModule = Import-Module -Name $subModulePath -PassThru

# When the module is unloaded, remove the nested binary module that was loaded with it
$PSModule.OnRemove = {
   Remove-Module -ModuleInfo $subModule
}

# Internal helper functions
function HasWildcardSymbols {
param(
   [string]
   $stringToVerify
)
   (-not [string]::IsNullOrEmpty($stringToVerify) -and `
    ($stringToVerify -match '\*' -or `
     $stringToVerify -match '\?'))
}

function RemoveWildcardSymbols {
param(
   [string]
   $stringToProcess
)
   if (-not [string]::IsNullOrEmpty($stringToProcess)) {
      $stringToProcess.Replace('*','').Replace('?','')
   } else {
      [string]::Empty
   }
}

function FormatError {
param(
   [System.Exception]
   $exception
)
   if ($exception -ne $null) {
      if ($exception.InnerException -ne $null) {
         $exception = $exception.InnerException
      }

      # result
      $exception.Message
   }

}

# Global variables
$global:DefaultSsoAdminServers = New-Object System.Collections.Generic.List[VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]

# Module Advanced Functions Implementation

#region Connection Management
function Connect-SsoAdminServer {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/29/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function establishes a connection to a vSphere SSO Admin server.

   .PARAMETER Server
   Specifies the IP address or the DNS name of the vSphere server to which you want to connect.

   .PARAMETER User
   Specifies the user name you want to use for authenticating with the server.

   .PARAMETER Password
   Specifies the password you want to use for authenticating with the server.

   .PARAMETER SkipCertificateCheck
   Specifies whether server Tls certificate validation will be skipped

   .EXAMPLE
   Connect-SsoAdminServer -Server my.vc.server -User myAdmin@vsphere.local -Password MyStrongPa$$w0rd

   Connects 'myAdmin@vsphere.local' user to Sso Admin server 'my.vc.server'
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='IP address or the DNS name of the vSphere server')]
   [string]
   $Server,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='User name you want to use for authenticating with the server')]
   [string]
   $User,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Password you want to use for authenticating with the server')]
   [VMware.vSphere.SsoAdmin.Utils.StringToSecureStringArgumentTransformationAttribute()]
   [SecureString]
   $Password,

   [Parameter(
      Mandatory=$false,
      HelpMessage='Skips server Tls certificate validation')]
   [switch]
   $SkipCertificateCheck)

   Process {
      $certificateValidator = $null
      if ($SkipCertificateCheck) {
         $certificateValidator = New-Object 'VMware.vSphere.SsoAdmin.Utils.AcceptAllX509CertificateValidator'
      }

      $ssoAdminServer = $null
      try {
         $ssoAdminServer = New-Object `
            'VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer' `
            -ArgumentList @(
            $Server,
            $User,
            $Password,
            $certificateValidator)
      } catch {
         Write-Error (FormatError $_.Exception)
      }

      if ($ssoAdminServer -ne $null) {
         $existingConnectionIndex = $global:DefaultSsoAdminServers.IndexOf($ssoAdminServer)
         if ($existingConnectionIndex -ge 0) {
            $global:DefaultSsoAdminServers[$existingConnectionIndex].RefCount++
            $ssoAdminServer = $global:DefaultSsoAdminServers[$existingConnectionIndex]
         } else {
            # Update $global:DefaultSsoAdminServers varaible
            $global:DefaultSsoAdminServers.Add($ssoAdminServer) | Out-Null
         }

         # Function Output
         Write-Output $ssoAdminServer
      }
   }
}

function Disconnect-SsoAdminServer {
   <#
   .NOTES
	===========================================================================
	Created on:   	9/29/2020
	Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
	===========================================================================
   .DESCRIPTION
   This function closes the connection to a vSphere SSO Admin server.

   .PARAMETER Server
   Specifies the vSphere SSO Admin systems you want to disconnect from

   .EXAMPLE
   $mySsoAdminConnection = Connect-SsoAdminServer -Server my.vc.server -User ssoAdmin@vsphere.local -Password 'ssoAdminStrongPa$$w0rd'
   Disconnect-SsoAdminServer -Server $mySsoAdminConnection

   Disconnect a SSO Admin connection stored in 'mySsoAdminConnection' varaible
#>
   [CmdletBinding()]
   param(
      [Parameter(
         ValueFromPipeline = $true,
         ValueFromPipelineByPropertyName = $false,
         HelpMessage = 'SsoAdminServer object')]
      [ValidateNotNull()]
      [VMware.vSphere.SsoAdmin.Utils.StringToSsoAdminServerArgumentTransformationAttribute()]
      [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer[]]
      $Server
   )

   Process {
      if (-not $PSBoundParameters['Server']) {
         switch (@($global:DefaultSsoAdminServers).count) {
            { $_ -eq 1 } { $server = ($global:DefaultSsoAdminServers).ToArray()[0] ; break }
            { $_ -gt 1 } {
               Throw 'Connected to more than 1 SSO server, please specify a SSO server via -Server parameter'
               break
            }
            Default {
               Throw 'Not connected to SSO server.'
             }
         }
      }

      foreach ($requestedServer in $Server) {
         if ($requestedServer.IsConnected) {
            $requestedServer.Disconnect()
         }

         if ($global:DefaultSsoAdminServers.Contains($requestedServer) -and $requestedServer.RefCount -eq 0) {
            $global:DefaultSsoAdminServers.Remove($requestedServer) | Out-Null
         }
      }
   }
}
#endregion

#region Person User Management
function New-SsoPersonUser {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/29/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function creates new person user account.

   .PARAMETER UserName
   Specifies the UserName of the requested person user account.

   .PARAMETER Password
   Specifies the Password of the requested person user account.

   .PARAMETER Description
   Specifies the Description of the requested person user account.

   .PARAMETER EmailAddress
   Specifies the EmailAddress of the requested person user account.

   .PARAMETER FirstName
   Specifies the FirstName of the requested person user account.

   .PARAMETER LastName
   Specifies the FirstName of the requested person user account.

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   $ssoAdminConnection = Connect-SsoAdminServer -Server my.vc.server -User ssoAdmin@vsphere.local -Password 'ssoAdminStrongPa$$w0rd'
   New-SsoPersonUser -Server $ssoAdminConnection -User myAdmin -Password 'MyStrongPa$$w0rd'

   Creates person user account with user name 'myAdmin' and password 'MyStrongPa$$w0rd'

   .EXAMPLE
   New-SsoPersonUser -User myAdmin -Password 'MyStrongPa$$w0rd' -EmailAddress 'myAdmin@mydomain.com' -FirstName 'My' -LastName 'Admin'

   Creates person user account with user name 'myAdmin', password 'MyStrongPa$$w0rd', and details against connections available in 'DefaultSsoAdminServers'
#>
[CmdletBinding(ConfirmImpact='Low')]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='User name of the new person user account')]
   [string]
   $UserName,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Password of the new person user account')]
   [string]
   $Password,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Description of the new person user account')]
   [string]
   $Description,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='EmailAddress of the new person user account')]
   [string]
   $EmailAddress,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='FirstName of the new person user account')]
   [string]
   $FirstName,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='LastName of the new person user account')]
   [string]
   $LastName,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   Process {
      $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
      if ($Server -ne $null) {
         $serversToProcess = $Server
      }

      foreach ($connection in $serversToProcess) {
         if (-not $connection.IsConnected) {
            Write-Error "Server $connection is disconnected"
            continue
         }

         # Output is the result of 'CreateLocalUser'
         try {
            $connection.Client.CreateLocalUser(
               $UserName,
               $Password,
               $Description,
               $EmailAddress,
               $FirstName,
               $LastName
            )
         } catch {
            Write-Error (FormatError $_.Exception)
         }
      }
   }
}

function Get-SsoPersonUser {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/29/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function gets person user account.

   .PARAMETER Name
   Specifies Name to filter on when searching for person user accounts.

   .PARAMETER Domain
   Specifies the Domain in which search will be applied, default is 'localos'.


   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   Get-SsoPersonUser -Name admin -Domain vsphere.local

   Gets person user accounts which contain name 'admin' in 'vsphere.local' domain

   .EXAMPLE
   Get-SsoGroup -Name 'Administrators' -Domain 'vsphere.local' | Get-SsoPersonUser

   Gets person user accounts members of 'Administrators' group
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Name filter to be applied when searching for person user accounts')]
   [string]
   $Name,

   [Parameter(
      ParameterSetName = 'ByNameAndDomain',
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Domain name to search in, default is "localos"')]
   [string]
   $Domain = 'localos',

   [Parameter(
      ParameterSetName = 'ByGroup',
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Searches members of the specified group')]
   [VMware.vSphere.SsoAdminClient.DataTypes.Group]
   $Group,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   Process {
      $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
      if ($Server -ne $null) {
         $serversToProcess = $Server
      }

      if ($Name -eq $null) {
         $Name = [string]::Empty
      }

      try {
         foreach ($connection in $serversToProcess) {
            if (-not $connection.IsConnected) {
               Write-Error "Server $connection is disconnected"
               continue
            }

            $personUsers = $null

            if ($Group -ne $null) {
               $personUsers = $connection.Client.GetPersonUsersInGroup(
                  (RemoveWildcardSymbols $Name),
                  $Group)
            } else {
               $personUsers = $connection.Client.GetLocalUsers(
                  (RemoveWildcardSymbols $Name),
                  $Domain)
            }

            if ($personUsers -ne $null) {
               foreach ($personUser in $personUsers) {
                  if ([string]::IsNullOrEmpty($Name) ) {
                     Write-Output $personUser
                  } else {
                     # Apply Name filtering
                     if ((HasWildcardSymbols $Name) -and `
                         $personUser.Name -like $Name) {
                         Write-Output $personUser
                     } elseif ($personUser.Name -eq $Name) {
                        # Exactly equal
                        Write-Output $personUser
                     }
                  }
               }
            }
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}

function Set-SsoPersonUser {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/29/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   Updates person user account.

   .PARAMETER User
   Specifies the PersonUser instance to update.

   .PARAMETER Group
   Specifies the Group you want to add or remove PwersonUser from.

   .PARAMETER Add
   Specifies user will be added to the spcified group.

   .PARAMETER Remove
   Specifies user will be removed from the spcified group.

   .PARAMETER Unlock
   Specifies user will be unloacked.

   .PARAMETER NewPassword
   Specifies new password for the specified user.

   .EXAMPLE
   Set-SsoPersonUser -User $myPersonUser -Group $myExampleGroup -Add -Server $ssoAdminConnection

   Adds $myPersonUser to $myExampleGroup

   .EXAMPLE
   Set-SsoPersonUser -User $myPersonUser -Group $myExampleGroup -Remove -Server $ssoAdminConnection

   Removes $myPersonUser from $myExampleGroup

   .EXAMPLE
   Set-SsoPersonUser -User $myPersonUser -Unlock -Server $ssoAdminConnection

   Unlocks $myPersonUser

   .EXAMPLE
   Set-SsoPersonUser -User $myPersonUser -NewPassword 'MyBrandNewPa$$W0RD' -Server $ssoAdminConnection

   Resets $myPersonUser password
#>
[CmdletBinding(ConfirmImpact='Medium')]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Person User instance you want to update')]
   [VMware.vSphere.SsoAdminClient.DataTypes.PersonUser]
   $User,

   [Parameter(
      ParameterSetName = 'AddToGroup',
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Group instance you want user to be added to or removed from')]
   [Parameter(
      ParameterSetName = 'RemoveFromGroup',
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Group instance you want user to be added to or removed from')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.Group]
   $Group,

   [Parameter(
      ParameterSetName = 'AddToGroup',
      Mandatory=$true)]
   [switch]
   $Add,

   [Parameter(
      ParameterSetName = 'RemoveFromGroup',
      Mandatory=$true)]
   [switch]
   $Remove,

   [Parameter(
      ParameterSetName = 'ResetPassword',
      Mandatory=$true,
      HelpMessage='New password for the specified user.')]
   [ValidateNotNull()]
   [string]
   $NewPassword,

   [Parameter(
      ParameterSetName = 'UnlockUser',
      Mandatory=$true,
      HelpMessage='Specifies to unlock user account.')]
   [switch]
   $Unlock)

   Process {
      try {
         foreach ($u in $User) {
            $ssoAdminClient = $u.GetClient()
            if ((-not $ssoAdminClient)) {
               Write-Error "Object '$u' is from disconnected server"
               continue
            }

            if ($Add) {
               $result = $ssoAdminClient.AddPersonUserToGroup($u, $Group)
               if ($result) {
                  Write-Output $u
               }
            }

            if ($Remove) {
               $result = $ssoAdminClient.RemovePersonUserFromGroup($u, $Group)
               if ($result) {
                  Write-Output $u
               }
            }

            if ($Unlock) {
               $result = $ssoAdminClient.UnlockPersonUser($u)
               if ($result) {
                  Write-Output $u
               }
            }

            if ($NewPassword) {
               $ssoAdminClient.ResetPersonUserPassword($u, $NewPassword)
               Write-Output $u
            }
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}

function Set-SsoSelfPersonUserPassword {
<#
   .NOTES
   ===========================================================================
   Created on:   	2/19/2021
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   Resets connected person user password.


   .PARAMETER NewPassword
   Specifies new password for the connected person user.


   .EXAMPLE
   Set-SsoSelfPersonUserPassword -Password 'MyBrandNewPa$$W0RD' -Server $ssoAdminConnection

   Resets password
#>
[CmdletBinding(ConfirmImpact='High')]
 param(
   [Parameter(
      Mandatory=$true,
      HelpMessage='New password for the connected user.')]
   [ValidateNotNull()]
   [SecureString]
   $Password,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   Process {
      $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
      if ($Server -ne $null) {
         $serversToProcess = $Server
      }

      foreach ($connection in $serversToProcess) {
         if (-not $connection.IsConnected) {
            Write-Error "Server $connection is disconnected"
            continue
         }

         try {
            $connection.Client.ResetSelfPersonUserPassword($Password)
         } catch {
            Write-Error (FormatError $_.Exception)
         }
      }
   }
}

function Remove-SsoPersonUser {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/29/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function removes existing person user account.

   .PARAMETER User
   Specifies the PersonUser instance to remove.

   .EXAMPLE
   $ssoAdminConnection = Connect-SsoAdminServer -Server my.vc.server -User ssoAdmin@vsphere.local -Password 'ssoAdminStrongPa$$w0rd'
   $myNewPersonUser = New-SsoPersonUser -Server $ssoAdminConnection -User myAdmin -Password 'MyStrongPa$$w0rd'
   Remove-SsoPersonUser -User $myNewPersonUser

   Remove person user account with user name 'myAdmin'
#>
[CmdletBinding(ConfirmImpact='High')]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Person User instance you want to remove from specified servers')]
   [VMware.vSphere.SsoAdminClient.DataTypes.PersonUser]
   $User)

   Process {
      try {
         foreach ($u in $User) {
            $ssoAdminClient = $u.GetClient()
            if ((-not $ssoAdminClient)) {
               Write-Error "Object '$u' is from disconnected server"
               continue
            }

            $ssoAdminClient.DeleteLocalUser($u)
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}
#endregion

#region Group cmdlets
function Get-SsoGroup {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/29/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function gets domain groups.

   .PARAMETER Name
   Specifies Name to filter on when searching for groups.

   .PARAMETER Domain
   Specifies the Domain in which search will be applied, default is 'localos'.


   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   Get-SsoGroup -Name administrators -Domain vsphere.local

   Gets 'adminsitrators' group in 'vsphere.local' domain
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Name filter to be applied when searching for group')]
   [string]
   $Name,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Domain name to search in, default is "localos"')]
   [string]
   $Domain = 'localos',

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   Process {
      $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
      if ($Server -ne $null) {
         $serversToProcess = $Server
      }

      if ($Name -eq $null) {
         $Name = [string]::Empty
      }

      try {
         foreach ($connection in $serversToProcess) {
            if (-not $connection.IsConnected) {
               Write-Error "Server $connection is disconnected"
               continue
            }

            foreach ($group in $connection.Client.GetGroups(
               (RemoveWildcardSymbols $Name),
               $Domain)) {


               if ([string]::IsNullOrEmpty($Name) ) {
                  Write-Output $group
               } else {
                  # Apply Name filtering
                  if ((HasWildcardSymbols $Name) -and `
                      $group.Name -like $Name) {
                      Write-Output $group
                  } elseif ($group.Name -eq $Name) {
                     # Exactly equal
                     Write-Output $group
                  }
               }
            }
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}

function Set-SsoGroup {
<#
   .NOTES
   ===========================================================================
   Created on:   	5/13/2020
   Created by:   	Scott Holden
    Twitter:       @ScottDotMS
    Github:        https://github.com/ScottHolden
   ===========================================================================
   .DESCRIPTION
   Updates a group.

   .PARAMETER Group
   Specifies the Group instance to add or remove.

   .PARAMETER ParentGroup
   Specifies the Parent Group you want to add or remove Group from.

   .PARAMETER Add
   Specifies group will be added to the spcified parent group.

   .PARAMETER Remove
   Specifies group will be removed from the spcified parent group.

   .EXAMPLE
   Set-SsoGroup -Group $myExampleGroup -ParentGroup $myParentGroup -Add -Server $ssoAdminConnection

   Adds $myExampleGroup to $myParentGroup

   .EXAMPLE
   Set-SsoGroup -Group $myExampleGroup -ParentGroup $myParentGroup -Remove -Server $ssoAdminConnection

   Removes $myExampleGroup from $myParentGroup
#>
[CmdletBinding(ConfirmImpact='Medium')]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Group instance you want to update')]
   [VMware.vSphere.SsoAdminClient.DataTypes.Group]
   $User,

   [Parameter(
      ParameterSetName = 'AddToGroup',
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Parent Group instance you want Group to be added to or removed from')]
   [Parameter(
      ParameterSetName = 'RemoveFromGroup',
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Parent Group instance you want Group to be added to or removed from')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.Group]
   $Group,

   [Parameter(
      ParameterSetName = 'AddToGroup',
      Mandatory=$true)]
   [switch]
   $Add,

   [Parameter(
      ParameterSetName = 'RemoveFromGroup',
      Mandatory=$true)]
   [switch]
   $Remove,

   Process {
      try {
         foreach ($g in $Group) {
            $ssoAdminClient = $g.GetClient()
            if ((-not $ssoAdminClient)) {
               Write-Error "Object '$g' is from disconnected server"
               continue
            }

            if ($Add) {
               $result = $ssoAdminClient.AddGroupToGroup($g, $Group)
               if ($result) {
                  Write-Output $g
               }
            }

            if ($Remove) {
               $result = $ssoAdminClient.RemoveGroupFromGroup($g, $Group)
               if ($result) {
                  Write-Output $g
               }
            }
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}
#endregion

#region PasswordPolicy cmdlets
function Get-SsoPasswordPolicy {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/30/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function gets password policy.

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   Get-SsoPasswordPolicy

   Gets password policy for the server connections available in $global:defaultSsoAdminServers
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   Process {
      $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
      if ($Server -ne $null) {
         $serversToProcess = $Server
      }
      try {
         foreach ($connection in $serversToProcess) {
            if (-not $connection.IsConnected) {
               Write-Error "Server $connection is disconnected"
               continue
            }

            $connection.Client.GetPasswordPolicy();
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}

function Set-SsoPasswordPolicy {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/30/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function updates password policy settings.

   .PARAMETER PasswordPolicy
   Specifies the PasswordPolicy instance which will be used as original policy. If some properties are not specified they will be updated with the properties from this object.

   .PARAMETER Description

   .PARAMETER ProhibitedPreviousPasswordsCount

   .PARAMETER MinLength

   .PARAMETER MaxLength

   .PARAMETER MaxIdenticalAdjacentCharacters

   .PARAMETER MinNumericCount

   .PARAMETER MinSpecialCharCount

   .PARAMETER MinAlphabeticCount

   .PARAMETER MinUppercaseCount

   .PARAMETER MinLowercaseCount

   .PARAMETER PasswordLifetimeDays

   .EXAMPLE
   Get-SsoPasswordPolicy | Set-SsoPasswordPolicy -MinLength 10 -PasswordLifetimeDays 45

   Updates password policy setting minimum password length to 10 symbols and password lifetime to 45 days
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='PasswordPolicy instance you want to update')]
   [VMware.vSphere.SsoAdminClient.DataTypes.PasswordPolicy]
   $PasswordPolicy,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='PasswordPolicy description')]
   [string]
   $Description,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $ProhibitedPreviousPasswordsCount,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MinLength,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MaxLength,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MaxIdenticalAdjacentCharacters,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MinNumericCount,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MinSpecialCharCount,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MinAlphabeticCount,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MinUppercaseCount,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MinLowercaseCount,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $PasswordLifetimeDays)

   Process {

      try {
         foreach ($pp in $PasswordPolicy) {

            $ssoAdminClient = $pp.GetClient()
            if ((-not $ssoAdminClient)) {
               Write-Error "Object '$pp' is from disconnected server"
               continue
            }

            if ([string]::IsNullOrEmpty($Description)) {
               $Description = $pp.Description
            }

            if ($ProhibitedPreviousPasswordsCount -eq $null) {
               $ProhibitedPreviousPasswordsCount = $pp.ProhibitedPreviousPasswordsCount
            }

            if ($MinLength -eq $null) {
               $MinLength = $pp.MinLength
            }

            if ($MaxLength -eq $null) {
               $MaxLength = $pp.MaxLength
            }

            if ($MaxIdenticalAdjacentCharacters -eq $null) {
               $MaxIdenticalAdjacentCharacters = $pp.MaxIdenticalAdjacentCharacters
            }

            if ($MinNumericCount -eq $null) {
               $MinNumericCount = $pp.MinNumericCount
            }

            if ($MinSpecialCharCount -eq $null) {
               $MinSpecialCharCount = $pp.MinSpecialCharCount
            }

            if ($MinAlphabeticCount -eq $null) {
               $MinAlphabeticCount = $pp.MinAlphabeticCount
            }

            if ($MinUppercaseCount -eq $null) {
               $MinUppercaseCount = $pp.MinUppercaseCount
            }

            if ($MinLowercaseCount -eq $null) {
               $MinLowercaseCount = $pp.MinLowercaseCount
            }

            if ($PasswordLifetimeDays -eq $null) {
               $PasswordLifetimeDays = $pp.PasswordLifetimeDays
            }

            $ssoAdminClient.SetPasswordPolicy(
              $Description,
              $ProhibitedPreviousPasswordsCount,
              $MinLength,
              $MaxLength,
              $MaxIdenticalAdjacentCharacters,
              $MinNumericCount,
              $MinSpecialCharCount,
              $MinAlphabeticCount,
              $MinUppercaseCount,
              $MinLowercaseCount,
              $PasswordLifetimeDays);
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}
#endregion

#region LockoutPolicy cmdlets
function Get-SsoLockoutPolicy {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/30/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function gets lockout policy.

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   Get-SsoLockoutPolicy

   Gets lockout policy for the server connections available in $global:defaultSsoAdminServers
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   Process {
      $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
      if ($Server -ne $null) {
         $serversToProcess = $Server
      }

      try {
         foreach ($connection in $serversToProcess) {
            if (-not $connection.IsConnected) {
               Write-Error "Server $connection is disconnected"
               continue
            }

            $connection.Client.GetLockoutPolicy();
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}

function Set-SsoLockoutPolicy {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/30/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function updates lockout policy settings.

   .PARAMETER LockoutPolicy
   Specifies the LockoutPolicy instance which will be used as original policy. If some properties are not specified they will be updated with the properties from this object.

   .PARAMETER Description

   .PARAMETER AutoUnlockIntervalSec

   .PARAMETER FailedAttemptIntervalSec

   .PARAMETER MaxFailedAttempts

   .EXAMPLE
   Get-SsoLockoutPolicy | Set-SsoLockoutPolicy -AutoUnlockIntervalSec 15 -MaxFailedAttempts 4

   Updates lockout policy auto unlock interval seconds and maximum failed attempts
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='LockoutPolicy instance you want to update')]
   [VMware.vSphere.SsoAdminClient.DataTypes.LockoutPolicy]
   $LockoutPolicy,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='LockoutPolicy description')]
   [string]
   $Description,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int64]]
   $AutoUnlockIntervalSec,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int64]]
   $FailedAttemptIntervalSec,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int32]]
   $MaxFailedAttempts)

   Process {
      try {
         foreach ($lp in $LockoutPolicy) {

            $ssoAdminClient = $lp.GetClient()
            if ((-not $ssoAdminClient)) {
               Write-Error "Object '$lp' is from disconnected server"
               continue
            }

            if ([string]::IsNullOrEmpty($Description)) {
               $Description = $lp.Description
            }

            if ($AutoUnlockIntervalSec -eq $null) {
               $AutoUnlockIntervalSec = $lp.AutoUnlockIntervalSec
            }

            if ($FailedAttemptIntervalSec -eq $null) {
               $FailedAttemptIntervalSec = $lp.FailedAttemptIntervalSec
            }

            if ($MaxFailedAttempts -eq $null) {
               $MaxFailedAttempts = $lp.MaxFailedAttempts
            }

            $ssoAdminClient.SetLockoutPolicy(
              $Description,
              $AutoUnlockIntervalSec,
              $FailedAttemptIntervalSec,
              $MaxFailedAttempts);
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}
#endregion

#region TokenLifetime cmdlets
function Get-SsoTokenLifetime {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/30/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function gets HoK and Bearer Token lifetime settings.

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   Get-SsoTokenLifetime

   Gets HoK and Bearer Token lifetime settings for the server connections available in $global:defaultSsoAdminServers
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   Process {
      $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
      if ($Server -ne $null) {
         $serversToProcess = $Server
      }

      try {
         foreach ($connection in $serversToProcess) {
            if (-not $connection.IsConnected) {
               Write-Error "Server $connection is disconnected"
               continue
            }

            $connection.Client.GetTokenLifetime();
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}

function Set-SsoTokenLifetime {
<#
   .NOTES
   ===========================================================================
   Created on:   	9/30/2020
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function updates HoK or Bearer token lifetime settings.

   .PARAMETER TokenLifetime
   Specifies the TokenLifetime instance to update.

   .PARAMETER MaxHoKTokenLifetime

   .PARAMETER MaxBearerTokenLifetime

   .EXAMPLE
   Get-SsoTokenLifetime | Set-SsoTokenLifetime -MaxHoKTokenLifetime 60

   Updates HoK token lifetime setting
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='TokenLifetime instance you want to update')]
   [VMware.vSphere.SsoAdminClient.DataTypes.TokenLifetime]
   $TokenLifetime,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int64]]
   $MaxHoKTokenLifetime,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [Nullable[System.Int64]]
   $MaxBearerTokenLifetime)

   Process {

      try {
         foreach ($tl in $TokenLifetime) {

            $ssoAdminClient = $tl.GetClient()
            if ((-not $ssoAdminClient)) {
               Write-Error "Object '$tl' is from disconnected server"
               continue
            }

            $ssoAdminClient.SetTokenLifetime(
               $MaxHoKTokenLifetime,
               $MaxBearerTokenLifetime
            );
         }
      } catch {
         Write-Error (FormatError $_.Exception)
      }
   }
}
#endregion

#region IdentitySource
function Add-ExternalDomainIdentitySource {
<#
   .NOTES
   ===========================================================================
   Created on:   	2/11/2021
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function adds Identity Source of ActiveDirectory, OpenLDAP or NIS type.

   .PARAMETER Name
   Name of the identity source

   .PARAMETER DomainName
   Domain name

   .PARAMETER DomainAlias
   Domain alias

   .PARAMETER PrimaryUrl
   Primary Server URL

   .PARAMETER BaseDNUsers
   Base distinguished name for users

   .PARAMETER BaseDNGroups
   Base distinguished name for groups

   .PARAMETER Username
   Domain authentication user name

   .PARAMETER Passowrd
   Domain authentication password

   .PARAMETER DomainServerType
   Type of the ExternalDomain, one of 'ActiveDirectory','OpenLdap','NIS'

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   Add-ExternalDomainIdentitySource `
      -Name 'sof-powercli' `
      -DomainName 'sof-powercli.vmware.com' `
      -DomainAlias 'sof-powercli' `
      -PrimaryUrl 'ldap://sof-powercli.vmware.com:389' `
      -BaseDNUsers 'CN=Users,DC=sof-powercli,DC=vmware,DC=com' `
      -BaseDNGroups 'CN=Users,DC=sof-powercli,DC=vmware,DC=com' `
      -Username 'sofPowercliAdmin' `
      -Password '$up3R$Tr0Pa$$w0rD'

   Adds External Identity Source
#>
[CmdletBinding()]
[Alias("Add-ActiveDirectoryIdentitySource")]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Friendly name of the identity source')]
   [ValidateNotNull()]
   [string]
   $Name,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [ValidateNotNull()]
   [string]
   $DomainName,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [string]
   $DomainAlias,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [ValidateNotNull()]
   [string]
   $PrimaryUrl,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Base distinguished name for users')]
   [ValidateNotNull()]
   [string]
   $BaseDNUsers,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Base distinguished name for groups')]
   [ValidateNotNull()]
   [string]
   $BaseDNGroups,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Domain authentication user name')]
   [ValidateNotNull()]
   [string]
   $Username,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Domain authentication password')]
   [ValidateNotNull()]
   [string]
   $Password,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='External domain server type')]
   [ValidateSet('ActiveDirectory')]
   [string]
   $DomainServerType = 'ActiveDirectory',

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
   if ($Server -ne $null) {
      $serversToProcess = $Server
   }

   try {
      foreach ($connection in $serversToProcess) {
         if (-not $connection.IsConnected) {
            Write-Error "Server $connection is disconnected"
            continue
         }

         $connection.Client.AddActiveDirectoryExternalDomain(
            $DomainName,
            $DomainAlias,
            $Name,
            $PrimaryUrl,
            $BaseDNUsers,
            $BaseDNGroups,
            $Username,
            $Password,
            $DomainServerType);
      }
   } catch {
      Write-Error (FormatError $_.Exception)
   }
}

function Add-LDAPIdentitySource {
<#
   .NOTES
   ===========================================================================
   Created on:   	2/11/2021
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function adds LDAP Identity Source of ActiveDirectory, OpenLDAP or NIS type.

   .PARAMETER Name
   Friendly name of the identity source

   .PARAMETER DomainName
   Domain name

   .PARAMETER DomainAlias
   Domain alias

   .PARAMETER PrimaryUrl
   Primary Server URL

   .PARAMETER SecondaryUrl
   Secondary Server URL

   .PARAMETER BaseDNUsers
   Base distinguished name for users

   .PARAMETER BaseDNGroups
   Base distinguished name for groups

   .PARAMETER Username
   Domain authentication user name

   .PARAMETER Passowrd
   Domain authentication password

   .PARAMETER ServerType
   Type of the ExternalDomain, one of 'ActiveDirectory','OpenLdap','NIS'

   .PARAMETER Certificates
   List of X509Certicate2 LDAP certificates

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   Adds LDAP Identity Source

   .EXAMPLE
   Add-LDAPIdentitySource `
      -Name 'sof-powercli' `
      -DomainName 'sof-powercli.vmware.com' `
      -DomainAlias 'sof-powercli' `
      -PrimaryUrl 'ldap://sof-powercli.vmware.com:389' `
      -BaseDNUsers 'CN=Users,DC=sof-powercli,DC=vmware,DC=com' `
      -BaseDNGroups 'CN=Users,DC=sof-powercli,DC=vmware,DC=com' `
      -Username 'sofPowercliAdmin@sof-powercli.vmware.com' `
      -Password '$up3R$Tr0Pa$$w0rD' `
      -Certificates 'C:\Temp\test.cer'
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Friendly name of the identity source')]
   [ValidateNotNull()]
   [string]
   $Name,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [ValidateNotNull()]
   [string]
   $DomainName,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [string]
   $DomainAlias,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [string]
   $SecondaryUrl,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false)]
   [ValidateNotNull()]
   [string]
   $PrimaryUrl,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Base distinguished name for users')]
   [ValidateNotNull()]
   [string]
   $BaseDNUsers,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Base distinguished name for groups')]
   [ValidateNotNull()]
   [string]
   $BaseDNGroups,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Domain authentication user name')]
   [ValidateNotNull()]
   [string]
   $Username,

   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Domain authentication password')]
   [ValidateNotNull()]
   [string]
   $Password,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Ldap Certificates')]
   [System.Security.Cryptography.X509Certificates.X509Certificate2[]]
   $Certificates,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Ldap Server type')]
   [ValidateSet('ActiveDirectory')]
   [string]
   $ServerType = 'ActiveDirectory',

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
   if ($Server -ne $null) {
      $serversToProcess = $Server
   }

   try {
      foreach ($connection in $serversToProcess) {
         if (-not $connection.IsConnected) {
            Write-Error "Server $connection is disconnected"
            continue
         }

         $connection.Client.AddLdapIdentitySource(
            $DomainName,
            $DomainAlias,
            $Name,
            $PrimaryUrl,
            $SecondaryUrl,
            $BaseDNUsers,
            $BaseDNGroups,
            $Username,
            $Password,
            $ServerType,
            $Certificates);
      }
   } catch {
      Write-Error (FormatError $_.Exception)
   }
}

function Set-LDAPIdentitySource {
<#
   .NOTES
   ===========================================================================
   Created on:   	2/17/2021
   Created by:   	Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function adds LDAP Identity Source of ActiveDirectory, OpenLDAP or NIS type.

   .PARAMETER IdentitySource
   Identity Source to update

   .PARAMETER Certificates
   List of X509Certicate2 LDAP certificates

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   Updates LDAP Identity Source

   .EXAMPLE

   Updates certificate of a LDAP identity source

   Get-IdentitySource -External | `
   Set-LDAPIdentitySource `
      -Certificates 'C:\Temp\test.cer'
#>
[CmdletBinding()]
 param(
   [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Identity source to update')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.ActiveDirectoryIdentitySource]
   $IdentitySource,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Ldap Certificates')]
   [System.Security.Cryptography.X509Certificates.X509Certificate2[]]
   $Certificates,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

Process {
   $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
   if ($Server -ne $null) {
      $serversToProcess = $Server
   }

   try {
      foreach ($connection in $serversToProcess) {
         if (-not $connection.IsConnected) {
            Write-Error "Server $connection is disconnected"
            continue
         }

         $connection.Client.UpdateLdapIdentitySource(
            $IdentitySource.Name,
            $IdentitySource.FriendlyName,
            $IdentitySource.PrimaryUrl,
            $IdentitySource.FailoverUrl,
            $IdentitySource.UserBaseDN,
            $IdentitySource.GroupBaseDN,
            $Certificates);
      }
   } catch {
      Write-Error (FormatError $_.Exception)
   }
}
}

function Get-IdentitySource {
<#
   .NOTES
   ===========================================================================
   Created on:   11/26/2020
   Created by:   Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function gets Identity Source.

   .PARAMETER Localos
   Filter parameter to return only the localos domain identity source

   .PARAMETER System
   Filter parameter to return only the system domain identity source

   .PARAMETER External
   Filter parameter to return only the external domain identity sources

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   Get-IdentitySource -External

   Gets all external domain identity source
#>
[CmdletBinding()]
 param(

  [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Returns only the localos domain identity source')]
   [Switch]
   $Localos,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Returns only the system domain identity source')]
   [Switch]
   $System,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Returns only the external domain identity sources')]
   [Switch]
   $External,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

   $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
   if ($Server -ne $null) {
      $serversToProcess = $Server
   }
   foreach ($connection in $serversToProcess) {
      if (-not $connection.IsConnected) {
         Write-Error "Server $connection is disconnected"
         continue
      }

      $resultIdentitySources = @()
      $allIdentitySources = $connection.Client.GetDomains()

      if (-not $Localos -and -not $System -and -not $External) {
         $resultIdentitySources = $allIdentitySources
      }

      if ($Localos) {
         $resultIdentitySources += $allIdentitySources | Where-Object { $_ -is [VMware.vSphere.SsoAdminClient.DataTypes.LocalOSIdentitySource] }
      }

      if ($System) {
         $resultIdentitySources += $allIdentitySources | Where-Object { $_ -is [VMware.vSphere.SsoAdminClient.DataTypes.SystemIdentitySource] }
      }

      if ($External) {
         $resultIdentitySources += $allIdentitySources | Where-Object { $_ -is [VMware.vSphere.SsoAdminClient.DataTypes.ActiveDirectoryIdentitySource] }
      }

      #Return result
      $resultIdentitySources
   }
}

function Remove-IdentitySource {
<#
   .NOTES
   ===========================================================================
   Created on:   03/19/2021
   Created by:   Dimitar Milov
    Twitter:       @dimitar_milov
    Github:        https://github.com/dmilov
   ===========================================================================
   .DESCRIPTION
   This function removes Identity Source.

   .PARAMETER IdentitySource
   The identity source to remove

   .PARAMETER Server
   Specifies the vSphere Sso Admin Server on which you want to run the cmdlet.
   If not specified the servers available in $global:DefaultSsoAdminServers variable will be used.

   .EXAMPLE
   Get-IdentitySource -External | Remove-IdentitySource

   Removes all external domain identity source
#>
[CmdletBinding()]
 param(

  [Parameter(
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Identity source to remove')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.IdentitySource]
   $IdentitySource,

   [Parameter(
      Mandatory=$false,
      ValueFromPipeline=$false,
      ValueFromPipelineByPropertyName=$false,
      HelpMessage='Connected SsoAdminServer object')]
   [ValidateNotNull()]
   [VMware.vSphere.SsoAdminClient.DataTypes.SsoAdminServer]
   $Server)

Process {

   $serversToProcess = $global:DefaultSsoAdminServers.ToArray()
   if ($Server -ne $null) {
      $serversToProcess = $Server
   }


   try {
      foreach ($connection in $serversToProcess) {
         if (-not $connection.IsConnected) {
            Write-Error "Server $connection is disconnected"
            continue
         }

         $connection.Client.DeleteDomain($IdentitySource.Name)
      }
   } catch {
      Write-Error (FormatError $_.Exception)
   }
}
}
#endregion