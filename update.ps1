#################################################
# HelloID-Conn-Prov-Target-Facilitor-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$correlatedAccount = $null

#region functions
# function Get-MappedValueFromMappingFile {
#     [CmdletBinding()]
#     param (
#         [Parameter(Mandatory)]
#         [string]
#         $CsvFileLocation,

#         [string]
#         $ContractPropertyExternalId,

#         [Parameter(Mandatory)]
#         [string]
#         $CsvPropertyHeaderName

#     )
#     process {
#         try {
#             $MappingFile = Import-Csv $CsvFileLocation -Delimiter $actionContext.Configuration.Delimiter
#             $mappedProperty = ($MappingFile | Where-Object { $_.$($CsvPropertyHeaderName) -eq $ContractPropertyExternalId })

#             if ($null -eq $mappedProperty) {
#                 throw "No $($CsvPropertyHeaderName) found corresponding to $($CsvPropertyHeaderName) ID [$($ContractPropertyExternalId)]"
#             }
            
#             Write-Output $mappedProperty
#         }
#         catch {
#             $PSCmdlet.ThrowTerminatingError($_)
#         }
#     }
# }

function Get-FacilitorResource {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Url,

        [Parameter(Mandatory)]
        [string]
        $Property,

        [string]
        $PropertyId,

        [Parameter(Mandatory)]
        [string]
        $SearchProperty,

        [string]
        $SearchValue
    )

    process {
        try {
            $splatGetProperty = @{
                Uri     = $Url
                Headers = $headers
                Method  = 'GET'
            }

            $resultProperty = ([array](Invoke-RestMethod @splatGetProperty)).$($property)

            if ($resultProperty.count -eq 0) {
                throw "No $($Property) found in target system corresponding to $($Property) $SearchProperty [$($PropertyId)]"     
            }
            elseif ($resultProperty.count -gt 1) {
                throw "More than 1 $($Property) found in target system corresponding to $($Property) $SearchProperty [$($PropertyId)]"
            }

            Write-Output $resultProperty 
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function ConvertTo-FacilitorFlatObject {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object,
        [string] $Prefix = ""
    )
 
    $result = [ordered]@{}
 
    foreach ($property in $Object.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix`_$($property.Name)" } else { $property.Name }
 
        if ($null -ne $property.Value) {
            if ($property.Value -is [pscustomobject]) {
                $flattenedSubObject = ConvertTo-FacilitorFlatObject -Object $property.Value -Prefix $name
                foreach ($subProperty in $flattenedSubObject.PSObject.Properties) {
                    $result[$subProperty.Name] = [string]$subProperty.Value
                }
            }
            else {
                $result[$name] = [string]$property.Value
            }
        }
    }
 
    [PSCustomObject]$result
}

function Resolve-FacilitorError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }

        try {
            #  Collect ErrorDetails
            if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
                $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message

            }
            elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
                if ($null -ne $ErrorObject.Exception.Response) {
                    if ([string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
                        1

                        $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                        if ($null -ne $streamReaderResponse) {
                            $httpErrorObj.ErrorDetails = $streamReaderResponse
                        }
                    }
                    else {
                        $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
                    }
                }
            }
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.message)"

        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function Add-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorMessage,

        [Parameter(Mandatory)]
        [bool]
        $IsError
    )
    process {
        try {
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $ErrorMessage
                    IsError = $IsError
                })           
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
#endregion

try {
    # Verify that [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found in the actionContext'
    }
    $outputContext.AccountReference = $actionContext.References.Account

    $headers = @{
        'Content-Type'        = 'application/json; charset=utf-8'
        Accept                = 'application/json; charset=utf-8'
        'X-FACILITOR-API-KEY' = $actionContext.Configuration.APIKey
    }

    Write-Information "Verifying if a Facilitor account for [$($personContext.Person.DisplayName)] exists"

    try {
        $splatGetUser = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)?include=custom_fields"
            Method  = 'GET'
            Headers = $headers
        }
        $correlatedAccount = (Invoke-RestMethod @splatGetUser).person
    }
    catch {
        # A '404' is returned if the entity cannot be found
        if ($_.Exception.Response.StatusCode -eq 404) {
            $correlatedAccount = $null
        }
        else {
            throw
        }
    }

    $isValidationError = $false

    Write-Information "Lookup Cost Centre name"
    try {
        $splatGetCostcentres = @{
            Url            = "$($actionContext.Configuration.BaseUrl)/api2/costcentres?name=$($actionContext.Data.mapping.costCenterId)"
            Property       = 'costcentres'
            PropertyId     = $actionContext.Data.mapping.costCenterId
            SearchProperty = 'name'
        }
        $costcentre = Get-FacilitorResource @splatGetCostcentres
        
        $actionContext.Data | Add-Member @{
            costcentre = [PSCustomObject]@{
                id = $costcentre.id
            }
        } -Force
    }
    catch {
        $isValidationError = $true
        Add-AuditLog -ErrorMessage "$($_.Exception.message)" -IsError $true           
    }

    Write-Information "Lookup Department via Mapping"
    try {
        $splatGetDepartments = @{
            Url            = "$($actionContext.Configuration.BaseUrl)/api2/departments?name=$($actionContext.Data.mapping.departmentId)"
            Property       = 'departments'
            PropertyId     = $actionContext.Data.mapping.departmentId
            SearchProperty = 'name'
        }
        $department = Get-FacilitorResource @splatGetDepartments

        $actionContext.Data | Add-Member @{
            department = [PSCustomObject]@{
                id = $department.id
            }
        } -Force

    }
    catch {
        $isValidationError = $true
        Add-AuditLog -ErrorMessage "$($_.Exception.message)" -IsError $true             
    }

    Write-Information "Lookup Location via Mapping"
    try {
        if (-not ([string]::IsNullOrEmpty($actionContext.Data.mapping.locationId))) {
            $splatGetLocations = @{
                Url            = "$($actionContext.Configuration.BaseUrl)/api2/locations?visitzipcode=$($actionContext.Data.mapping.locationId)"
                Property       = 'locations'
                PropertyId     = $actionContext.Data.mapping.locationId
                SearchProperty = 'visitzipcode'
            }
            $location = Get-FacilitorResource @splatGetLocations
        }
        else {
            Write-Information "LocationId (vistizip) is empty lookup skiped"
        }
        $actionContext.Data.custom_fields = @(
            [PSCustomObject]@{
                propertyid = 1060
                value      = "$($location.id)"
                Type       = "N"
                sequence   = 50
                label      = "Locatie ID"
            }
        )
    }
    catch {
        $isValidationError = $true
        Add-AuditLog -ErrorMessage "$($_.Exception.message)" -IsError $true             
    }

    if ($isValidationError) {
        throw 'Validation error'
    }

    $actionContext.Data | Add-Member @{
        function = [PSCustomObject]@{
            name = "$($actionContext.Data.mapping.function)"
        }
    } -Force

    # Always compare the account against the current account in target system
    if (($null -ne $correlatedAccount) -and ($isValidationError -eq $false)) {
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @(($actionContext.Data | Select-Object * -ExcludeProperty id, custom_fields, costcentre, department, function, mapping).PSObject.Properties)
        }
        $propertiesChangedObject = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        $propertiesChanged = @{}
        $propertiesChangedObject | ForEach-Object { $propertiesChanged[$_.Name] = $_.Value }

        #additional compares for nested objects
        if ($correlatedAccount.costcentre.id -ne $actionContext.data.costcentre.id) {
            $propertiesChanged['costcentre'] = $actionContext.Data.costcentre
        }

        if ($correlatedAccount.department.id -ne $actionContext.data.department.id) {
            $propertiesChanged['department'] = $actionContext.Data.department
        }

        if ($correlatedAccount.function.name -ne $actionContext.data.function.name) {
            $propertiesChanged['function'] = $actionContext.Data.function
        }

        # only select location custom field for compared
        $correlatedAccount.custom_fields = @($correlatedAccount.custom_fields | Where-Object { $_.propertyid -eq 1060 })
        if ([string]$correlatedAccount.custom_fields.value -ne $actionContext.data.custom_fields.value) {
            $propertiesChanged['custom_fields'] = $actionContext.Data.custom_fields
        }

        if ($($propertiesChanged.Keys).count -gt 0) {
            $action = 'UpdateAccount'
        }
        else {
            $action = 'NoChanges'
        }
    }
    else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {  
            Write-Information "Updating Facilitor account with accountReference: [$($actionContext.References.Account)], Account property(s) required to update: $($propertiesChanged.Keys -join ', ')"

            $body = @{
                person = $propertiesChanged
            } | ConvertTo-Json -Depth 10

            $splatUpdateUser = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)?include=custom_fields"
                Method  = 'PUT'
                Headers = $headers
                Body    = [System.Text.Encoding]::UTF8.GetBytes($body)
            }

            if (-not($actionContext.DryRun -eq $true)) {
                $updatePersonResult = Invoke-RestMethod @splatUpdateUser
                $outputContext.PreviousData = $correlatedAccount
                $outputContext.data = $updatePersonResult.person

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account with accountReference: [$($actionContext.References.Account)] was successful, Account property(s) updated: [$($propertiesChanged.Keys -join ",")]"
                        IsError = $false
                    })
            }
            else {
                write-warning "DryRun would update account: $body"
            }

            $outputContext.Success = $true
        }

        'NoChanges' {
            Write-Information "No changes to Facilitor account with accountReference: [$($actionContext.References.Account)]"

            $outputContext.PreviousData = $correlatedAccount
            $outputContext.data = $actionContext.Data
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account with accountReference: [$($actionContext.References.Account)] was succesful. No changes need to be made to the account"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Facilitor account with accountReference: [$($actionContext.References.Account)] for: [$($personContext.Person.DisplayName)] not found. Possibly deleted"
                    IsError = $true
                })
            break
        }
    }

}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FacilitorError -ErrorObject $ex
        $auditMessage = "Could not update Facilitor account. Error: $($errorObj.FriendlyMessage)"
        Write-Information "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not update Facilitor account. Error: $($ex.Exception.Message)"
        Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    if (-Not($ex.Exception.Message -eq 'Validation error')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $auditMessage
                IsError = $true
            })
    }
}