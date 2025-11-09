
<#PSScriptInfo

.VERSION 1.0

.GUID a606fc36-8215-4bec-9f1c-f28bc63ad843

.AUTHOR timmcmic

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>
    #Requires -Module @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.28.0' } 
    #Requires -Module @{ ModuleName = 'Microsoft.Graph.Identity.DirectoryManagement'; ModuleVersion = '2.28.0' }
<# 

.DESCRIPTION 
 This script allows administrators to manage M365 domains. 

#> 
Param(
    #Define General Paramters
    [Parameter(Mandatory=$true)]
    [string]$logFolderPath,
    [Parameter(Mandatory=$false)]
    [string]$domainName="",
    [Parameter(Mandatory=$false)]
    [string]$customDNSServer="",
    #Define Microsoft Graph Parameters
    [Parameter(Mandatory = $false)]
    [ValidateSet("","China","Global","USGov","USGovDod")]
    [string]$msGraphEnvironmentName="",
    [Parameter(Mandatory=$false)]
    [string]$msGraphTenantID="",
    [Parameter(Mandatory=$false)]
    [string]$msGraphCertificateThumbprint="",
    [Parameter(Mandatory=$false)]
    [string]$msGraphApplicationID="",
    [Parameter(Mandatory=$false)]
    [string]$msGraphClientSecret="",
    [Parameter(Mandatory=$false)]
    [string]$msGraphUseBeta=$true,
     [Parameter(Mandatory = $false)]
    [ValidateSet("","Add","Remove","Verify","Force","DNSVerification","DNSPublic","DNSRecords","Viral")]
    [string]$adminOperation=""
)


#*****************************************************

Function new-LogFile
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$logFileName,
        [Parameter(Mandatory = $true)]
        [string]$logFolderPath
    )

    [string]$logFileSuffix=".log"
    [string]$fileName=$logFileName+$logFileSuffix

    # Get our log file path

    $logFolderPath = $logFolderPath+"\"+$logFileName+"\"
    
    #Since $logFile is defined in the calling function - this sets the log file name for the entire script
    
    $global:LogFile = Join-path $logFolderPath $fileName

    #Test the path to see if this exists if not create.

    [boolean]$pathExists = Test-Path -Path $logFolderPath

    if ($pathExists -eq $false)
    {
        try 
        {
            #Path did not exist - Creating

            New-Item -Path $logFolderPath -Type Directory
        }
        catch 
        {
            throw $_
        } 
    }
}

#*****************************************************
Function Out-LogFile
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $String,
        [Parameter(Mandatory = $false)]
        [boolean]$isError=$FALSE
    )

    # Get the current date

    [string]$date = Get-Date -Format G

    # Build output string
    #In this case since I abuse the function to write data to screen and record it in log file
    #If the input is not a string type do not time it just throw it to the log.

    if ($string.gettype().name -eq "String")
    {
        [string]$logstring = ( "[" + $date + "] - " + $string)
    }
    else 
    {
        $logString = $String
    }

    # Write everything to our log file and the screen

    $logstring | Out-File -FilePath $global:LogFile -Append

    #Write to the screen the information passed to the log.

    if ($string.gettype().name -eq "String")
    {
        Write-Host $logString
    }
    else 
    {
        write-host $logString | select-object -expandProperty *
    }

    #If the output to the log is terminating exception - throw the same string.

    if ($isError -eq $TRUE)
    {
        #Ok - so here's the deal.
        #By default error action is continue.  IN all my function calls I use STOP for the most part.
        #In this case if we hit this error code - one of two things happen.
        #If the call is from another function that is not in a do while - the error is logged and we continue with exiting.
        #If the call is from a function in a do while - write-error rethrows the exception.  The exception is caught by the caller where a retry occurs.
        #This is how we end up logging an error then looping back around.

        if ($global:GraphConnection -eq $TRUE)
        {
            Disconnect-MGGraph
        }

        write-error $logString

        exit
    }
}

#*****************************************************
Function WriteXMLFile
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $outputFile,
        [Parameter(Mandatory = $true)]
        $data
    )

    out-logfile -string "Entering WriteXMLFile"

    try
    {
        out-logfile -string "Writing outout to xml file."

        $data | export-cliXML -path $outputFile -errorAction STOP
    }
    catch
    {
        out-logfile -string $_
        out-logfile -string "Unable to write data to XML file." -isError:$TRUE
    }
}

