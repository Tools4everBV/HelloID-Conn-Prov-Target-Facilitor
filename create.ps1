#################################################
# HelloID-Conn-Prov-Target-Facilitor-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions

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
        $SearchProperty
    )
    process {
        try {
            if ([string]::IsNullOrEmpty($PropertyId)) {
                throw "The mapped value for $($Property) is empty in HelloID. This is a required field"
            }

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
    # Verify if a user must be either [created and correlated] or just [correlated]
    $outputContext.AccountReference = 'Currently not available'

    $headers = @{
        'Content-Type'        = 'application/json; charset=utf-8'
        Accept                = 'application/json; charset=utf-8'
        'X-FACILITOR-API-KEY' = $actionContext.Configuration.APIKey
    }

    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue
        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly. No correlation field is specified'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw "Correlation is enabled but the contents of the specified correleation field ($correlationField) has no value"
        }

        $splatGetUser = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api2/persons?$correlationField=$correlationValue"
            Headers = $headers
            Method  = 'GET'
        }
        $personResult = Invoke-RestMethod @splatGetUser

        if ($personResult.total_count -eq 1 ) {
            $correlatedAccount = $personResult.persons | Select-Object -First 1
        }
        elseif ($personResult.total_count -gt 1 ) {
            throw "Multiple accounts found with Correlation: $correlationField = $correlationValue"
        } 
    }

    if ($null -eq $correlatedAccount) {
        $action = 'CreateAccount'
    }
    else {
        $action = 'CorrelateAccount'
    }

    if ($action -eq 'CreateAccount') {
        $isValidationError = $false
            
        try {
            $splatGetCostcentres = @{
                Url            = "$($actionContext.Configuration.BaseUrl)/api2/costcentres?name=$($actionContext.Data.mapping.costCenterId)"
                Property       = 'costcentres'
                PropertyId     = $actionContext.Data.mapping.costCenterId
                SearchProperty = 'name'
            }
            $costcentre = Get-FacilitorResource @splatGetCostcentres

            $costCentreValue = @{
                id = $costcentre.id
            }
            $actionContext.Data | Add-Member -MemberType NoteProperty -Name "costcentre" -Value $costCentreValue
        }
        catch {
            $isValidationError = $true
            Add-AuditLog -ErrorMessage "$($_.Exception.message)" -IsError $true           
        }

        try {
            $splatGetDepartments = @{
                Url            = "$($actionContext.Configuration.BaseUrl)/api2/departments?name=$($actionContext.Data.mapping.departmentId)"
                Property       = 'departments'
                PropertyId     = $actionContext.Data.mapping.departmentId
                SearchProperty = 'name'
            }
            $department = Get-FacilitorResource @splatGetDepartments

            $departmentValue = @{
                id = $department.id
            }
            $actionContext.Data | Add-Member -MemberType NoteProperty -Name "department" -Value $departmentValue
        }
        catch {
            $isValidationError = $true
            Add-AuditLog -ErrorMessage "$($_.Exception.message)" -IsError $true             
        }

        try {
            $splatGetLocations = @{
                Url            = "$($actionContext.Configuration.BaseUrl)/api2/locations?visitzipcode=$($actionContext.Data.mapping.locationId)"
                Property       = 'locations'
                PropertyId     = $actionContext.Data.mapping.locationId
                SearchProperty = 'visitzipcode'
            }
            $location = Get-FacilitorResource @splatGetLocations

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
    }

    # Process
    switch ($action) {
        'CreateAccount' {

            # No mapping needed for function, resource script creates all functions.
            $actionContext.Data | Add-Member @{
                function = [PSCustomObject]@{
                    name = "$($actionContext.Data.mapping.function)"
                }
            } -Force

            $createBody = @{
                person = $actionContext.Data | Select-Object * -ExcludeProperty mapping
            } | ConvertTo-Json -Depth 10

            Write-Information 'Creating and correlating Facilitor account'
            $splatCreateUser = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api2/persons?inlcude=custom_fields"
                Headers = $headers
                Method  = 'POST'
                Body    = [System.Text.Encoding]::UTF8.GetBytes($createBody)
            }

            if (-not($actionContext.DryRun -eq $true)) {
                $createPersonResult = Invoke-RestMethod @splatCreateUser
                $outputContext.AccountReference = $createPersonResult.person.id
                $outputContext.data = $createPersonResult.person

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
                        IsError = $false
                    })
            }
            else {
                write-warning "DryRun would create account: $createBody"
            }
            
            $outputContext.Success = $true 
            break
        } 

        'CorrelateAccount' {
            Write-Information 'Correlating Facilitor account'
            $outputContext.AccountReference = $correlatedAccount.id
            $outputContext.data = $correlatedAccount
            $outputContext.AccountCorrelated = $true

            $outputContext.success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount"
                    Message = "Correlated account: [$($correlatedAccount.id)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                    IsError = $false
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem

    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FacilitorError -ErrorObject $ex
        $auditMessage = "Could not create or correlate for Facilitor. Error: $($errorObj.FriendlyMessage)"
        Write-Information "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not create or correlate for Facilitor. Error: $($ex.Exception.Message)"
        Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    if (-Not($ex.Exception.Message -eq 'Validation error')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $auditMessage
                IsError = $true
            })
    }
}
