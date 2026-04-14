Automation Migration Bundle (EXPORT)
====================================

Runbooks:
- runbooks\published\  (exported via Export-AzAutomationRunbook -Slot Published)
- runbooks\draft\      (optional if IncludeDraftRunbooks was used)

Variables:
- variables\automationVariables.csv
- arm\variables.resources.json     (ARM helper snippet)
- arm\variables.parameters.json    (parameters stub for encrypted variables)

Notes:
- Encrypted variable values are NOT exported. The ARM snippet uses parameters for encrypted values.