#*****************************************************
Function WriteJsonFile
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $outputFile,
        [Parameter(Mandatory = $true)]
        $data
    )

    out-logfile -string "Entering WriteJsonFile"

    $functionData = $data | ConvertTo-Json

    try
    {
        out-logfile -string "Writing outout to json file."

        $functionData | out-file -FilePath $outputFile -errorAction STOP
    }
    catch
    {
        out-logfile -string $_
        out-logfile -string "Unable to write data to JSON file." -isError:$TRUE
    }
}

#*****************************************************
Function CheckGraphEnvironment
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $msGraphEnvironmentName
    )

    out-logfile -string "Entering CheckGraphEnvironment"

    if ($msGraphEnvironmentName -eq "")
    {
        out-logfile -string "A graph envirnoment was not supplied."

        write-host "Select the grpah environment for your tenant:"
        write-host "1:  Global"
        write-host "2:  USGov"
        write-host "3:  USDoD"
        write-host "4:  China"

        $selection = read-host "Please make a environment selection: "

        out-logfile -string ("Graph environment selected = "+$selection)

        switch($selection)
        {
            '1' {
                $msGraphEnvironmentName = $global:global
            } '2' {
                $msGraphEnvironmentName = $global:usGov
            } '3' {
                $msGraphEnvironmentName = $global:usDOD
            } '4' {
                $msGraphEnvironmentName = $global:China
            } default {
                out-logfile -string "Invalid environment selection made." -isError:$TRUE
            }
        }

        out-logfile -string ("MSGraphEnvironmentName: "+$msGraphEnvironmentName)
    }
    else
    {
        out-logfile -string "Returning the supplied msgraph environment."
    }

    return $msGraphEnvironmentName
}

#*****************************************************
Function CheckGraphTenantID
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $msGraphTenantID
    )

    out-logfile -string "Entering CheckGraphTenantID"

    if ($msGraphTenantID -eq "")
    {
        $msGraphTenantID = read-host "Provied an Entra / Graph TenantID: "

        out-logfile -string ("MSGraphTenantID: "+$msGraphTenantID)
    }
    else
    {
        out-logfile -string "Returning the supplied msgraph tenant id."
    }

    return $msGraphTenantID
}

#*****************************************************
Function CheckGraphURL
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $msGraphEnvironmentName
    )

    $msGraphURL = ""

    out-logfile -string "Entering CheckGraphURL"

    if ($msGraphEnvironmentName -eq $global:global)
    {
        $msGraphURL = $global:msGraphURLGlobal
    }
    elseif ($msGraphEnvironmentName -eq $global:usGov)
    {
        $msGraphURL = $global:msGraphURLUSGov
    }
    elseif ($msGraphEnvironmentName -eq $global:usDOD)
    {
        $msGraphURL = $global:msGraphURLUSDoD
    }
    elseif ($msGraphEnvironmentName -eq $global:China)
    {
        $msGraphURL = $global:msGraphURLChina
    }

    out-logfile -string ("MSGraphURL: "+$msGraphURL)

    return $msGraphURL
}

