# HelloID-Conn-Prov-Target-Facilitor

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Facilitor/blob/main/Logo.png?raw=true">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Facilitor](#helloid-conn-prov-target-facilitor)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Functional description](#functional-description)
    - [Connection settings](#connection-settings)
    - [Field mapping](#field-mapping)
      - [Correlation configuration](#correlation-configuration)
    - [Remarks](#remarks)
      - [Custom field](#custom-field)
      - [Cost centre, department and location](#cost-centre-department-and-location)
      - [Functions](#functions)
      - [Enable / Disable](#enable--disable)
      - [Updating using a _HTTP.PUT_](#updating-using-a-httpput)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Facilitor_ is a target connector. _Facilitor_ provides a set of REST APIs that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint             | Description                                                                |
| -------------------- | -------------------------------------------------------------------------- |
| /persons             | `GET / POST` actions to read and write the user in Facilitor               |
| /authorizationgroups | `GET` actions to read authorization groups from Facilitor                  |
| /costcentres         | `GET` actions to read cost centers from Facilitor                          |
| /departments         | `GET` actions to read departments from Facilitor                           |
| /locations           | `GET` actions to read locations from Facilitor                             |
| /employeefunctions   | `GET / POST` actions to read and write the employee functions in Facilitor |

The following lifecycle events are available:

| Event                                   | Description                                                     |
| --------------------------------------- | --------------------------------------------------------------- |
| create.ps1                              | Create and/or correlate the Account                             |
| update.ps1                              | Update the Account                                              |
| enable.ps1                              | Enable the Account                                              |
| disable.ps1                             | Disable the Account                                             |
| delete.ps1                              | Only disables the account. Deleting an account is not supported |
| permissions/groups/permissions.ps1      | Retrieve the permissions                                        |
| permissions/groups/grantPermission.ps1  | Grant permission                                                |
| permissions/groups/revokePermission.ps1 | Revoke permission                                               |
| resources/functions/resource.ps1        | create function resources                                       |
| configuration.json                      | Default _configuration.json_                                    |
| fieldMapping.json                       | Default _fieldMapping.json_                                     |

## Getting started

### Functional description

The purpose of this connector is to _manage user account provisioning_ within Facilitor.

In addition, the connector manages permissions

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                        | Mandatory |
| ------- | ---------------------------------- | --------- |
| APIKey  | The _APIKey_ to connect to the API | Yes       |
| BaseUrl | The URL to the API                 | Yes       |

### Field mapping

The field mapping can be imported by using the [_fieldMapping.json_](./fieldMapping.json) file.

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Facilitor_ to a person in _HelloID_.

To properly set up the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

 | Setting                   | Value               |
 | ------------------------- | ------------------- |
 | Enable correlation        | `True`              |
 | Person correlation field  | `Person.ExternalId` |
 | Account correlation field | `employeeNumber`    |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Remarks

#### Custom field

The connector uses a custom field for populating the location field, the custom field used for this is identified by the ID `1060` and labeled `Locatie ID`. This is because the existing location field for the person corresponds to the preferred location of that person, not the location where the person works. Facilitor uses a daily running script that reads the custom field to fill the location where the person works.

> [!IMPORTANT]
> `custom_fields` are mapped in the powershell `create.ps1` and `update.ps1` script. Make sure you get the right `propertyid` from Facilitor. In the current script `1060` is used.

#### Cost centre, department and location

The field mapping contains a mapping object where the cost centre, department and location are populated with either the ID or the name of the corresponding object in the primary contract. This mapping object is used in the create and update lifecycle for validation.

The validation process works as follows: the value from the mapping object is looked up in Faciltor and retrieves the corresponding ID of the object in Facilitor. By default on `name` or `visitzipcode`. If something goes wrong during validation, the connector will return a validation error. You can edit the `SearchProperty` in the  `create.ps1` and `update.ps1` script. Example:

```Powershell
$splatGetDepartments = @{
    Url = "$($actionContext.Configuration.BaseUrl)/api2/departments?name=$($actionContext.Data.mapping.departmentId)"
    Property = 'departments'
    PropertyId = $actionContext.Data.mapping.departmentId
    SearchProperty = 'name'
}
```

> [!TIP]
> Optionally you can use a .csv file and retrieve the corresponding IDs. Please check out the [_examples folder_](./examples) to get you started

#### Functions
The resource script creates all the values needed for the function field. The functions are mapped by name but must exist in Facilitor.

#### Enable / Disable

Both the _enable_ and _disable_ lifecycle actions, will set the `deactivated` property. The value of this property is a `[DateTime]` string in the format: `yyyy-MM-ddTHH:mm:ssZ`.

- ℹ️ Within the _disable_ lifecycle action, the value will be set to the current date.

> [!IMPORTANT]
> The `enable.ps1` and `disable.ps1` are only needed if Facilitor doesn't delete the person when `deactivated` is filled. If used please also test if `deactivated` is overridden when updating the account. This could still be a problem in Facilitor.

#### Updating using a _HTTP.PUT_

Updating the account is based on a _HTTP.PUT_. A partial _PUT_ is supported within _Facilitor_. Meaning; that only the properties that have changed will be updated.

## Getting help

> ℹ️ _For more information on how to configure a HelloID PowerShell V2 connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_

> ℹ️ _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
