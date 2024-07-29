###########################################
# HelloID-Conn-Prov-Target-Facilitor-Revoke
# PowerShell V2
############################################

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
#endregion

# Begin
try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $headers = @{
        'Content-Type'        = 'application/json; charset=utf-8'
        Accept                = 'application/json; charset=utf-8'
        'X-FACILITOR-API-KEY' = $actionContext.Configuration.APIKey
    }

    Write-Information  "Verifying if a Facilitor account for [$($personContext.Person.DisplayName)] exists"
    try {
        $splatParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)?include=authorization"
            Method  = 'GET'
            Headers = $headers
        }
        $correlatedAccount = Invoke-RestMethod @splatParams
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

    if ($correlatedAccount) {
        $action = 'RevokePermission'
    }
    elseif ($null -eq $responseUser) {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'RevokePermission' {
            Write-Information  "Revoking Facilitor permission: [$($actionContext.References.Permission.Reference)]"
            if ($correlatedAccount.person.authorization.authorizationgroup.id -Contains $actionContext.References.Permission.Reference) {
                $authorizationBody = [array]($correlatedAccount.person.authorization | Where-Object { $_.authorizationgroup.id -ne $actionContext.References.Permission.Reference })
                if ($null -eq $authorizationBody) {
                    $authorizationBody = @()
                }
                $body = @{
                    person = @{
                        authorization = $authorizationBody
                    }
                } | ConvertTo-Json -Depth 10

                $splatRevokePermission = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)"
                    Method  = 'PUT'
                    Headers = $headers
                    Body    = $body
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    $null = Invoke-RestMethod @splatRevokePermission

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = 'Revoke permission was successful'
                            IsError = $false
                        })
                }
                else {
                    write-warning "DryRun would revoke permission: $body"
                }
            }
            else {
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = 'Permission was already revoked'
                        IsError = $false
                    })
            }

            $outputContext.Success = $true
            break
        }

        'NotFound' {
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Facilitor account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
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
        $auditMessage = "Could not revoke Facilitor permission. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not revoke Facilitor permission. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = 'RevokePermission'
            Message = $auditMessage
            IsError = $true
        })
}