#*****************************************************
Function CheckMSGraph
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $msGraphApplicationID,
        [Parameter(Mandatory = $true)]
        $msGraphCertificateThumbprint,
        [Parameter(Mandatory = $true)]
        $msGraphClientSecret
    )

    $applicationAuthType = ""
    $appIdProvied = $false
    $certificateProvided = $false
    $clientSecreteProvied = $false
    $interactiveAuth = "InteractiveAuth"
    $certificateAuth = "CertificateAuth"
    $clientSecretAuth = "ClientSecret"

    out-logfile -string "Entering CheckMSGraph"

    out-logfile -string "Determine if an MSGraphApplicationID was specified..."

    if ($msGraphApplicationID -ne "")
    {
        out-logfile -string "MSGraphApplicationID Provided."

        $appIdProvied = $TRUE
    }
    else
    {
        out-logfile -string "MSGraphApplicationID Not Provided"
    }

    out-logfile -string "Determine if MSGraphCertificateThumbprint was specified..."

    if ($msGraphCertificateThumbprint -ne "")
    {
        out-logfile -string "MSGraphCertificateThumbprint Provided"
        $certificateProvided = $TRUE
    }
    else
    {
        out-logfile -string "MSGraphCertificateThumbprint Not Provided"
        
    }

    out-logfile -string "Determine if MSGraphClientSecret was specified..."

    if ($msGraphClientSecret -ne "")
    {
        out-logfile -string "MSGraphClientSecret Provided"
        $clientSecreteProvied = $TRUE
    }
    else
    {
        out-logfile -string "MSGraphClientSecret Not Provided"
    }

    out-logfile -string "Determine the authentication method."

    if ($appIdProvied -eq $FALSE -and (($certificateProvided -eq $TRUE) -or ($clientSecreteProvied -eq $TRUE)))
    {
        out-logfile -string "A msGraphApplicationID is required anytime msGraphCertificateThumbprint or msGraphClientSecret are specified." -isError:$TRUE
    }
    else
    {
        out-logfile -string "Not missing msGraphApplicationID."
    }

    if ($appIDProvied -eq $TRUE -and (($certificateProvided -eq $FALSE) -and ($clientSecreteProvied -eq $FALSE)))
    {
        out-logfile -string "An msGraphCertificateThumbPrint or msGraphClientSecret is required anytime msGraphApplicationID is specified." -isError:$TRUE
    }
    else
    {
        out-logfile -string "Not missing msGraphCertificateThumbprint or msGraphClientSecret with msGraphApplicationID."
    }

    if ($appIDProvied -eq $TRUE -and (($certificateProvided -eq $TRUE) -and ($clientSecreteProvied -eq $TRUE)))
    {
        out-logfile -string "Specify either an msGraphCertificateThumbPrint or msGraphClientSecret only when msGraphApplicationID is specified." -isError:$TRUE
    }
    else
    {
        out-logfile -string "Not specifying both msGraphCertificateThumbprint and msGraphClientSecret with msGraphApplicationID."
    }

    if (($appIdProvied -eq $TRUE) -and ($certificateProvided -eq $TRUE))
    {
        out-logfile -string "Certificate authentication type utilized."
        $applicationAuthType = $certificateAuth
    }
    elseif (($appIDProvied -eq $TRUE) -and ($clientSecreteProvied -eq $TRUE))
    {
        out-logfile -string "Client Secret authentication type utilized."
        $applicationAuthType = $clientSecretAuth
    }
    else
    {
        out-logfile -string "Interactive authentication type specified."
        $applicationAuthType = $interactiveAuth
    }

    out-logfile -string ("MSGraphAuthType: "+$applicationAuthType)

    return $applicationAuthType
}

#*****************************************************
Function ConnectMSGraph
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $msGraphAuthType,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        $msGraphApplicationID,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        $msGraphCertificateThumbPrint,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        $msGraphClientSecret,
        [Parameter(Mandatory = $true)]
        $msGraphEnvironmentName,
        [Parameter(Mandatory = $true)]
        $msGraphTenantID,
        [Parameter(Mandatory = $true)]
        $msGraphStaticScope
    )

    $interactiveAuth = "InteractiveAuth"
    $certificateAuth = "CertificateAuth"
    $clientSecretAuth = "ClientSecret"

    out-logfile -string "Entering ConnectMSGraph"

    if ($msGraphAuthType -eq $interactiveAuth)
    {
        out-logfile -string "Connect to msgraph using interactive authentication."

        try
        {
            connect-MGGraph -environment $msGraphEnvironmentName -tenant $msGraphTenantID -scopes $msGraphStaticScope -errorAction STOP

            out-logfile -string "Graph connection successful."
        }
        catch
        {
            out-logfile -string $_
            out-logfile -string "Error connecting to Microsoft Graph." -isError:$true
        }
    }
    elseif ($msGraphAuthType -eq $certificateAuth)
    {
        out-logfile -string "Connect to msgraph using certificate authentication."

        try
        {
            connect-MGGraph -environment $msGraphEnvironmentName -tenant $msGraphTenantID -clientID $msGraphApplicationID -certificateThumbprint $msGraphCertificateThumbprint -errorAction STOP

            out-logfile -string "Graph connection successful."
        }
        catch
        {
            out-logfile -string $_
            out-logfile -string "Error connecting to Microsoft Graph."
        }
    }
    elseif ($msGraphAuthType -eq $clientSecretAuth)
    {
        out-logfile -string "Connect to msgraph using certificate authentication."

        try
        {
            connect-MGGraph -environment $msGraphEnvironmentName -tenant $msGraphTenantID -clientID $msGraphApplicationID -clientSecretCredential $msGraphClientSecret -errorAction STOP

            out-logfile -string "Graph connection successful."
        }
        catch
        {
            out-logfile -string $_
            out-logfile -string "Error connecting to Microsoft Graph."
        }
    }

    $global:GraphConnection = $TRUE
}

