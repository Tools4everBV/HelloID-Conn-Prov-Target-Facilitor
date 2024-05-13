############################################
# HelloID-Conn-Prov-Target-Facilitor-Disable
# PowerShell V2
# Version: 1.0.0
############################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($actionContext.Configuration.IsDebug)) {
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
        $ContentType = 'application/json; charset=utf-8',

        [Parameter(Mandatory = $false)]
        [System.Collections.IDictionary]
        $Headers = @{}
    )

    process {
        try {

            $authorization = "$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"
            $base64Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
            $Headers.Add("Authorization","Basic $base64Credentials")
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }

            if (-not  [string]::IsNullOrEmpty($actionContext.Configuration.ProxyAddress)) {
                $splatParams['Proxy'] = $actionContext.Configuration.ProxyAddress
            }

            if ($Body){
                Write-Verbose 'Adding body to request'
                $splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($Body)
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
            #  Collect ErrorDetails
            if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
                $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message

            } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
                if ($null -ne $ErrorObject.Exception.Response)
                {
                    if ([string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)){

                        $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                        if($null -ne $streamReaderResponse){
                            $httpErrorObj.ErrorDetails = $streamReaderResponse
                        }
                    }
                    else {
                        $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
                    }
                }
            }
            # Build FriendlyMessage

            try {
                $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.message)"
            }catch
            {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }

        } catch {

        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }



    Write-Verbose "Verifying if a Facilitor account for [$($personContext.Person.DisplayName)] exists"
    try {
        $splatParams = @{}
        $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)"
        $splatParams['Method'] = 'GET'
        $personResult = Invoke-FacilitorRestMethod @splatParams
        $correlatedAccount =$personResult.person
    }
    catch {
        # A '404' is returned if the entity cannot be found
        if ($_.Exception.Response.StatusCode -eq 404) {
            $correlatedAccount = $null
        } else {
            throw
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'DisableAccount'
        $dryRunMessage = "Disable Facilitor account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] will be executed during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "Facilitor account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Verbose -Verbose "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'DisableAccount' {
                Write-Verbose "Disabling Facilitor account with accountReference: [$($actionContext.References.Account)]"


                $nowUtc = [DateTime]::UtcNow
                $body = @{
                    person = @{
                        deactivated = $nowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                } | ConvertTo-Json
                $splatParams = @{}
                $splatParams['Uri'] = "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)"
                $splatParams['Body'] = $body
                $splatParams['Method'] = 'PUT'
                $null = Invoke-FacilitorRestMethod @splatParams

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Disable account with accountReference: [$($actionContext.References.Account)] was successful"
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $outputContext.Success  = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Facilitor account with accountReference: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Skipping action"
                    IsError = $false
                })
                break
            }
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FacilitorError -ErrorObject $ex
        $auditMessage = "Could not disable Facilitor account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not disable Facilitor account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Action  = $action
        Message = $auditMessage
        IsError = $true
    })
}
