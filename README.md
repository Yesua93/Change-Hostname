# RenameComputer.ps1
Script to remotely rename computers in a hybrid environment (Intune)

¡¡¡IMPORTANT!!!
In order to use this script, you must delegate the permission to add and change objects to the OU where the equipment is to be used.

To deploy to Intune, make a Win32 app package and deploy as System.

What does this script do?
This script checks for connectivity to AD and AAD (Enter ID).
It checks the computer information if it is Windows 10 or Windows 11.
It obtains the computer model, if it is a portable computer it will store the variable "PT".
It obtains the logged in user to save it in a variable, this does it collecting all the processes in execution and obtaining the first process that is not executed as "NT AUTHORITY SYSTEM".
It checks if the computer name exists. If it exists it adds a 1 to the end of the computer name.
Finally perform a Set the computer name.
Example: "W10USERNAMEOPT1".
