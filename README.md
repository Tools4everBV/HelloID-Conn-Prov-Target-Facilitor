
# HelloID-Conn-Prov-Target-Facilitor

This connector is not yet ready:
1. the create and update, enable and disable scripts work and are tested, but the Costcentre and Department properties unique identifieers are not yet determined  (currently using a hardcoded "id" of the department and ignoring the  costcenterexternalid and departmentexternalid parameters )
2. The grand/revoke scripts are not yet implemented because the call to the target system does not update the rights
3. for more info see https://dev.azure.com/t4e/Connectors/_workitems/edit/22711


| :information_source: Information                                                                                                                                                                                                                                                                                                                                                       |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://facilitor.nl/wp-content/uploads/2019/12/Facilitor_logo_CMYK_FMS_blauw_oranje-382x95.jpg">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Facilitor](#helloid-conn-prov-target-facilitor)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Field mapping](#field-mapping)
        - [Complex mapping](#complex-mapping)
          - [FamilyName](#familyname)
          - [Mail](#mail)
      - [Correlation configuration](#correlation-configuration)
    - [Connection settings](#connection-settings)
    - [Remarks](#remarks)
      - [`Department` \& `CostCentre` validation](#department--costcentre-validation)
      - [`locationcode`](#locationcode)
      - [Enable / Disable](#enable--disable)
      - [Updating using a _HTTP.PUT_](#updating-using-a-httpput)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Facilitor_ is a target connector. _Facilitor_ provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint             | Description |
| -------------------- | ----------- |
| /persons             |             |
| /authorizationgroups |             |

The following lifecycle events are available:

| Event           | Description                         |
| --------------- | ----------------------------------- |
| create.ps1      | Create and/or correlate the Account |
| update.ps1      | Update the Account                  |
| enable.ps1      | Enable the Account                  |
| disable.ps1     | Disable the Account                 |
| delete.ps1      | Not supported
| permissions.ps1 | Retrieve the permissions            |
| grant.ps1       | Grant permission                    |
| revoke.ps1      | Revoke permission                   |

## Getting started

### Provisioning PowerShell V2 connector

This is _Provisioning PowerShell V2_ connector. Meaning that the configuration is a little different contrary to a _Provisioning PowerShell V1_ connector. For more information on how to configure a HelloID PowerShell V2 connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages.

#### Field mapping

The _mapping_ plays a fundamental role in every connector and is essential for aligning the data fields between a HelloID person and the target system. The _Provisioning PowerShell V2_ connector comes with a UI-based field mapping and is therefore, more accessible to a broader audience, including people who may not have a programming background. The mapping can be imported in HelloID using the MappingExportfacilitor.json file

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Facilitor_ to a person in _HelloID_.

To properly set up the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value               |
    | ------------------------- | ------------------- |
    | Enable correlation        | `True`              |
    | Person correlation field  | `Person.ExternalId` |
    | Account correlation field | `employeenumber`    |

### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                          | Mandatory |
| -------- | ------------------------------------ | --------- |
| UserName | The _UserName_ to connect to the API | Yes       |
| Password | The _Password_ to connect to the API | Yes       |
| BaseUrl  | The URL to the API                   | Yes       |

### Remarks

#### `Department` & `CostCentre` validation

During account creation, both the `Department` & `CostCentre` will be validated on existence within _Facililtor_.

| :exclamation Note, department and costcenter selection is not yet determined, currently using a hardcoded id, instead of wat is listed elseware in this document|
|---------------------------------------------------------------|

- The `CostCentre` is validated based on the `Person.PrimaryContract.CostCenter.ExternalId`. The result of this validation is a `costCentre` object containing the `id`.
- The `Department` will then be validated based on the `id` from the `costCentre` object.


Both the `costCentre` and `department` must exists within _Facilitor_.

When either of these validations fail, the account will not be created.
If the account does already exist, then the department will not be updated with the new value in this case, but the other attributes will be updated as normal.


#### `locationcode`

Locations can only be used in combination with: `building`, `floor` and `room`. Because the `building`, `floor` and `room` data might absent within the HR source, the _locationcode_ is currently not available within the connector.

#### Enable / Disable

Both the _enable_ and _disable_ lifecycle actions, will set the `deactivated` property. The value of this property is a `[DateTime]` string in format: `yyyy-MM-ddTHH:mm:ssZ`.

- ℹ️ Within the _disable_ lifecycle action, the value will be set to the current date.

#### Updating using a _HTTP.PUT_

Updating the account is based on a _HTTP.PUT_. A partial _PUT_ is supported within _Facilitor_. Meaning; only the properties that have changed will be updated.

## Getting help

> ℹ️ _For more information on how to configure a HelloID PowerShell V2 connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_

> ℹ️ _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/