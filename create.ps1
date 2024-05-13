#################################################
# HelloID-Conn-Prov-Target-Facilitor-Create
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

function  ConvertTo-FacilitorPersonCreateObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject] $Account,

        [Parameter(Mandatory = $false)]
        [PSCustomObject] $DepartmentId,

        [Parameter(Mandatory = $false)]
        [bool] $Active = $false

    )

    $person = @{}
    $nowUtc = [DateTime]::UtcNow

    $excludedProperties = @("costcentreexternalid","departmentexternalid","function")

    ($Account  | Select-Object * ).PSObject.Properties.foreach{
        if (-not ($_.Name -in  $excludedproperties)){
            $person.Add("$($_.Name)","$($_.Value)")
        }
    }
    if (-not $Active) {
        $person.Add('deactivated',$nowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ"))
    }
    if ($null -ne $DepartmentId){
        $person.add("department", $DepartmentId)
    }
    if($null -ne $Account.function)
    {
        $function  = @{
            name = $Account.function
        }
        $person.add('function', $function)
    }
    write-Output $person

}

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
        $Account | Add-Member -MemberType NoteProperty -Name "departmentexternalid" -value "$($ExistingDepartment.Id)" # temporally use id instead of external id or name
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
#endregion

try {

    # Verify if a user must be either [created and correlated] or just [correlated]
    $correlatedAccount = $null
    if ($actionContext.CorrelationConfiguration.Enabled){
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue
        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly. No correlation field is specified'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw "Correlation is enabled but the contents of the specified correleation field ($correlationField) has no value"
        }
        $personresult = Invoke-FacilitorRestMethod -Method GET  -Uri "$($actionContext.Configuration.BaseUrl)/api2/persons?$correlationField=$correlationValue"
        if($Personresult.total_count -eq 1 ){
            $correlatedAccount = $Personresult.persons | Select-Object -First 1
        }
        elseif($personResult.total_count -gt 1 ) {
            throw "Multiple accounts found with Correlation: $correlationField = $correlationValue"
        }

        if ($null -eq $correlatedAccount){
            $action = 'CreateAccount'
        } else {
            $action = 'CorrelateAccount'
        }
    }
    else {
        trow "The Correlation configuration has not been specified, this is however required for this connector"
    }

     # lookup costcenter based on external id
     # currently externalid is however not working, so the department/costcenter is hardcoded by name atm
     # as it looks that external id is also in the future not available. It probably will be replaced by either name or id

     if ($action -eq'CreateAccount')
     {
        Write-Verbose 'lookup costcentre'
        $costCenter = $personContext.Person.PrimaryContract.CostCenter
        $costCenterMapping = Import-Csv $actionContext.Configuration.CostCentreMappingFile

        $targetCostCentre = ($costCenterMapping | where-object {$_.CostCenter -eq $costCenter.ExternalId})
        if ($null -eq $targetCostCentre) {
            throw "CostCenter with ID [$($costCenter.ExternalId)] does not exist in mapping file"
        }

        $costcentreresult = Invoke-FacilitorRestMethod -Method GET  -Uri "$($actionContext.Configuration.BaseUrl)/api2/costcentres?id=$($targetCostCentre.FacilitorCostCenterId)"

        if($costcentreresult.total_count -eq 1 ){
            $costcentre = $Costcentreresult.costcentres | Select-Object -First 1

            Write-Verbose 'lookup department'
            $department = $personContext.Person.PrimaryContract.Department
            $departmentMapping = Import-Csv "C:\Projects\Consultancy\github_helloid\HelloID-Conn-Prov-Target-Facilitor\departmentMapping.csv"

            $targetDepartment = ($departmentMapping | where-object {$_.Department -eq $department.ExternalId})
            if ($null -eq $targetDepartment) {
                throw "Department with ID [$($department.ExternalId)] does not exist in mapping file"
            }

            $departmentResponse = Invoke-FacilitorRestMethod -Method GET  -Uri "$($actionContext.Configuration.BaseUrl)/api2/departments?id=$($targetDepartment.FacilitorDepartmentId)" #&costcentre.id=$($costcentre.id)"  #filter on name is not exact but externalid will be used
            foreach ($department in $departmentresult){
                if ($department.costcentre.id -eq $costcentre.id) {
                    $departmentResult += $department
                }
            }


            if($departmentResult.total_count -eq 1 ){
                $department =  $departmentResult.Departments | Select-Object -First 1
            }
            else {
                throw "No unique department with externalid $($actionContext.Data.deparmentexternalid) found"
            }
        }
        else {
            throw "No unique costcentre with externalid $($actionContext.Data.costecentreexternalid) found"
        }
    }
    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Verbose -Verbose "[DryRun] $action Facilitor account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            Write-Verbose 'Creating and correlating Facilitor account'

            $facilitorPerson = ConvertTo-FacilitorPersonCreateObject -Account $actionContext.Data -DepartmentId $department.id -Active $false

            #currently locations is not implemented because it is not working

            if (-not($actionContext.DryRun -eq $true)) {

                $body = @{
                    person = $facilitorPerson
                } | ConvertTo-Json

                Write-Verbose 'Create account (person)'
                $personCreateresult = Invoke-FacilitorRestMethod -Method POST  -Body $body -Uri "$($actionContext.Configuration.BaseUrl)/api2/persons"
                if($null -ne $PersonCreateresult.person.id){

                    $createdPerson = $personCreateresult.person
                    $outputContext.AccountReference =  $CreatedPerson.id
                    $outputContext.data = $actionContext.Data
                    $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
                    $outputContext.success = $true
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = $auditLogMessage
                        IsError = $false
                    })
                }
                else {
                   throw "Create account dit not return a reference"
                }
            }
            else {
                Write-Verbose 'Dryrun : Create account (person)'
                $auditLogMessage = "Dryrun : Create account (person)"
                $outputContext.success = $true
                $outputContext.AccountReference = "dummy"
                $outputContext.Data = $actionContext.Data
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
                    IsError = $false
                })
            }
            break
        }

        'CorrelateAccount' {
            Write-Verbose 'Correlating Facilitor account'
            $outputContext.AccountReference = $correlatedAccount.id

            $outputContext.data =  ConvertTo-AccountObject -AccountModel $actionContext.Data -FacilitorPerson $correlatedAccount
            $auditLogMessage = "Correlated account: [$($correlatedAccount.id)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            $outputContext.success = $true
            $outputContext.AccountCorrelated = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CorrelateAccount"
                Message = $auditLogMessage
                IsError = $false
            })

            break
        }
    }
}
catch {
    $outputContext.success = $false
    if($null -eq $outputContext.AccountReference){
        $outputContext.AccountReference = "dummy"
    }
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FacilitorError -ErrorObject $ex
        $auditMessage = "Could not $action for Facilitor. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not $action for Facilitor. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