#*****************************************************
Function WriteMGContext
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $outputFile
    )

    out-logfile -string "Enter WriteMGContext"

    $mgContext = $NULL

    try
    {
        $mgContext = get-MGContext -errorAction STOP
    }
    catch
    {
        out-logfile -string $_
        out-logfile -string "Unable to run get-MGContext." -isError:$TRUE
    }

    WriteXMLFile -outputFile $outputFile -data $mgContext
}

#*****************************************************
Function CheckDomainName
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $domainName
    )

    out-logfile -string "Enter CheckDomainName"

    if ($domainName -eq "")
    {
        out-logfile -string "Domain name not specified - obtaining."

        $domainName = read-host "Please enter a domain name to add or takeover"

        out-logfile -string ("Domain name to process: "+$domainName)
    }
    else
    {
        out-logfile -string "Domain name specified."
        out-logfile -string ("Domain name to process: "+$domainName)
    }

    return $domainName
}

#*****************************************************
Function TestDomainName
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $domainName,
        [Parameter(Mandatory = $true)]
        $outputFile
    )

    out-logfile -string "Enter TestDomainName"

    $functionDomain = $NULL
    $selection = $NULL

    try
    {
        $functionDomain = get-MGDomain -domainID $domainName -errorAction STOP
    }
    catch
    {
        out-logfile -string $_
        out-logfile -string ("Specified Domain "+$domainName+" is not added to the specified tenant.")
        
        $selection = Read-Host "Add domain to tenant to proceed? Y/N"

        switch ($selection)
        {
            'Y' {
                try
                {
                    out-logfile -string "Attempting to add the domain."
                    $functionDomain = new-MGDomain -id $domainName -errorAction STOP    
                    $functionDomainAdded = $true
                }
                catch
                {
                    out-logfile -string $_
                    out-logfile -string "Unable to add the domain as a part of the force takover process - exit." -isError:$TRUE
                }
            } 'N' {
                out-logfile -string "Please add the domain manually with new-MGDomain prior to proceeding with force takeover or add operation." -isError:$TRUE
            } default {
                out-logfile -string "Invalid environment selection made." -isError:$TRUE
            }
        }
    }

    WriteXMLFile -outputFile $outputFile -data $functionDomain
}

#*****************************************************
Function GetM365DNSRecords
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $domainName,
        [Parameter(Mandatory = $true)]
        $outputFile
    )

    out-logfile -string "Enter GetM365DNSRecords"

    $functionDNSRecords
    $functionObject
    [array]$functionDNSRecordsReturn=@()

    try
    {
        $functionDNSRecords = Get-MgDomainVerificationDnsRecord -DomainID $domainName -errorAction STOP
    }
    catch
    {
        out-logfile -string $_
        out-logfile -string "Unable to obtain M365 DNS Verification Records." -isError:$TRUE
    }

    WriteXMLFile -data $functionDNSRecords -outputFile $outputFile

    out-logfile -string "Creating custom objects of DNS entries for return."

    foreach ($entry in $functionDNSRecords)
    {
        if ($entry.recordType -eq $global:dnsTypeText)
        {
            $functionObject = New-Object PSObject -Property @{
                RecordType = $entry.recordType
                Value = $entry.AdditionalProperties.text
            }
        }
        elseif ($entry.recordType -eq $global:dnsTypeMX)
        {
           $functionObject = New-Object PSObject -Property @{
                RecordType = $entry.recordType
                Value = $entry.AdditionalProperties.mailExchange
            }
        }

        $functionDNSRecordsReturn += $functionObject
    }

    out-logfile -string $functionDNSRecordsReturn

    return $functionDNSRecordsReturn
}

