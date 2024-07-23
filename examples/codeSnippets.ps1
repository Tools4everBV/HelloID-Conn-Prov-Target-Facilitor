# Function for reading .csv
function Get-MappedValueFromMappingFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $CsvFileLocation,

        [string]
        $ContractPropertyExternalId,

        [Parameter(Mandatory)]
        [string]
        $CsvPropertyHeaderName

    )
    process {
        try {
            $MappingFile = Import-Csv $CsvFileLocation -Delimiter $actionContext.Configuration.Delimiter
            $mappedProperty = ($MappingFile | Where-Object { $_.$($CsvPropertyHeaderName) -eq $ContractPropertyExternalId })
            if ($null -eq $mappedProperty) {
                throw "No $($CsvPropertyHeaderName) found corresponding to $($CsvPropertyHeaderName) ID [$($ContractPropertyExternalId)]"
            }
            
            Write-Output $mappedProperty
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}


# Example cost centre
$splatGetMappedCostcentres = @{
    CsvFileLocation            = $actionContext.Configuration.CostCentreMappingFile
    ContractPropertyExternalId = $actionContext.Data.mapping.costCenterId
    CsvPropertyHeaderName      = 'CostCenter'
}
$mappedCostCentre = Get-FacilitorResource @splatGetMappedCostcentres

# When looking up a field by id the splat Property needs to be changed from costcentres to costcentre
$splatGetCostcentres = @{
    Url            = "$($actionContext.Configuration.BaseUrl)/api2/costcentres?id=$($mappedCostCentre.FacilitorCostCenterId)"
    Property       = 'costcentre'
    PropertyId     = $mappedCostCentre.FacilitorCostCenterId
    SearchProperty = 'id'
}
$costcentre = Get-FacilitorResource @splatGetCostcentres


# Example department
$splatGetMappedDepartments = @{
    CsvFileLocation            = $actionContext.Configuration.DepartmentMappingFile
    ContractPropertyExternalId = $actionContext.Data.mapping.departmentId
    CsvPropertyHeaderName      = 'Department'
}
$mappedDepartment = Get-FacilitorResource @splatGetMappedDepartments

# When looking up a field by id the splat Property needs to be changed from departments to department
$splatGetDepartments = @{
    Url            = "$($actionContext.Configuration.BaseUrl)/api2/departments?id=$($mappedDepartment.FacilitorDepartmentId)"
    Property       = 'department'
    PropertyId     = $mappedDepartment.FacilitorDepartmentId
    SearchProperty = 'id'
}
$department = Get-FacilitorResource @splatGetDepartments


# Example location
$splatGetMappedLocations = @{
    CsvFileLocation            = $actionContext.Configuration.LocationMappingFile
    ContractPropertyExternalId = $actionContext.Data.mapping.locationId
    CsvPropertyHeaderName      = 'Location'
}
$mappedLocation = Get-FacilitorResource @splatGetMappedLocations

# When looking up a field by id the splat Property needs to be changed from locations to location
$splatGetLocations = @{
    Url            = "$($actionContext.Configuration.BaseUrl)/api2/locations?id=$($mappedLocation.FacilitorLocationId)"
    Property       = 'location'
    PropertyId     = $mappedLocation.FacilitorLocationId
    SearchProperty = 'id'
}
$location = Get-FacilitorResource @splatGetLocations