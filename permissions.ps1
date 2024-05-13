################################################
# HelloID-Conn-Prov-Target-Facilitor-Permissions
# PowerShell V2
# Version: 1.0.0
################################################

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

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [switch]
        $Paging
    )

    process {
        try {
            $limit = 100
            $offset = 0
            $returnValue = [System.Collections.Generic.list[object]]::new()
            if ($Paging) {
                if ($Uri.Contains('?')) {
                    $Uri += "&limit=$limit&offset=$offset"
                } else {
                    $Uri += "?limit=$limit&offset=$offset"
                }
            }
            do {
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
                $partialResult = Invoke-RestMethod @splatParams -Verbose:$false

                if ($partialResult.authorizationgroups.count -gt 0) {
                    $returnValue.AddRange($partialResult.authorizationgroups)
                    $offset += $limit
                    $Uri = $Uri -replace 'offset=\d+', "offset=$offset"
                }

            }until ($partialResult.authorizationgroups.count -lt $limit)

            Write-Output $returnValue -NoEnumerate
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

try {
    Write-Verbose 'Adding authorization headers'
    $authorization = "$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"
    $base64Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
    $splatParams = @{
        Headers = @{
            'Authorization' = "Basic $($base64Credentials)"
        }
    }
    Write-Verbose 'Retrieving permissions'
    $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api2/authorizationgroups"
    $splatParams['Method'] = 'GET'
    $permissions = Invoke-FacilitorRestMethod @splatParams -Paging
    foreach ($permission in $permissions) {
        $outputContext.Permissions.Add(
            @{
                DisplayName    = $permission.name
                Identification = @{
                    Reference   = $permission.id
                    DisplayName = $permission.name
                }
            }
        )
    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FacilitorError -ErrorObject $ex
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
}
