#tlukas, 08.11.2024

#write-host "Loading 11-healthcheck.psm1!" -ForegroundColor Green

#region --- diff function
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
#endregion

#region --- component checks
function Compare-MOD-Galaxis-Config {
    $module = "Galaxis"
    $healthcheckDir = Get-HealthcheckPath # Assuming this returns 'I:\modulus-toolkit\healthcheck\'
    
    $TemplatesPath = "I:\modulus-toolkit\prep\GALAXIS Config only"
    $ShouldBePath = "I:\modulus-toolkit\prep\GALAXIS Config only replaced"
    $LivePath = "D:\Galaxis" 
    
    #Paths for outputting the comparison results
    $outputFolder = "$($healthcheckDir)\output\$module"
    $outputFilePath = "$($healthcheckDir)\output\" + $module + "_diff.diff"

    #Clean Up and Prepare Output Directory
    Write-Host "Cleaning up previous output directory for module: $module" -ForegroundColor Yellow
    if (Test-Path $outputFolder) { Remove-Item -Path $outputFolder -Recurse -Force }
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

    #Generate the "Should Be" State (Reconfigured Scope)
    Write-Host "Generating 'Should Be' state in $ShouldBePath..." -ForegroundColor Cyan
    
    #Ensure the output directory for the replaced files is clean/created
    if (Test-Path $ShouldBePath) { Remove-Item -Path $ShouldBePath -Recurse -Force }
    New-Item -ItemType Directory -Path $ShouldBePath -Force | Out-Null
    
    # Run the placeholder replacement logic
    Invoke-PlaceholderReplacement `
        -BasePath $TemplatesPath `
        -Include '*' `
        -OutputRoot $ShouldBePath `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets 

    #Perform the Comparison (Reconfigured Scope vs. Live Files)
    Write-Host "Starting Git Diff comparison: Should Be ($ShouldBePath) vs. Live ($LivePath)" -ForegroundColor Green
    
    #We use $ShouldBePath as the Reference and $LivePath (D:\Galaxis) as the Scope.
    #The output will be directed to the specified file and the output folder.
    Compare-ReferenceToScope-GitDiff `
        -Reference $ShouldBePath `
        -Scope $LivePath `
        -outputFilePath $outputFilePath `
        -Module $module

    Write-Host "Configuration comparison for $module completed. See output files in $outputFolder and $outputFilePath" -ForegroundColor Green
}

function Compare-MOD-CFCS-Config {
    write-log "not implemented yet, TODO" WARNING
    Return;

    $module = "CFCS"
    $healthcheckDir = Get-HealthcheckPath # Assuming this returns 'I:\modulus-toolkit\healthcheck\'
    
    $TemplatesPath = "I:\modulus-toolkit\prep\GALAXIS Config only"
    $ShouldBePath = "I:\modulus-toolkit\prep\GALAXIS Config only replaced"
    $LivePath = "D:\Galaxis" 
    
    #Paths for outputting the comparison results
    $outputFolder = "$($healthcheckDir)\output\$module"
    $outputFilePath = "$($healthcheckDir)\output\" + $module + "_diff.txt"

    #Clean Up and Prepare Output Directory
    Write-Host "Cleaning up previous output directory for module: $module" -ForegroundColor Yellow
    if (Test-Path $outputFolder) { Remove-Item -Path $outputFolder -Recurse -Force }
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

    #Generate the "Should Be" State (Reconfigured Scope)
    Write-Host "Generating 'Should Be' state in $ShouldBePath..." -ForegroundColor Cyan
    
    #Ensure the output directory for the replaced files is clean/created
    if (Test-Path $ShouldBePath) { Remove-Item -Path $ShouldBePath -Recurse -Force }
    New-Item -ItemType Directory -Path $ShouldBePath -Force | Out-Null
    
    # Run the placeholder replacement logic
    Invoke-PlaceholderReplacement `
        -BasePath $TemplatesPath `
        -Include '*' `
        -OutputRoot $ShouldBePath `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets 

    #Perform the Comparison (Reconfigured Scope vs. Live Files)
    Write-Host "Starting Git Diff comparison: Should Be ($ShouldBePath) vs. Live ($LivePath)" -ForegroundColor Green
    
    #We use $ShouldBePath as the Reference and $LivePath (D:\Galaxis) as the Scope.
    #The output will be directed to the specified file and the output folder.
    Compare-ReferenceToScope-GitDiff `
        -Reference $ShouldBePath `
        -Scope $LivePath `
        -outputFilePath $outputFilePath `
        -Module $module

    Write-Host "Configuration comparison for $module completed. See output files in $outputFolder and $outputFilePath" -ForegroundColor Green
}

