# Modulus Toolkit – Complete Function Reference

**Author:** Thomas Lukas  
**Last Updated:** 02.10.2025

This document provides an exhaustive overview of the functions defined in the Modulus Toolkit. It covers modules from core initialization and remote session management to deployment, Oracle administration, sysprep preparation, casino parameter changes, and healthchecks. (Some functions that serve as “background” or helper routines are also included.)

---

## Table of Contents

1. [Core Initialization & Environment Setup](#1)
2. [Remote Session & WinRM Configuration](#2)
3. [Server Information & Administration](#3)
4. [DevOps – Deployment & Maintenance](#4)
5. [Oracle Database Information & Administration](#5)
6. [Sysprep & System Reimaging](#6)
7. [CasinoChanger](#7)
8. [Healthcheck & Configuration Comparison](#8)
9. [Startup & Profile Integration](#9)
10. [Configuration Files & JSON Settings](#10)
11. [Additional Helper Functions](#11)
12. [Usage Guidelines & Best Practices](#12)

---

<a name="1"></a>

## 1. Core Initialization & Environment Setup  
*(Defined in `modules\1-core-init.psm1`)*

### Elevation & Profile Handling
- **Set-ElevatedState([bool]$Enable):**  
  Encrypts (when enabled) or deletes a token file to mark the toolkit as “elevated.”
- **Elevate-Toolkit:**  
  Prompts the user for a password; if correct, calls Set-ElevatedState and reloads the profile.
- **Suspend-Toolkit:**  
  Disables elevated state and reloads the profile.
- **Get-ElevatedState:**  
  Determines if the toolkit is running in elevated mode by checking for the presence of a special key or decrypting the token.
- **Reload-Profile:**  
  Invokes the PS7 profile (typically reloading the toolkit).

### Environment, Module, and Vault Initialization
- **Test-InternetConnection:**  
  Tests connectivity (e.g. via pinging www.google.com).
- **Initialize-Environment:**  
  Checks for the `MODULUS_SERVER` environment variable; if missing, prompts the user to choose a role (DB, APP, FS, 1VM, WS) and sets it.
- **Initialize-Modules([string[]]$Modules, [string]$ModulePath):**  
  Ensures required modules (e.g. PSIni, SecretManagement, SecretStore) are installed and imported.
- **Initialize-Vault([string]$Vault):**  
  Registers and configures the secret vault.
- **Initialize-Tools:**  
  Uses the helper `Find-Tool` to locate external utilities (e.g. 7-Zip, Notepad++) and creates global aliases.

### Credential Management
- **Set-CredentialInVault:**  
  Prompts the user for credentials and stores them securely in the vault.
- **Get-CredentialFromVault:**  
  Retrieves credentials from the vault (or prompts if they’re missing).
- **Remove-CredentialFromVault:**  
  Deletes a stored credential.
- **Enable-VaultWithoutPassword / Disable-VaultWithoutPassword:**  
  Adjusts the vault’s password requirement.

### Utility Functions & JSON Handling
- **Find-Tool:**  
  Searches common paths for a specified executable.
- **Update-Toolkit:**  
  Fetches and runs an update script from GitHub if an internet connection is available.
					   
													
- **Get-ModulePath, Get-PlaceHolders, Get-ENVConfig, Get-VMConfig, Get-DB-Credentials, Get-Components, Get-ReconfigurationScope:**  
  Functions that read JSON configuration files for placeholders, directory settings, environment variables, and component definitions.
- **Get-BinaryVersion:**  
  Retrieves version information from binary files.

### Directory Retrieval
- **Get-SourcesPath, Get-PrepPath, Get-GalaxisPath, Get-OnlinedataPath, Get-LogsPath:**  
  Extract the paths for source files, the staging (“prep”) folder, the live Galaxis folder, and logs from the JSON configuration.

---

<a name="2"></a>

## 2. Remote Session & WinRM Configuration  
*(Modules: Startup Scripts `1-pssessions.ps1`/`2-sysprep.ps1` and Module 3: `3-remote.psm1`)*

### Startup Scripts
- **1-pssessions.ps1:**  
  Checks if the remote session is running under PS7; if not, launches PS7 and loads the toolkit.
- **2-sysprep.ps1:**  
  Similar to the remote startup script but also triggers sysprep functions.

### WinRM & PSSession Configuration (Module 2)
- **Set-WinRM-tlukas / Set-WinRM-VM:**  
  Configures WinRM settings for specific network adapters (by setting network category to Private, updating TrustedHosts, and invoking quickconfig).
- **PSSession Configuration Block:**  
  Registers a custom PSSession configuration named `modulus-PS7` if not already present.
- **Open-DB-Session, Open-APP-Session, Open-FS-Session:**  
  Create remote sessions for DB, APP, and FS servers using credentials from the vault and the custom session configuration. They also map network drives and set the working directory.

---

<a name="3"></a>

## 3. Server Information & Administration  
*(Modules 3 & 4: `3-server-info.psm1` and `4-server-admin.psm1`)*

### Server Information (Module 3)
- **Get-MOD-ENVVARs:**  
  Lists current machine environment variables that match those defined in your JSON config.
- **Compare-MOD-ENVVARs:**  
  Compares live environment variables with desired values (with placeholder replacement) and outputs a status (MATCH, MISSING, MISMATCH).
- **Get-MOD-Network:**  
  Retrieves and outputs network adapter details (IP addresses, subnet masks, default gateways, DNS servers) for adapters specified in the JSON configuration.
- **Compare-MOD-Network:**  
  Compares live network settings with desired configuration values.
  
**IPv4 Network Helper Functions:**
- **Convert-PrefixLengthToSubnetMask:**  
  Converts a CIDR prefix (e.g. 24) into a standard subnet mask (e.g. 255.255.255.0).
- **Get-SubnetMaskPrefixLength:**  
  Computes the prefix length from a given subnet mask string.
- **Get-IPv4SubnetMaskForAdapter:**  
  Retrieves the prefix length (or subnet mask) for a specified adapter.
- **Get-IPv4DnsServersForAdapter:**  
  Lists the IPv4 DNS servers for a given network adapter.

### Server Administration (Module 4)
- **Initialize-VM (and its variants: Initialize-DB, Initialize-APP, Initialize-FS, Initialize-1VM, Initialize-WS):**  
  Set the machine’s hostname, update environment variables, map shared drives (I: and M:), and prompt for a reboot if necessary.
- **Restart-VMWithPrompt:**  
  Prompts the user for a reboot decision.
- **Set-SubstO-autostart:**  
  Checks for and installs `substO.bat` into the user’s startup folder.
- **Set-MOD-ENVVARs:**  
  Iterates over environment variable definitions from the JSON and sets them on the machine.
- **Rename-MOD-NICs:**  
  Renames network adapters to standardized names (e.g. OFFICE, FLOOR, MODULUS) based on how many adapters are detected.
- **Remove-MOD-Network:**  
  Removes IPv4 configurations (IP addresses, gateways, DNS) from network adapters.
- **Set-MOD-Network:**  
  Applies new IP settings and DNS addresses from the JSON configuration.
- **Manage-Disks:**  
  Performs backup and cleanup operations on disk volumes, clears read-only attributes, and brings offline disks online.

---

<a name="4"></a>

## 4. DevOps – Deployment & Maintenance  
*(Modules 5 & 6: `5-devops-info.psm1` and `6-devops-admin.psm1`)*

The DevOps chapter is designed to help with the staging ("prep") and deployment ("deploy") of updates and maintenance operations for the Galaxis system. It includes functions for cleaning up temporary folders, preparing new releases from source archives, and deploying them to live directories.

### DevOps Info (Module 5)
- **Clear-PrepDir:**  
  Clears out the staging (“prep”) folder to remove any previously prepared files.
- **Clear-LogsDir:**  
  Clears out the logs directory.

### Prep Functions – Staging New Releases  
These functions extract new binaries and configuration files from compressed archives stored in the "sources" folder. They then rearrange the extracted files into a structure expected by the live system.

- **Prep-Galaxis:**  
  Searches for a 7z archive (matching patterns such as `Galaxis*Executable*.7z`) in the sources directory and extracts it into a subfolder within the prep directory (e.g. `Executable only`). Post-extraction, it moves files from deeper subdirectories (like `Server\Galaxis\`) into the correct target folder and cleans up any extraneous directories (such as Docker or installation folders) that are not needed for deployment.
- **Prep-SYSTM:**  
  Has two sub-functions:
  - **Prep-SYSTM-Executables:**  
    Extracts SYSTM executable updates from archives (e.g. matching `SYSTM*Executable*.7z`) and rearranges the file structure for deployment.
  - **Prep-SYSTM-Config:**  
    Extracts configuration file updates for SYSTM from archives (e.g. matching `SYSTM*Config*.7z`) and similarly moves them to the proper directory.
- **Prep-Other:**  
  Handles other files not categorized as executables or configuration files by extracting them from archives matching patterns like `Galaxis*Other*.7z`.
- **Prep-Config:**  
  Specifically extracts configuration updates (archives matching `Galaxis*Config*.7z`), then moves and cleans up the extracted files.
- **Prep-Install / Prep-Web / Prep-CRYSTALControl / Prep-MBoxUI / Prep-PlayWatch:**  
  Similar in concept, these functions extract and stage installer packages, web modules, Crystal Control updates, MBoxUI, and PlayWatch packages respectively. Each uses the common helper function `Extract-7ZipFile` to extract the relevant 7z archives into designated subdirectories within the prep folder and then performs any necessary post-extraction cleanup (such as moving files to flatten the folder structure or removing extraneous folders).

### Deploy Functions – Rolling Out Updates to Live  
Once files have been staged in the prep folder, the deploy functions copy them into the live system directories (e.g., `D:\Galaxis` or `D:\OnlineData`).

- **Deploy-Galaxis:**  
  Uses Robocopy to mirror the contents of the `Executable only`, `Config only`, and `Other` folders from the prep directory to the live Galaxis installation folder. It employs parameters such as `/IM /IS /IT` (to force overwrite) and creates a detailed log file in the logs directory.
- **Deploy-SYSTM:**  
  Contains sub-functions:
  - **Deploy-SYSTM-Executables:**  
    Copies SYSTM executable files from the staging area to the live Galaxis folder using Robocopy, with parameters that force an overwrite.
  - **Deploy-SYSTM-Config:**  
    Deploys configuration files for SYSTM, typically using parameters (e.g. `/XC /XN /XO`) that only copy non-existing or outdated files.
- **Deploy-Web, Deploy-PlayWatch, Deploy-CRYSTALControl, etc.:**  
  These functions similarly use Robocopy to copy staged files (from their respective prep subdirectories) into their live locations. They generate log files, verify the outcome, and provide on-screen output to allow technicians to verify that the correct files have been deployed.

Each deploy function typically:
  - Determines the source folder from the prep directory (using filtering based on folder names such as "Executables", "Config", etc.).
  - Uses Robocopy with appropriate options (which might vary to either force overwrite or only update non-existing files) to copy files into the target live directory.
  - Writes a log file (with a timestamp in the filename) into the logs directory.
  - Displays the tail end of the log file so that the operator can quickly verify the results.

---

## 4. (Expanded) DevOps – Deployment & Maintenance

This chapter focuses on preparing (staging) and deploying updates. The functions are divided into two primary groups:

### Prep Functions – Staging New Releases

The **prep functions** extract new releases from compressed archives stored in the *sources* directory. They use the common helper `Extract-7ZipFile` to extract files that match a specific pattern (e.g. `Galaxis*Executable*.7z`, `SYSTM*Config*.7z`, etc.). Once extracted, the functions often perform additional operations:
- **Moving Files:**  
  Files extracted into a nested folder (for example, `Server\Galaxis\`) are moved up to a designated folder (e.g. `Executable only` or `Config only`) to ensure a flat folder structure.
- **Cleanup:**  
  Unnecessary directories (such as Docker subfolders or batch installer directories) are removed to leave only the relevant files for deployment.
- **Specific Tasks:**  
  Functions such as `Prep-Galaxis` handle the primary Galaxis executables; `Prep-SYSTM` deals with both executables and configuration files specific to the SYSTM component; `Prep-MBoxUI` and `Prep-PlayWatch` similarly stage updates for their respective modules.

**Key Prep Functions:**
- **Prep-Galaxis:**  
  Extracts and stages Galaxis executables. After extraction, it rearranges the files into the expected folder structure and removes any unnecessary subdirectories.
- **Prep-SYSTM:**  
  Divided into `Prep-SYSTM-Executables` (for binary updates) and `Prep-SYSTM-Config` (for configuration updates). Both functions ensure that the files are organized correctly in the prep directory.
- **Prep-Other & Prep-Config:**  
  These functions stage miscellaneous files (which do not fall under executables) and configuration files respectively.
- **Prep-Install, Prep-Web, Prep-CRYSTALControl, Prep-MBoxUI, Prep-PlayWatch:**  
  Specialized functions for staging installer packages, web modules, and updates for specific applications. They all follow the same pattern: extract using a defined file pattern, move the files into the proper subdirectory, and perform cleanup operations.

### Deploy Functions – Rolling Out Updates to Live

After the new packages are staged in the prep folder, the **deploy functions** copy them from the staging area to the live system directories using Robocopy.

- **Deploy-Galaxis:**  
  Copies the contents from the prep folders (for executables, configuration, and other files) to the live Galaxis installation directory (typically `D:\Galaxis`). It uses options like `/IM /IS /IT` (which force overwrite) and logs detailed output to a log file.
- **Deploy-SYSTM:**  
  Contains sub-functions for executables and configuration. They use Robocopy flags such as `/XC /XN /XO` (to copy only newer or non-existent files) when appropriate.
- **Deploy-Web, Deploy-PlayWatch, Deploy-CRYSTALControl, etc.:**  
  These functions are tailored for specific components. They use similar Robocopy commands, ensuring that the updated files are mirrored from the staging directory to their live locations (e.g., in `D:\OnlineData` or other designated paths).

Each deploy function typically:
- Determines the package folder within the prep directory by filtering with a pattern.
- Uses Robocopy to mirror or update the live folder.
- Generates a log file (named with a timestamp) in the logs directory.
- Displays the final part of the log for quick verification.

---

<a name="5"></a>

## 5. Oracle Database Information & Administration  
*(Modules 7 & 8: `7-oracle-info.psm1` and `8-oracle-admin.psm1`)*

### Oracle Information (Module 7)
- **Show-GLX-oracle-patch-version / Show-JKP-oracle-patch-version:**  
  Executes `oracle_patch_version.sql` to display the current OPatch version and Oracle patch information.
- **Show-GLX-mod-users / Show-JKP-mod-users:**  
  Lists modulus-specific Oracle users by executing SQL scripts.
- **Show-GLX-betabli:**  
  Executes a SQL script to display entries in the GALAXIS betabli table.
- **Show-GLX-dba-users:**  
  *(Marked as TODO)* Intended to list DBA-specific users.

### Oracle Administration (Module 8)
- **Set-Oracle-Config:**  
  Updates the `tnsnames.ora` file for the Oracle Client by replacing hostnames for entries like GLX and JKP.
- **Execute-GalaxisOracle-jar:**  
  Runs a Java utility (`galaxisoracle.jar`) using `loadjava` to update Oracle objects.
- **Set-GLX-default-profile / Set-JKP-default-profile:**  
  Executes SQL scripts to set the default Oracle profiles.
- **Set-JKP-DB-version-1050:**  
  Disables triggers, updates database tables, and then re-enables triggers to update versions in the JKP schema.
- **Export/Import Helpers:**  
  - **Prep-GLX-EXP_DIR, Prep-JKP-EXP_DIR, Execute-Full-Export, Execute-Full-Import:**  
    Prepare export directories and perform full database export/import using Oracle Data Pump.
- **Privilege Spooling Functions:**  
  - **Spool-GLX-sys-privileges, Spool-JKP-sys-privileges, Spool-GLX-table-privileges, Spool-JKP-table-privileges:**  
    Run SQL scripts that spool system and table privileges.
- **Compile Functions:**  
  - **Compile-GLX-Serial, Compile-JKP-Serial, Compile-GLX-Invalids, Compile-JKP-Invalids:**  
    Recompile serial numbers or list invalid objects in the GLX and JKP databases.

---

<a name="6"></a>

## 6. Sysprep & System Reimaging  
*(Module 9: `9-sysprep.psm1`)*

This module coordinates the process for preparing a machine for sysprep.

### Status Management
- **Get-Sysprep-Status / Set-Sysprep-Status:**  
  Read and write the sysprep status from/to a JSON configuration file (`sysprep.json`).

### Pre-Sysprep Preparations
- **Set-ServicesToManual:**  
  Stops critical services (GalaxisStartupService, RabbitMQ, pinit, nginx) and sets their startup type to Manual so they don’t restart automatically.
- **Check-LegacyIssues:**  
  Checks for legacy Windows Appx packages (e.g. Xbox, Cortana) that might interfere with sysprep.
- **Check-Registry:**  
  Verifies and fixes registry settings required for sysprep (e.g. `SysprepStatus`, `SkipRearm`).
- **Reintall-MSDTC:**  
  Uninstalls and reinstalls MSDTC.
- **Disk & NIC Preparations:**  
  - **Manage-Disks:**  
    Clears and reactivates disk volumes.
  - **Rename-MOD-NICs, Remove-MOD-Network, Set-MOD-Network:**  
    Renames network adapters, removes old IP configurations, and applies new settings.
- **Sysprep User & Defender Handling:**
  - **Create-SysprepUser / Delete-SysprepUser:**  
    Creates and later removes a temporary user used during sysprep.
  - **Disable-DnFW / Enable-DnFW:**  
    Disables (and later re-enables) Windows Defender real-time monitoring and firewall settings.
- **Sysprep:**  
  Invokes the Windows sysprep utility with an unattended XML file.
- **Modulus-Sysprep:**  
  The main coordination function that calls the above steps in order.

---

<a name="7"></a>

## 7. CasinoChanger  
*(Module 10: `10-casinochanger.psm1`)*

This module supports interactive changes to casino-specific settings in the database.

- **Open-CasinoChanger-Help:**  
  Opens the CasinoChanger help manual in a web browser.
- **Setup-CasinoChanger:**  
  Executes a SQL script (`CC_setup.sql`) to prepare the database for casino parameter changes.
- **Cleanup-CasinoChanger:**  
  Executes a SQL script (`CC_cleanup.sql`) to revert or clean up changes after execution.
- **Execute-CasinoChanger:**  
  Prompts the user for the old casino ID, reads new casino settings (such as casino ID, corporate codes, long and short names) from the JSON configuration, constructs a PL/SQL block that calls the `MOD_CasinoChanger` procedure, executes it, and then cleans up.

---

<a name="8"></a>

## 8. Healthcheck & Configuration Comparison  
*(Module 11: `11-healthcheck.psm1`)*

These functions help ensure that live configuration files match the expected (reference) versions.

- **Copy-FilesToCompare:**  
  Copies files from a live directory (e.g. Galaxis folder) into a “to compare” directory.
- **Replace-PlaceholdersWithDefaultsOrCopy:**  
  Processes reference files by replacing placeholders (using defaults defined in a JSON file) and copies them into a “scope” folder.
- **Compare-ReferenceToScope-GitDiff:**  
  Uses Git diff in no-index mode to compare files from the “scope” folder against the live files, logging differences to an output file.
- **High-Level Comparison Functions:**  
  - **Compare-MOD-Galaxis-Config, Compare-MOD-CFCS-Config, Compare-MOD-CRYSTALControl-Config, Compare-MOD-JPApps-Config:**  
    Wrap the above steps to compare configurations for different modules.
  - **Compare-MOD-FullReference:**  
    Runs all individual comparisons in sequence.

---

<a name="9"></a>

## 9. Startup & Profile Integration

### Startup Scripts
- **1-pssessions.ps1 & 2-sysprep.ps1:**  
  Ensure that remote sessions are started under PowerShell 7 and that the toolkit (and sysprep functions, if applicable) are loaded.

### PowerShell Profile
- **Microsoft.PowerShell_profile.ps1:**  
  Checks if the current user is allowed to use the toolkit (based on a whitelist), removes any previous instances of the module, and re-imports the toolkit if the key file (`TK.key`) exists. It also calls `Assert-MOD-Components` to verify that all required components are present.

---

<a name="10"></a>

## 10. Configuration Files & JSON Settings

The toolkit uses several JSON configuration files (located in the `config` folder):

- **envvars.json, scope.json:**  
  Contain definitions for directories, environment variables, network settings, and server roles.
- **components.json:**  
  Lists all the components (modules, tools, databases) along with their paths, binary locations, and versioning information.
- **sysprep.json:**  
  Tracks the status of various steps required for sysprep.
- **Unattend.xml:**  
  Used by sysprep for performing an unattended installation.

---

<a name="11"></a>

## 11. Additional Helper Functions

These functions support logging, file operations, and user confirmations:

- **Confirm-Action:**  
  Prompts the user with a warning and requires a specific confirmation text to proceed.
- **Get-DatabaseCredentials / Set-DatabaseCredentials:**  
  Retrieve or store credentials for database access using the SecretManagement vault.
- **Execute-SQL-Script:**  
  A wrapper that runs SQL scripts via SQL*Plus, handling parameters like credentials, database name, script path, and additional arguments.
- **Spool-*/Import-*/Export-* Functions:**  
  Functions such as `Spool-GLX-sys-privileges`, `Spool-JKP-table-privileges`, `Export-GLX-Full`, `Import-JKP-Full`, etc. to run and spool output from SQL scripts.
- **Compile Functions:**  
  Functions like `Compile-GLX-Serial`, `Compile-JKP-Invalids` that execute SQL scripts to recompile or check for invalid database objects.
- **Git Diff Based Comparison Helpers:**  
  Functions in the healthcheck module that leverage Git diff for file comparisons.

---

<a name="12"></a>

## 12. Usage Guidelines & Best Practices

1. **Importing the Toolkit:**  
   - Use PowerShell 7 and log in as an allowed user (e.g. ThomasLukas, Administrator, SysprepUser).  
   - The custom profile automatically imports the toolkit if `TK.key` is present.
2. **Remote Session Management:**  
   - Use the provided startup scripts and remote session functions (e.g. `Open-DB-Session`) to manage remote connections.
3. **Deployments & Updates:**  
   - Utilize the prep and deploy functions (see DevOps chapter) to stage and roll out updates.  
   - Always create backups of current configurations using backup functions (e.g. `Backup-GLXDir`).
4. **Oracle Operations:**  
   - Use the Oracle modules to check patch versions, update tnsnames.ora, export/import full schemas, and spool privileges.
5. **Sysprep Process:**  
   - Run `Modulus-Sysprep` (or use the sysprep startup script) to prepare a system for imaging.  
   - Ensure that legacy issues, registry settings, disk configurations, and NIC settings are correct before sysprep.
6. **CasinoChanger:**  
   - When `CC.key` is available, run `Execute-CasinoChanger` to update casino parameters interactively.
7. **Healthchecks:**  
   - Run the healthcheck functions to verify that live configurations match the expected (reference) versions.
8. **Security:**  
   - Keep key files (e.g. TK.key, SP.key, CC.key) secure and restrict access to the credential vault.
9. **Logging & Troubleshooting:**  
   - Check log files in the directories specified by your JSON configuration for troubleshooting information.

---

*This exhaustive document serves as a comprehensive reference to all functions in the Modulus Toolkit. As you refine your usage, you may choose to move background and helper functions into an appendix or a separate document.*

---

