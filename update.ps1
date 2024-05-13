#################################################
# HelloID-Conn-Prov-Target-Facilitor-Update
# PowerShell V2
# Version: 1.0.0
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($actionContext.Configuration.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$correlatedAccount = $null

#region functions


function ConvertTo-AccountObject{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject] $AccountModel,

        [Parameter(Mandatory)]
        [PSCustomObject] $FacilitorPerson

    )
    $account = [PSCustomObject]@{}
    ($AccountModel | Select-Object * -ExcludeProperty costcentreexternalid,departmentexternalid,function,location).PSObject.Properties.foreach{

    $Account | Add-Member -MemberType NoteProperty  -Name $($_.Name) -Value  $FacilitorPerson.$($_.Name)
    }

    if ($null -ne $FacilitorPerson.department.id)
    {

        $ExistingDepartmentResult =  Invoke-FacilitorRestMethod -Method GET -Uri "$($actionContext.Configuration.BaseUrl)/api2/departments?id=$($FacilitorPerson.department.id)"
        $ExistingDepartment = $ExistingDepartmentResult.department
        $Account | Add-Member -MemberType NoteProperty -Name "departmentexternalid" -value "$($ExistingDepartment.Id)" # temporally use id instead of external id
        if ($null -ne $ExistingDepartment.costcentre.id)
        {
            $existingCostCenterResult =  Invoke-FacilitorRestMethod -Method GET -Uri "$($actionContext.Configuration.BaseUrl)/api2/costcentres?id=$($ExistingDepartment.costcentre.id)"
            $existingCostCentre =  $existingCostCenterResult.costcentre
            $Account | Add-Member -MemberType NoteProperty -Name "costcentreexternalid" -value "$($existingCostCentre.id)"   # temporally use id instead of external id
        }
    }

    if ($null -ne $FacilitorPerson.location.id)
    {
        $ExistingLocationResult =  Invoke-FacilitorRestMethod -Method GET -Uri "$($actionContext.Configuration.BaseUrl)/api2/locations?id=$($FacilitorPerson.location.id)"
        $ExistingLocation =  $ExistingLocationResult.location
        $Account | Add-Member -MemberType NoteProperty -Name "locationcode" -value $ExistingLocation.code
    }

    $Account | Add-Member -MemberType NoteProperty -Name "function" -value $FacilitorPerson.function.name
    write-output $Account

}

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

function ConvertTo-FacilitatorPersonUpdateObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject] $Account,

        [Parameter(Mandatory)]
        [PSCustomObject] $propertiesChanged
    )
    $person = @{}
    $shouldUpdateDepartment = $false
    $DependenciesError = $false
    ($Account  | Select-Object * ).PSObject.Properties.foreach{
       if ($_.Name -in $propertiesChanged.Name)
       {
            if($_.Name -in @("departmentexternalid","costcentreexternalid"))
            {
                $shouldUpdateDepartment = $true
            }
            elseif($_.name -eq "function"){
                $function  = @{
                    name = $Account.function
                }
                $person.add('function', $function)

            }
            else {
                $person.Add("$($_.Name)","$($_.Value)")
            }
       }
    }

    if ($shouldUpdateDepartment -eq $true)
    {
        # lookup costcenter based on external id
        # currently externalid is however not working, so the department/costcenter is hardcoded by name atm
        # as it looks that external id is also in the future not available. It probably will be replaced by either name or id


        $costcentreresult = Invoke-FacilitorRestMethod -Method GET -Uri "$($actionContext.Configuration.BaseUrl)/api2/costcentres?name=6201012"
        if($costcentreresult.total_count -eq 1 ){
            $costcentre =  $Costcentreresult.costcentres | Select-Object -First 1
            # lookup department based on external id and associated with the correct costcentre
            Write-Verbose 'lookup department'


            $Departmentresult = Invoke-FacilitorRestMethod -Method GET  -Uri "$($actionContext.Configuration.BaseUrl)/api2/departments?name=1112&costcentre=$($costcentre.id)"  #filter on name is not exact but externalid will be used

            if($Departmentresult.total_count -eq 1 ){
                $department = $departmentresult.Departments | Select-Object -First 1
                $person.add("department", $department.id)
            }
            else {
                $DependenciesError = $true;
                $auditLogMessage =  "Unable to update account completely. No unique department with externalid [$($Account.deparmentexternalid)]found"
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
                    IsError = $true
                })
            }
        }
        else {
            $DependenciesError = $true;
            $auditLogMessage =  "Unable to update account completely. No unique department costcentre with externalid [$($Account.costecentreexternalid)] found"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $auditLogMessage
                IsError = $true
            })
        }

    }

    Write-output $person,$DependenciesError
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
    # Verify that [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found in the actionContext'
    }
    $outputContext.AccountReference = $actionContext.References.Account

    Write-Verbose "Verifying if a Facilitor account for [$($personContext.Person.DisplayName)] exists"

    try {
        $personResult = Invoke-FacilitorRestMethod -Method GET  -Uri "$($actionContext.Configuration.BaseUrl)/api2/persons?id=$($actionContext.References.Account)"
        $correlatedAccount =$personResult.person
        #convert correlated Facilitor account back to helloid account Contextdata,  so it can be compared to the
        $correlatedAccountContextData =  ConvertTo-AccountObject -Account $actionContext.Data -FacilitorPerson $Personresult.person
    }
    catch{
        if ($_.Exception.Response.StatusCode -eq 404) {
            $correlatedAccount = $null;
        }
        else{
            throw
        }
    }
    # Always compare the account against the current account in target system
    if ($null -ne $correlatedAccount) {

        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccountContextData.PSObject.Properties)
            DifferenceObject = @(([PSCustomObject]$actionContext.Data).PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $action = 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
        } else {
            $action = 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
    } else {
        $action = 'NotFound'
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Verbose -Verbose "[DryRun] $dryRunMessage"
    }

    # Process

    switch ($action) {
        'UpdateAccount' {

            $facilitorPersonUpdateObject,$dependenciesError =  ConvertTo-FacilitatorPersonUpdateObject -Account $actionContext.Data -propertiesChanged $propertiesChanged

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Verbose "Updating Facilitor account with accountReference: [$($actionContext.References.Account)]"

                $Headers = @{}
                $Body = @{
                    person = $facilitorPersonUpdateObject
                } | ConvertTo-Json

                $personUpdateResult = Invoke-FacilitorRestMethod -Method PUT -Headers $Headers -Body $Body -Uri "$($actionContext.Configuration.BaseUrl)/api2/persons/$($actionContext.References.Account)"

                # Make sure to test with special characters and if needed; add utf8 encoding.

                if($DependenciesError)
                {
                    $outputContext.PreviousData=$correlatedAccountContextData
                    $outputContext.data = $actionContext.Data
                    $outputContext.Success = $false
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account with accountReference: [$($actionContext.References.Account)] was not completely successful: Department could not be updated. Other properties updated successfully. Account property(s) updated: [$($person.PSObject.Properties.name -join ",")]"
                        IsError = $true
                    })

                }
                else {
                    $outputContext.PreviousData=$correlatedAccountContextData
                    $outputContext.data = $actionContext.Data
                    $outputContext.Success = $true
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account with accountReference: [$($actionContext.References.Account)] was successful, Account property(s) updated: [$($propertiesChanged.name -join ",")]"
                        IsError = $false
                    })
                 }
            }
            break
        }

        'NoChanges' {
            Write-Verbose "No changes to Facilitor account with accountReference: [$($actionContext.References.Account)]"

            $outputContext.PreviousData=$correlatedAccountContextData
            $outputContext.data = $actionContext.Data
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount"
                Message = "Update account with accountReference: [$($actionContext.References.Account)] was succesful. No changes need to be made to the account"
                IsError = $false
            })
            break
        }

        'NotFound' {
            $outputContext.Success  = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount"
                Message = "Facilitor account with accountReference: [$($actionContext.References.Account) for: [$($personContext.Person.DisplayName)] not found. Possibly deleted"
                IsError = $true
            })
            break
        }
    }

} catch {
    $outputContext.Success  = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FacilitorError -ErrorObject $ex
        $auditMessage = "Could not update Facilitor account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Facilitor account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
