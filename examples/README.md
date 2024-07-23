# Examples of how to add .csv in your code

> [!IMPORTANT]
> We recommend only using .csv if the required values are not available in your HelloID source system.

The validation process works as follows: the value from the mapping object is looked up in the .csv file and retrieves the corresponding ID of the object in Facilitor. After that, the ID is used in a GET request to verify if the object exists in Facilitor. If that is the case, it gets added to the create body. If something goes wrong during validation, the connector will return a validation error.

The connector utilizes three separate mapping files. Examples of these mapping files can be found in the [_assets folder_](./examples/assets). The column names in these mapping files are hardcoded and used in the connector. If you want to change these, make sure to also edit the connector accordingly.

Please checkout  [_codeSnippets.ps1_](./examples/codeSnippets.ps1) for examples codes.