#*****************************************************
Function TestDNSRecords
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $domainName,
        [Parameter(Mandatory = $true)]
        $txt,
        [Parameter(Mandatory = $true)]
        $mx,
        [Parameter(Mandatory = $true)]
        $m365DNS
    )

    $functionM365TXT = ""
    $functionM365MX = ""
    $functionTXTPresent = $FALSE
    $functionMXPresent = $false
    $functionverificationPresent = $FALSE

    out-logfile -string "Enter TestDNSRecords"

    foreach ($entry in $m365DNS)
    {
        if ($entry.RecordType -eq $global:dnsTypeText)
        {
            out-logfile -string $entry.Value
            $functionM365Txt = $entry.value
        }
        elseif ($entry.recordType -eq $global:dnsTypeMX)
        {
            out-logfile -string $entry.Value
            $functionM365MX = $entry.Value
        }
    }

    out-logfile -string ("M365 TXT Record: "+$functionM365Txt)
    out-logfile -string ("M365 MX Record: "+$functionM365mx)

    out-logfile -string "Testing public DNS records."

    foreach ($entry in $txt)
    {
        if ($entry.value -eq $functionM365Txt)
        {
            out-logfile -string "TXT record found in public dns."
            $functionTXTPresent = $TRUE
        }
        else 
        {
            out-logfile -string "TXT record not found in public dns."
        }
    }

    foreach ($entry in $mx)
    {
        if ($entry.value -eq $functionM365MX)
        {
            out-logfile -string "MX record found in public dns."
            $functionMXPresent = $TRUE
        }
        else 
        {
            out-logfile -string "MX record not found in public dns."
        }
    }

    if (($functionMXPresent -eq $TRUE) -or ($functionTXTPresent -eq $TRUE))
    {
        out-logfile -string "A minimum of one verification method was located for the domain - proceed."
    }
    else 
    {
       
        out-logfile -string ("`n `n Either TXT Record [Most Common]: "+$functionM365TXT + " or MX Record: "+$functionM365MX+" must be present in public dns.  `n If the domain was recently added please add either of this records to proceed. `n `n") -isError:$TRUE
    }
}

#*****************************************************
Function GetPublicDNS
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $domainName,
        [Parameter(Mandatory = $true)]
        $dnsType,
        [Parameter(Mandatory = $true)]
        $outputFile,
        [Parameter(Mandatory = $true)]
        $customDNSServer
    )

    out-logfile -string "Enter GetPublicDNS"

    [array]$functionDNSRecords=@()
    [array]$functionDNSRecordsReturn =@()

    if ($customDNSServer -eq "")
    {
        out-logfile -string "Using DNS resolvers set on local interface."

        try
        {
            $functionDNSRecords += Resolve-DNSName -name $domainName -type $dnsType -errorAction STOP
        }
        catch
        {
            out-logfile -string $_
            out-logfile -string "Unable to obtain public DNS records." -isError:$TRUE
        } 
    }
    else
    {
        out-logfile -string "Using custom dns resolver."

        try
        {
            $functionDNSRecords += Resolve-DNSName -name $domainName -type $dnsType -server $customDNSServer -errorAction STOP
        }
        catch
        {
            out-logfile -string $_
            out-logfile -string "Unable to obtain public DNS records." -isError:$TRUE
        } 
    }

    WriteXMLFile -data $functionDNSRecords -outputFile $outputFile

    foreach ($entry in $functionDNSRecords)
    {
        if ($entry.type -eq $global:dnsTypeSOA)
        {
            out-logfile -string "Entry is type SOA."

            $functionObject = New-Object PSObject -Property @{
                RecordType = $global:dnsTypeSOA
                Value = "NotApplicable"
            }
        }
        elseif ($entry.type -eq $global:dnsTypeText)
        {
            out-logfile -string "Entry type is TXT."

            foreach ($value in $entry.strings)
            {
                $functionObject = New-Object PSObject -Property @{
                RecordType = $global:dnsTypeText
                Value = $value
                }
            }
        }
        elseif ($entry.type -eq $global:dnsTypeMX)
        {
            out-logfile -string "Entry type is TXT."
            
            $functionObject = New-Object PSObject -Property @{
                RecordType = $global:dnsTypeMX
                Value = $entry.NameExchange  
            }
        }

        $functionDNSRecordsReturn += $functionObject
    }

    out-logfile -string $functionDNSRecordsReturn

    return $functionDNSRecordsReturn
}

