# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 08.11.2024

function Copy-FilesToCompare {
    param (
        [string]$ReferenceFolder,
        [string]$LiveFolder,
        [string]$ToCompareFolder
    )

    # Validate paths
    foreach ($folder in @($ReferenceFolder, $LiveFolder)) {
        if (-not (Test-Path -Path $folder)) {
            throw "Folder does not exist: $folder"
        }
    }

    if (-not (Test-Path $ToCompareFolder)) {
        md $ToCompareFolder
        Write-Host "Creating $ToCompareFolder-folder!"
    }

    # Get all files from the Reference folder recursively
    $referenceFiles = Get-ChildItem -Path $ReferenceFolder -Recurse -File

    foreach ($file in $referenceFiles) {
        # Create the destination path based on the reference file path
        $relativePath = $file.FullName.Substring($ReferenceFolder.Length)
        $destinationPath = Join-Path -Path $ToCompareFolder -ChildPath $relativePath

        # Check if the corresponding file exists in the Live folder
        $liveFilePath = Join-Path -Path $LiveFolder -ChildPath $relativePath

        if (Test-Path -Path $liveFilePath) {
            # Create the destination directory if it doesn't exist
            $destinationDir = Split-Path -Path $destinationPath -Parent
            if (-not (Test-Path -Path $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            # Copy the file to the destination
            Copy-Item -Path $liveFilePath -Destination $destinationPath -Force
            #Write-Output "Copied: $liveFilePath to $destinationPath"
        } else {
            Write-Output "File not found in live: $liveFilePath"
        }
    }

    Write-host "Mirrored the contents of $ReferenceFolder from $LiveFolder to $ToCompareFolder!" -ForegroundColor Yellow
    Write-Host "  "
}

#to rewrite
function Replace-PlaceholdersWithDefaultsOrCopy {
    param (
        [string]$Reference,         
        [string]$Scope         
    )

    if (-not (Test-Path $Scope)) {
        md $Scope
        Write-Host "Creating $scope-folder!"
    }

    $jsonContent = Get-PlaceHolders

    # Get all files recursively in the reference folder
    Write-Host "Getting files recursively from reference folder: $Reference" -ForegroundColor Green
    $referenceFiles = Get-ChildItem -Path $Reference -Recurse -File
    Write-Host "Found $($referenceFiles.Count) files in reference folder."

    # Iterate through each file in the reference folder
    foreach ($referenceFile in $referenceFiles) {
        $relativePath = $referenceFile.FullName.Substring($Reference.Length).TrimStart('\') # Get the relative path
        #Write-Host "Processing file: $relativePath from reference folder"

        # Construct the corresponding path in the scope folder
        $scopeFile = Join-Path -Path $Scope -ChildPath $relativePath																									

        # Ensure the directory exists for the scope path
        $scopeDir = Split-Path -Path $scopeFile -Parent
        if (-Not (Test-Path -Path $scopeDir)) {
            Write-Host "Creating directory: $scopeDir" -ForegroundColor Yellow
            New-Item -Path $scopeDir -ItemType Directory | Out-Null
        }

        # Get the content of the reference file
        $referenceContent = Get-Content -Path $referenceFile.FullName -Raw

        # Initialize a flag to check if placeholders exist
        $hasPlaceholders = $false

        # Check for placeholders and replace them if found
        foreach ($key in $jsonContent.PSObject.Properties.Name) {
            $placeholder = $key                  # e.g., PH_SOCIETE
            $defaultValue = $jsonContent.$key.default # Default value from JSON

            if ($referenceContent -match $placeholder) {
                $hasPlaceholders = $true
                # Replace the placeholder with the default value
																														 
                $referenceContent = $referenceContent -replace $placeholder, $defaultValue
            }
        }

        # If no placeholders are found, just copy the file
        if (-Not $hasPlaceholders) {
            Write-Host "No placeholders found in $relativePath. Copying file."
            Copy-Item -Path $referenceFile.FullName -Destination $scopeFile -Force
        } else {
            # Save the modified content to the scope folder
            Write-Host "Placeholders replaced. Saving modified file to: $scopeFile"

            Set-Content -Path $scopeFile -Value $referenceContent
        }
    }

    Write-Host "Finished preparing scope folder. Placeholders replaced where necessary!" -ForegroundColor Green
	$scopeFiles = Get-ChildItem -Path $Scope -Recurse -File
    Write-Host "Found $($scopeFiles.Count) files in scope folder." -ForegroundColor Green
    write-host "  "
}

function Compare-ReferencetoScope-GitDiff {
    param (
        [string]$Reference,         
        [string]$Scope,        
        [string]$outputFilePath,
        [string]$Module
    )

    $diffFilePath = "I:\modulus-toolkit\healthcheck\output\"+$Module+"\"
    if (-not (Test-Path -Path $diffFilePath)) {
        New-Item -ItemType Directory -Path $diffFilePath -Force | Out-Null
    }

    # Prepare the output file
    Write-Host "Preparing output file: $outputFilePath"
    if (Test-Path -Path $outputFilePath) {
        Write-Host "Output file already exists. Removing old file."
        Remove-Item -Path $outputFilePath
    }
    New-Item -Path $outputFilePath -ItemType File | Out-Null
    
    Write-Host "Output file created: $outputFilePath"

    # Get all files recursively in the reference folder
    Write-Host "Getting files recursively from reference folder: $Reference"
    $referenceFolder = Get-ChildItem -Path $Reference -Recurse -File
    Write-Host "Found $($referenceFolder.Count) files in reference folder."

    # Iterate through each file in the reference folder
    foreach ($referenceFile in $referenceFolder) {
        $relativePath = $referenceFile.FullName.Substring($Reference.Length).TrimStart('\') # Get the relative path of the file
        #Write-Host "Processing file: $relativePath"

        # Find the corresponding file in the scope folder
        $scopeFile = Join-Path -Path $Scope -ChildPath $relativePath
        #$scopeFile
        if (-Not (Test-Path -Path $scopeFile)) {
            Write-Host "File $relativePath not found in scope folder" -ForegroundColor Red
            Add-Content -Path $outputFilePath -Value "File $relativePath not found in scope folder`n"
            continue
        }

        # Compare files using Git diff
        $A = $referenceFile.fullname
        $B = $scopeFile
																												  		
        #$diffOutput = git diff --unified=0 --no-index --word-diff --color $referenceFile.fullname "$scopeFile"
        $diffOutput = git diff --unified=0 --no-index --word-diff  $A $B


        # Use an array to collect filtered output
        $filteredOutput = @()

        <#
        foreach ($line in $diffOutput) {
            if (-not $line.StartsWith('diff') -and
                -not $line.StartsWith('index') -and
                -not $line.StartsWith('---') -and
                -not $line.StartsWith('+++') -and
                -not [string]::IsNullOrWhiteSpace($line)) {
                # Add the line to the filtered output if it doesn't match any unwanted patterns
                $filteredOutput += $line
            }
        }
        #>

        if ($diffOutput.count -gt 4) {
            $filteredOutput = $diffOutput[4..($diffOutput.Length - 1)]
        }

        # Append filtered output to output file
        if ($filteredOutput.Count -gt 0) {
            # Save detailed diff for individual file
            <# previous file stuff
            $outputFile = $referenceFile.Name + "_diff.txt"
            $diffFilePath = "C:\Modulus\GitHub\modulus\00_scope\output\$outputFile"
            while (Test-Path $diffFilePath) { $diffFilePath = $diffFilePath + "_" }
            Set-Content -Path $diffFilePath -Value $diffOutput
            Write-Host "Differences found in $relativePath" -ForegroundColor Red															
            Add-Content -Path $outputFilePath -Value "Differences found in ${relativePath}:`n"
            Add-Content -Path $outputFilePath -Value $filteredOutput
            #>
            $outputFile = $referenceFile.Name
            $diffFilePath = "I:\modulus-toolkit\healthcheck\output\"+$Module+"\"
            while (Test-Path $diffFilePath$outputFile".diff" ){ $outputFile = $outputFile + "_" }
            Set-Content -Path $diffFilePath$outputFile".diff" -Value $diffOutput
            Write-Host "Differences found in $relativePath" -ForegroundColor Red															
            Add-Content -Path $outputFilePath -Value "Differences found in ${relativePath}:`n"
            Add-Content -Path $outputFilePath -Value $filteredOutput
        } else {
            Add-Content -Path $outputFilePath -Value "No differences found in ${relativePath}`n"
        }
    }

    Write-Host "Comparison complete. Differences logged to $outputFilePath" -ForegroundColor Green
}

#execution:
function Compare-MOD-Galaxis-Config {

    $APP_HN = Get-MOD-APP-hostname
    $dir    = "\\$APP_HN\D$\Galaxis"
    $module = "Galaxis"

    $healthcheckDir = (Get-PSConfig).directories.healthcheck
    $Live           = $healthcheckDir+"\live\$module"
    $Reference      = $healthcheckDir+"\reference\$module"
    $Scope          = $healthcheckDir+"\scope\$module"
    $outputFolder   = $healthcheckDir+"\output\$module"
    $outputFilePath = $healthcheckDir+"\output\"+$module+"_diff.txt"

    if (Test-Path $Live) {
        remove-item -path $Live -Recurse -Force 
    }

    if (Test-Path $Scope) {
        remove-item -path $Scope -Recurse -Force 
    }

    if (Test-Path $outputFolder) {
        remove-item -path $outputFolder -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
    #md $outputFolder | Out-Null

    #filling $live-folder in github
    Copy-FilesToCompare $Reference $dir $Live

    #mirror $scope folder by iterating through $Reference and replacing placeholders, recreating files or just copying if they do not have any placeholders
    Replace-PlaceholdersWithDefaultsOrCopy -Reference $Reference -Scope $Scope

    #do a diff between $live and $scope, outputting into $outputFolder
    Compare-ReferenceToScope-GitDiff $Scope $Live $outputFilePath $module
}

function Compare-MOD-CFCS-Config {

    $FS_HN  = Get-MOD-FS-hostname
    $dir    = "\\$FS_HN\D$\OnlineData\CRYSTAL.Net\CRYSTAL Floor Communication Service"
    $module = "CFCS"

    $healthcheckDir = (Get-PSConfig).directories.healthcheck
    $Live           = $healthcheckDir+"\live\$module"
    $Reference      = $healthcheckDir+"\reference\$module"
    $Scope          = $healthcheckDir+"\scope\$module"
    $outputFolder   = $healthcheckDir+"\output\$module"
    $outputFilePath = $healthcheckDir+"\output\"+$module+"_diff.txt"

    if (Test-Path $Live) {
        remove-item -path $Live -Recurse -Force 
    }

    if (Test-Path $Scope) {
        remove-item -path $Scope -Recurse -Force 
    }

    if (Test-Path $outputFolder) {
        remove-item -path $outputFolder -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
    #md $outputFolder | Out-Null

    #filling $live-folder in github
    Copy-FilesToCompare $Reference $dir $Live

    #mirror $scope folder by iterating through $Reference and replacing placeholders, recreating files or just copying if they do not have any placeholders
    Replace-PlaceholdersWithDefaultsOrCopy -Reference $Reference -Scope $Scope

    #do a diff between $live and $scope, outputting into $outputFolder
    Compare-ReferenceToScope-GitDiff $Scope $Live $outputFilePath $module
}

function Compare-MOD-CRYSTALControl-Config {

    $FS_HN  = Get-MOD-FS-hostname
    $dir    = "\\$FS_HN\D$\OnlineData\bin\control"
    $module = "CRYSTALControl"

    $healthcheckDir = (Get-PSConfig).directories.healthcheck
    $Live           = $healthcheckDir+"\live\$module"
    $Reference      = $healthcheckDir+"\reference\$module"
    $Scope          = $healthcheckDir+"\scope\$module"
    $outputFolder   = $healthcheckDir+"\output\$module"
    $outputFilePath = $healthcheckDir+"\output\"+$module+"_diff.txt"

    if (Test-Path $Live) {
        remove-item -path $Live -Recurse -Force 
    }

    if (Test-Path $Scope) {
        remove-item -path $Scope -Recurse -Force 
    }

    if (Test-Path $outputFolder) {
        remove-item -path $outputFolder -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
    #md $outputFolder | Out-Null

    #filling $live-folder in github
    Copy-FilesToCompare $Reference $dir $Live

    #mirror $scope folder by iterating through $Reference and replacing placeholders, recreating files or just copying if they do not have any placeholders
    Replace-PlaceholdersWithDefaultsOrCopy -Reference $Reference -Scope $Scope

    #do a diff between $live and $scope, outputting into $outputFolder
    Compare-ReferenceToScope-GitDiff $Scope $Live $outputFilePath $module
}

function Compare-MOD-JPApps-Config {

    $APP_HN  = Get-MOD-APP-hostname
    $dir     = "\\$APP_HN\C$\Program Files (x86)\Modulus"
    $module  = "JPApps"

    $healthcheckDir = (Get-PSConfig).directories.healthcheck
    $Live           = $healthcheckDir+"\live\$module"
    $Reference      = $healthcheckDir+"\reference\$module"
    $Scope          = $healthcheckDir+"\scope\$module"
    $outputFolder   = $healthcheckDir+"\output\$module"
    $outputFilePath = $healthcheckDir+"\output\"+$module+"_diff.txt"

    if (Test-Path $Live) {
        remove-item -path $Live -Recurse -Force 
    }

    if (Test-Path $Scope) {
        remove-item -path $Scope -Recurse -Force 
    }

    if (Test-Path $outputFolder) {
        remove-item -path $outputFolder -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
    #md $outputFolder | Out-Null

    #filling $live-folder in github
    Copy-FilesToCompare $Reference $dir $Live

    #mirror $scope folder by iterating through $Reference and replacing placeholders, recreating files or just copying if they do not have any placeholders
    Replace-PlaceholdersWithDefaultsOrCopy -Reference $Reference -Scope $Scope

    #do a diff between $live and $scope, outputting into $outputFolder
    Compare-ReferenceToScope-GitDiff $Scope $Live $outputFilePath $module
}

function Compare-MOD-FullReference {
    Compare-MOD-Galaxis-Config
    Compare-MOD-CFCS-Config
    Compare-MOD-CRYSTALControl-Config
    Compare-MOD-JPApps-Config
}