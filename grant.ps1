##########################################
# HelloID-Conn-Prov-Target-Facilitor-Grant
# PowerShell V2
# Version: 1.0.0
###########################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Invoke-FacilitorRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json',

        [Parameter()]
        [System.Collections.IDictionary]
        $Headers = @{}
    )
    process {
        Write-Verbose 'Adding authorization headers'
        $authorization = "$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"
        $base64Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
        $Headers.Add("Authorization", "Basic $base64Credentials")
        try {
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }

            if ($Body) {
                Write-Verbose 'Adding body to request'
                $splatParams['Body'] = $Body
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        } catch {
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
            if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
                $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
                $httpErrorObj.FriendlyMessage = ($ErrorObject.ErrorDetails.Message | ConvertFrom-Json)
            } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if ($null -ne $streamReaderResponse) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        } catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }
    Write-Verbose "Verifying if a Facilitor account for [$($personContext.Person.DisplayName)] exists"
    try {
        $splatParams = @{
            Uri    = "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)?include=authorization"
            Method = 'GET'
        }
        $correlatedAccount = Invoke-FacilitorRestMethod @splatParams
    } catch {
        # A '404' is returned if the entity cannot be found
        if ($_.Exception.Response.StatusCode -eq 404) {
            throw "Facilitor account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted"
        }
        throw
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Verbose "[DryRun] Granting Facilitor entitlement: [$($actionContext.References.Permission.DisplayName)]" -Verbose
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        Write-Verbose "Granting Facilitor entitlement: [$($actionContext.References.Permission.DisplayName)]"
        if ($correlatedAccount.person.authorization.authorizationgroup.id -NotContains $actionContext.References.Permission.Reference) {
            $correlatedAccount.person.authorization += [PSCustomObject]@{
                authorizationgroup = [PSCustomObject]@{
                    id = $actionContext.References.Permission.Reference
                }
            }
            $body = @{
                person = ($correlatedAccount.person | Select-Object authorization)
            } | ConvertTo-Json -Depth 10
            $personUpdateResult = Invoke-FacilitorRestMethod -Method PUT -Body $Body -Uri "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)"
        }
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = 'Grant permission was successful'
                IsError = $false
            })
    }
    $outputContext.Success = $true
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FacilitorError -ErrorObject $ex
        $auditMessage = "Could not grant Facilitor permission. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not grant Facilitor permission. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