#*****************************************************
Function GetMSGraphCall
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $domainName,
        [Parameter(Mandatory = $true)]
        $msGraphUseBeta,
        [Parameter(Mandatory = $true)]
        $msGraphEnvironmentName
    )

    $functionmsGraphPublicVersion = "v1.0"
    $functionmsGraphBetaVersion = "Beta"
    $functionDomainString = "/$functionmsGraphPublicVersion/domains/$domainName/verify"
    $functionDomainStringBeta = "/$functionmsGraphBetaVersion/domains/$domainName/verify"

    out-logfile -string "Enter GetMSGraphCall"

    out-logfile -string $functionDomainString
    out-logfile -string $functionDomainStringBeta

    out-logfile -string "Determining the correct graph api endpoint."

    if (($msGraphEnvironmentName -eq $global:global) -and ($msGraphUseBeta -eq $FALSE))
    {
        out-logfile -string "Global / Not Beta"

        $functionURI = $global:msGraphURLGlobal+$functionDomainString
    }
    elseif (($msGraphEnvironmentName -eq $global:usGov) -and ($msGraphUseBeta -eq $FALSE))
    {
        out-logfile -string "Global / Not Beta"

        $functionURI = $global:msGraphURLUSGov+$functionDomainString
    }
    elseif (($msGraphEnvironmentName -eq $global:usDOD) -and ($msGraphUseBeta -eq $FALSE))
    {
        out-logfile -string "Global / Not Beta"

        $functionURI = $global:msGraphURLUSDoD+$functionDomainString
    }
    elseif (($msGraphEnvironmentName -eq $global:China) -and ($msGraphUseBeta -eq $FALSE))
    {
        out-logfile -string "Global / Not Beta"

        $functionURI = $global:msGraphURLChina+$functionDomainString
    }
    elseif (($msGraphEnvironmentName -eq $global:global) -and ($msGraphUseBeta -eq $TRUE))
    {
        out-logfile -string "Global / Beta"

        $functionURI = $global:msGraphURLGlobal+$functionDomainStringBeta
    }
    elseif (($msGraphEnvironmentName -eq $global:usGov) -and ($msGraphUseBeta -eq $TRUE))
    {
        out-logfile -string "Global / Beta"

        $functionURI = $global:msGraphURLUSGov+$functionDomainStringBeta
    }
    elseif (($msGraphEnvironmentName -eq $global:usDOD) -and ($msGraphUseBeta -eq $TRUE))
    {
        out-logfile -string "Global / Beta"

        $functionURI = $global:msGraphURLUSDoD+$functionDomainStringBeta
    }
    elseif (($msGraphEnvironmentName -eq $global:China) -and ($msGraphUseBeta -eq $TRUE))
    {
        out-logfile -string "Global / Beta"

        $functionURI = $global:msGraphURLChina+$functionDomainStringBeta
    }

    out-logfile -string $functionURI

    return $functionURI
}

#*****************************************************
Function TakeOverDomain
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $msGraphURI,
        [Parameter(Mandatory = $true)]
        $outputFile
    )

    $graphMethod = "Post"
    $body = @{}

    out-logfile -string "Enter TakeOverDomain"

    $body = @{ forceTakeover = $true }

    $body = $body | ConvertTo-Json

    out-logfile -string $body

    try {
        out-logfile -string "Attempting to validate domain."
        Invoke-MGGraphRequest -Method $graphMethod -uri $msGraphURI -Body $body -errorAction Stop
        out-logfile -string 'SUCCESS'
    }
    catch {
        $_ | ConvertTo-Json | set-content $outputFile
        out-logfile -string $_
        out-logfile -string "ERROR OCCURED VALIDATING DOMAIN"
    }
}

#*****************************************************
Function IsDomainViral
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $domainName,
        [Parameter(Mandatory = $true)]
        $outputFile
    )

    out-logfile -string "Enter IsDomainViral"

    $functionURL = "https://login.microsoftonline.com/common/userrealm/"+$domainName+"?api-version=2.1"
    $functionResults = $NULL

    out-logfile -string ("Testing: "+$functionURL)

    $functionResults = Invoke-WebRequest $functionURL

    if ($functionResults.content.contains("IsViral"))
    {
        out-logfile -string "Domain is reporting viral - force takover potentially will succeed."
    }
    else 
    {
        out-logfile "Domain is not reporting viral - unlikely to succeed."
    }

    $functionResults.content | out-file -FilePath $outputFile
}

#*****************************************************
 Function write-hashTable
{
    [cmdletbinding()]

    Param
    (
        [Parameter(Mandatory = $true)]
        $hashTable
    )

    Out-LogFile -string "********************************************************************************"

    foreach ($key in $hashtable.GetEnumerator())
    {
        out-logfile -string ("Key: "+$key.name+" is "+$key.Value.Description+" with value "+$key.Value.Value)
    }      

    Out-LogFile -string "********************************************************************************"
}

#*****************************************************
 Function writeOperationsList
{
    write-host "********************************************************"
    write-host "Select operation to perform:"
    write-host "1:  Add a Domain"
    write-host "2:  Remove a Domain"
    write-host "3:  Verify a Domain"
    write-host "4:  Force Takeover Domain"
    write-host "5:  Display Domain Verification Records"
    write-host "6:  Validate Domain Verification Records in Public DNS"
    write-host "7:  Display Domain DNS Records"
    write-host "8:  Determine Domain Viral Status"
    write-host "9:  Exit"
    write-host "********************************************************"

    [int]$actionChoice = read-host -Prompt "Operation Selected:"

    return $actionChoice
}

