# HelloID-Conn-Prov-Target-Facilitor

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
| /costcentres         |             |
| /departments         |             |
| /locations           |             |

The following lifecycle events are available:

| Event           | Description                         |
| --------------- | ----------------------------------- |
| create.ps1      | Create and/or correlate the Account |
| update.ps1      | Update the Account                  |
| enable.ps1      | Enable the Account                  |
| disable.ps1     | Disable the Account                 |
| delete.ps1      | Not supported                       |
| permissions.ps1 | Retrieve the permissions            |
| grant.ps1       | Grant permission                    |
| revoke.ps1      | Revoke permission                   |
| resource.ps1    | create resources                    |

## Getting started

### Provisioning PowerShell V2 connector

This is _Provisioning PowerShell V2_ connector. Meaning that the configuration is a little different contrary to a _Provisioning PowerShell V1_ connector. For more information on how to configure a HelloID PowerShell V2 connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages.

#### Field mapping

The _mapping_ plays a fundamental role in every connector and is essential for aligning the data fields between a HelloID person and the target system. The _Provisioning PowerShell V2_ connector comes with a UI-based field mapping and is therefore, more accessible to a broader audience, including people who may not have a programming background. The mapping can be imported in HelloID using the fieldMapping.json file

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

### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                          | Mandatory |
| -------- | ------------------------------------ | --------- |
| UserName | The _UserName_ to connect to the API | Yes       |
| Password | The _Password_ to connect to the API | Yes       |
| BaseUrl  | The URL to the API                   | Yes       |

### Remarks

The connector uses a custom field for populating the location field, the custom field used for this is identified by the ID 1080 and labeled 'Locatie ID. This is because the existing location field for the person corresponds to the preferred location of that person, not the location where the person actually works.

#### Mapping

The field mapping contains a mapping object where the cost centre, department, location, and function are populated with either the ID or the name of the corresponding object in the primary contract. This mapping object is used in the create and update lifecycle for validation.

The validation process works as follows: the value from the mapping object is looked up in the .csv file and retrieves the corresponding ID of the object in Facilitor. After that, the ID is used in a GET request to verify if the object exists in Facilitor. If that is the case, it gets added to the create body. If something goes wrong during validation, the connector will return a validation error.

This works a little bit differently for the function. The resource script creates all the values needed for the function field, so no validation is needed because all the possible functions already exist in Facilitor.

The connector utilizes three separate mapping files. Examples of these mapping files can be found in the Assets folder. The column names in these mapping files are hardcoded and used in the connector. If you want to change these, make sure to also edit the connector accordingly.

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
