################################################
# HelloID-Conn-Prov-Target-Facilitor-Permissions
# PowerShell V2
# Version: 1.0.0
################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
                    write-information 'Adding body to request'
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
            #  Collect ErrorDetails
            if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
                $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message

            } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
                if ($null -ne $ErrorObject.Exception.Response) {
                    if ([string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {

                        $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                        if ($null -ne $streamReaderResponse) {
                            $httpErrorObj.ErrorDetails = $streamReaderResponse
                        }
                    } else {
                        $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
                    }
                }
            }
             $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.message)"

        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    write-information 'Adding authorization headers'
    $authorization = "$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"
    $base64Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
    $splatParams = @{
        Uri = "$($actionContext.Configuration.BaseUrl)/api2/authorizationgroups"
        Method = 'GET'
        Headers = @{
            'Authorization' = "Basic $($base64Credentials)"
        }
    }
    write-information 'Retrieving permissions'
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
        write-information "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        write-information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
}