#=====================================================================================
#Begin main function body.
#=====================================================================================

#Declare global variables.

$global:global = "Global"
$global:usGov = "USGov"
$global:usDOD = "USDoD"
$global:China = "China"
$global:msGraphURLGlobal = "https://graph.microsoft.com"
$global:msGraphURLUSGov = "https://graph.microsoft.us"
$global:msGraphURLUSDoD = "https://dod-graph.microsoft.us"
$global:msGraphURLChina = "https://microsoftgraph.chinacloudapi.cn"

#Declare variables

[string]$logFileName = "ForceDomainTakeover"
[string]$logFileNameFull = $logFileName +".log"
[string]$resultsJson = "Results.json"
[string]$m365DNSRecordsInfo = "M365DNSRecords.xml"
[string]$publicDNSRecordsTXT = "PublicDNSRecordsTXT.xml"
[string]$publicDNSRecordsMX = "PublicDNSRecordsMX.xml"
[string]$mgContext = "MGContext.xml"
[string]$domainNameInfo = "DomainName.xml"
[string]$viralDomainInfo = "ViralInfo.txt"

[string]$msGraphStaticScope = "Domain.ReadWrite.All"
[string]$msGraphURL = ""
[string]$msGraphAuthType = ""

[string]$outputResultsJson = ""
[string]$outputM365DNSRecords = ""
[string]$outputPublicDNSRecordsTXT = ""
[string]$outputPublicDNSRecordsMX = ""
[string]$outputMGContext = ""
[string]$outputDomainName = ""

$m365DNSRecords = $NULL
$publicTXTRecords = $NULL
$publicMXRecords = $NULL

$global:dnsTypeText = "TXT"
$global:dnsTypeMX = "MX"
$global:dnsTypeSOA = "SOA"

$msGraphFunctionURI = ""
$takeOverDomainResults = $null

$actionChoice = ""
$continueAction = $false

$operations = @{
    add = @{ "Value" =  1 ; "Description" = "Add domain operation"}
    remove = @{ "Value" =  2 ; "Description" = "Remove domain operation"}
    verify = @{ "Value" =  3 ; "Description" = "Verify domain operation"}
    force = @{ "Value" = 4 ; "Description" = "Force domain takeover operation"}
    DNSVerification = @{ "Value" =  5 ; "Description" = "Display DNS verification records operation"}
    DNSPublic = @{ "Value" =  6 ; "Description" = "Display DNS records discovered in public DNS operation"}
    DNSRecords = @{ "Value" =  7 ; "Description" = "Display DNS records for M365 services"}
    viral = @{ "Value" =  8 ; "Description" = "Determine domain viral status operation"}
}

#Create the log file.

new-logfile -logFileName $logFileName -logFolderPath $logFolderPath

out-logfile -string "***********************************************************"
out-logfile -string "Starting ForceDomainTakeOver"
out-logfile -string "***********************************************************"

#Calculate output file names.

out-logfile -string "Calculating output file names..."
$outputresultsJson = $global:LogFile.replace($logFileNameFull,$resultsJson)
$outputM365DNSRecords = $global:LogFile.replace($logFileNameFull,$m365DNSRecordsInfo)
$outputPublicDNSRecordsTXT = $global:LogFile.replace($logFileNameFull,$publicDNSRecordsTXT)
$outputPublicDNSRecordsMX = $global:LogFile.replace($logFileNameFull,$publicDNSRecordsMX)
$outputMGContext = $global:LogFile.replace($logFileNameFull,$mgContext)
$outputDomainName = $global:LogFile.replace($logFileNameFull,$domainNameInfo)
$outputResultsJSON = $global:LogFile.replace($logFileNameFull,$resultsJson)
$outputViralInfo = $global:LogFile.replace($logFileNameFull,$viralDomainInfo)

$global:global:GraphConnection = $FALSE

out-logfile -string ("Output JSON Results: "+$outputresultsJson)
out-logfile -string ("Output M365 DNS Records: "+$outputM365DNSRecords)
out-logfile -string ("Output Public DNS Records TXT: "+$outputPublicDNSRecordsTXT)
out-logfile -string ("Output Public DNS Records MX: "+$outputPublicDNSRecordsMX)
out-logfile -string ("Output MGContext: "+$outputMGContext)
out-logfile -string ("Output DomainName: "+$outputDomainName)
out-logfile -string ("Output ResultsJSON: "+$outputResultsJson)
out-logfile -string ("Output ViralInfo: "+$outputViralInfo)