function Compare-MOD-CRYSTALControl-Config {
    write-log "not implemented yet, TODO" WARNING
    Return; #TODO

    $module = "CFCS"
    $healthcheckDir = Get-HealthcheckPath # Assuming this returns 'I:\modulus-toolkit\healthcheck\'
    
    $TemplatesPath = "I:\modulus-toolkit\prep\GALAXIS Config only"
    $ShouldBePath = "I:\modulus-toolkit\prep\GALAXIS Config only replaced"
    $LivePath = "D:\Galaxis" 
    
    #Paths for outputting the comparison results
    $outputFolder = "$($healthcheckDir)\output\$module"
    $outputFilePath = "$($healthcheckDir)\output\" + $module + "_diff.txt"

    #Clean Up and Prepare Output Directory
    Write-Host "Cleaning up previous output directory for module: $module" -ForegroundColor Yellow
    if (Test-Path $outputFolder) { Remove-Item -Path $outputFolder -Recurse -Force }
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

    #Generate the "Should Be" State (Reconfigured Scope)
    Write-Host "Generating 'Should Be' state in $ShouldBePath..." -ForegroundColor Cyan
    
    #Ensure the output directory for the replaced files is clean/created
    if (Test-Path $ShouldBePath) { Remove-Item -Path $ShouldBePath -Recurse -Force }
    New-Item -ItemType Directory -Path $ShouldBePath -Force | Out-Null
    
    # Run the placeholder replacement logic
    Invoke-PlaceholderReplacement `
        -BasePath $TemplatesPath `
        -Include '*' `
        -OutputRoot $ShouldBePath `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets 

    #Perform the Comparison (Reconfigured Scope vs. Live Files)
    Write-Host "Starting Git Diff comparison: Should Be ($ShouldBePath) vs. Live ($LivePath)" -ForegroundColor Green
    
    #We use $ShouldBePath as the Reference and $LivePath (D:\Galaxis) as the Scope.
    #The output will be directed to the specified file and the output folder.
    Compare-ReferenceToScope-GitDiff `
        -Reference $ShouldBePath `
        -Scope $LivePath `
        -outputFilePath $outputFilePath `
        -Module $module

    Write-Host "Configuration comparison for $module completed. See output files in $outputFolder and $outputFilePath" -ForegroundColor Green
}

function Compare-MOD-JPApps-Config {
    write-log "not implemented yet, TODO" WARNING
    Return; #TODO

    $module = "CFCS"
    $healthcheckDir = Get-HealthcheckPath # Assuming this returns 'I:\modulus-toolkit\healthcheck\'
    
    $TemplatesPath = "I:\modulus-toolkit\prep\GALAXIS Config only"
    $ShouldBePath = "I:\modulus-toolkit\prep\GALAXIS Config only replaced"
    $LivePath = "D:\Galaxis" 
    
    #Paths for outputting the comparison results
    $outputFolder = "$($healthcheckDir)\output\$module"
    $outputFilePath = "$($healthcheckDir)\output\" + $module + "_diff.txt"

    #Clean Up and Prepare Output Directory
    Write-Host "Cleaning up previous output directory for module: $module" -ForegroundColor Yellow
    if (Test-Path $outputFolder) { Remove-Item -Path $outputFolder -Recurse -Force }
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

    #Generate the "Should Be" State (Reconfigured Scope)
    Write-Host "Generating 'Should Be' state in $ShouldBePath..." -ForegroundColor Cyan
    
    #Ensure the output directory for the replaced files is clean/created
    if (Test-Path $ShouldBePath) { Remove-Item -Path $ShouldBePath -Recurse -Force }
    New-Item -ItemType Directory -Path $ShouldBePath -Force | Out-Null
    
    # Run the placeholder replacement logic
    Invoke-PlaceholderReplacement `
        -BasePath $TemplatesPath `
        -Include '*' `
        -OutputRoot $ShouldBePath `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets 

    #Perform the Comparison (Reconfigured Scope vs. Live Files)
    Write-Host "Starting Git Diff comparison: Should Be ($ShouldBePath) vs. Live ($LivePath)" -ForegroundColor Green
    
    #We use $ShouldBePath as the Reference and $LivePath (D:\Galaxis) as the Scope.
    #The output will be directed to the specified file and the output folder.
    Compare-ReferenceToScope-GitDiff `
        -Reference $ShouldBePath `
        -Scope $LivePath `
        -outputFilePath $outputFilePath `
        -Module $module

    Write-Host "Configuration comparison for $module completed. See output files in $outputFolder and $outputFilePath" -ForegroundColor Green
}

function Compare-MOD-FullReference {
    Return; #TODO
    Compare-MOD-Galaxis-Config
    Compare-MOD-CFCS-Config
    Compare-MOD-CRYSTALControl-Config
    Compare-MOD-JPApps-Config
}
#endregion


#Export-ModuleMember -Function * -Alias * -Variable *