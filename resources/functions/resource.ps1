########################################################
# HelloID-Conn-Prov-Target-Facilitor-Resources-Functions
# PowerShell V2
########################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
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

function Get-FacilitorEmployeeFunctions {
    param (
        [Parameter()]
        [string]
        $BaseUrl,
 
        [Parameter()]
        [object]
        $Headers,
 
        [Parameter()]
        [int]
        $Limit = 100
    )
 
    Write-Information 'Retrieving all employeeFunctions from Facilitor'
 
    $splatRetrieveEmployeeFunctionsParams = @{
        Method      = 'GET'
        Headers     = $headers
        ContentType = 'application/json'
    }
 
    $offset = 0
    $allEmployeeFunctions = @()
 
    do {
        $splatRetrieveEmployeeFunctionsParams['Uri'] = "$BaseUrl/api2/employeefunctions?limit=$Limit&offset=$offset"
        $response = Invoke-RestMethod @splatRetrieveEmployeeFunctionsParams
 
        $allEmployeeFunctions += $response.employeefunctions
        $offset += $Limit
    } while ($response.employeefunctions.Count -eq $Limit)
 
    Write-Information "Retrieved [$($allEmployeeFunctions.count)] functions"

    $allEmployeeFunctions
}
#endregion

try {
    Write-Information 'Setting authorization header'
    
    $headers = @{
        'Content-Type'        = 'application/json; charset=utf-8'
        Accept                = 'application/json; charset=utf-8'
        'X-FACILITOR-API-KEY' = $actionContext.Configuration.APIKey
    }

    $allEmployeeFunctions = Get-FacilitorEmployeeFunctions -BaseUrl $actionContext.Configuration.BaseUrl -Headers $headers

    Write-Information 'Checking how many employeeFunctions will be created'
    $employeeFunctionsToCreate = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in $resourceContext.SourceData) {
        $exists = $allEmployeeFunctions | Where-Object { $_.name -eq $resource }
        if (-not $exists) {
            if (-not ([string]::IsNullOrEmpty($resource))) {
                $employeeFunctionsToCreate.Add($resource)
            }
        }
        else {
            if ($actionContext.DryRun -eq $True) {
                Write-Information "[DryRun] Found [$($resource)] Facilitor resource $($exists | Convertto-json)"
            }
        }
    }

    Write-Information "Creating [$($employeeFunctionsToCreate.Count)] resources"
    foreach ($resource in $employeeFunctionsToCreate) {
        try {
            if (-not ($actionContext.DryRun -eq $True)) {
                $employeeFunctionObject = @{
                    employeefunction = @{
                        name = $resource
                    }
                } | ConvertTo-Json

                $splatCreateResourceParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/api2/employeefunctions"
                    Method      = 'POST'
                    Headers     = $headers
                    ContentType = 'application/json'
                    Body        = $employeeFunctionObject
                }
                $null = Invoke-RestMethod @splatCreateResourceParams -verbose:$false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Created resource: [$($resource)]"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Create [$($resource)] Facilitor resource, will be executed during enforcement+"
            }
        }
        catch {
            $outputContext.Success = $false
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-FacilitorError -ErrorObject $ex
                $auditMessage = "Could not create Facilitor resource [$($resource)]. Error: $($errorObj.FriendlyMessage)"
                Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            }
            else {
                $auditMessage = "Could not create Facilitor resource. Error: $($ex.Exception.Message)"
                Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditMessage
                    IsError = $true
                })
        }
    }
    $outputContext.Success = $true
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FacilitorError -ErrorObject $ex
        $auditMessage = "Could not create Facilitor resource. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not create Facilitor resource. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}