write-hashTable -hashTable $operations

#Establish graph connection.

out-logfile -string "Perfomring graph pre-checks and connections."

$msGraphEnvironmentName = CheckGraphEnvironment -msGraphEnvironmentName $msGraphEnvironmentName

out-logfile -string ("MSGraphEnvironmentName: "+$msGraphEnvironmentName)

$msGraphTenantID = CheckGraphTenantID -msGraphTenantID $msGraphTenantID

out-logfile -string ("MSGraphTenantID: "+$msGraphTenantID)

$msGraphURL = CheckGraphURL -msGraphEnvironmentName $msGraphEnvironmentName

out-logfile -string ("MSGraphURL: "+$msGraphURL)

$msGraphAuthType = CheckMSGraph -msGraphApplicationID $msGraphApplicationID -msGraphCertificateThumbprint $msGraphCertificateThumbprint -msGraphClientSecret $msGraphClientSecret

out-logfile -string ("MSGraphAuthType: "+$msGraphAuthType)

ConnectMSGraph -msGraphAuthType $msGraphAuthType -msGraphApplicationID $msGraphApplicationID -msGraphCertificateThumbprint $msGraphCertificateThumbprint -msGraphStaticScope $msGraphStaticScope -msGraphClientSecret $msGraphClientSecret -msGraphEnvironmentName $msGraphEnvironmentName -msGraphTenantID $msGraphTenantID

WriteMGContext -outputFile $outputMGContext

do {
    if ($adminOperation -eq "")
    {
        out-logfile -string "Prompt user for next operation to occur."

        $actionChoice = writeOperationsList

        out-logfile -string ("Administrator choice = "+$actionChoice.tostring())

        while ($actionChoice -lt 1 -or $actionChoice -gt 9 -or -not ($actionChoice -is [int])) 
        {
            $actionChoice = writeOperationsList
        }              
    }
    else 
    {
        $actionChoice = $operations.$adminOperation.value

        out-logfile -string ("Administrator choice = "+$actionChoice.tostring())
    }

    out-logfile -string "Proceed with evaluating the administrator action."

    switch ($actionChoice) {
        1 {  
            out-logfile -string "Entered Add Action"

            $domainName = CheckDomainName -domainName $domainName

            IsDomainViral -domainName $domainName -outputFile $outputViralInfo

            TestDomainName -domainName $domainName -outputFile $outputDomainName


        }
        2 {  
            out-logfile -string "Entered Remove Action"
        }
        3 {  
            out-logfile -string "Entered Verify Action"
        }
        4 {  
            out-logfile -string "Entered Force Takeover Action"
        }
        5 {  
            out-logfile -string "Entered Display Domain Verification Records Action"
        }
        6 {  
            out-logfile -string "Entered Validate Domain Records in Public DNS Action"
        }
        7 {  
            out-logfile -string "Entered Display M365 DNS Records Action"
        }
        8 {  
            out-logfile -string "Entered Determined Domain Viral Status Action"
        }
        Default {}
    }
} until (
    $actionChoice -eq 9
)

<#
$domainName = CheckDomainName -domainName $domainName

IsDomainViral -domainName $domainName -outputFile $outputViralInfo

out-logfile -string ("Domain name to process: "+$domainName)

TestDomainName -domainName $domainName -outputFile $outputDomainName

out-logfile -string "Obtaining all relevant DNS records."

$m365DNSRecords = GetM365DNSRecords -domainName $domainName -outputFile $outputM365DNSRecords

$publicTXTRecords = GetPubliCDNS -dnstype $global:dnsTypeText -domainName $domainName -outputFile $outputPublicDNSRecordsTXT -customDNSServer $customDNSServer

$publicMXRecords = GetPublicDNS -dnstype $global:dnsTypeMX -domainName $domainName -outputFile $outputPublicDNSRecordsMX -customDNSServer $customDNSServer

out-logfile -string "Testing to verify that public DNS is updated with verification records."

TestDNSRecords -mx $publicMXRecords -txt $publicTXTRecords -domainName $domainName -m365DNS $m365DNSRecords

out-logfile -string "Obtain MS Graph URI"

$msGraphFunctionURI = GetMSGraphCall -msGraphUseBeta $msGraphUseBeta -msGraphEnvironmentName $msGraphEnvironmentName -domainName $domainName

out-logfile -string "Attempt domain takeover."

TakeOverDomain -msGraphURI $msGraphFunctionURI -outputFile $outputResultsJSON

Disconnect-MgGraph

out-logfile -string "Done"

#>

exit



