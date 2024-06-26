# OpenCBMGUI by dotBtty
# See https://github.com/tonnyrh/OpenCBMGUI

# Import the necessary assembly for Windows Forms
Add-Type -AssemblyName System.Windows.Forms

# Import the OpenCBMGUI module
# Import-Module -Name "$PSScriptRoot\OpenCBMGUI.psm1"

# Define the root path for OpenCBM
$rootPath = "C:\Program Files\opencbm"  # Using a fixed path for clarity

# Define a debug flag
$debug = $false


# Function to create and show an input box dialog for renaming a file
function Show-InputBox {
    param (
        [string]$title,
        [string]$promptText,
        [string]$defaultValue
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.Size = New-Object System.Drawing.Size(400, 150)
    $form.StartPosition = "CenterParent"

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $promptText
    $label.Size = New-Object System.Drawing.Size(360, 20)
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Text = $defaultValue
    $textBox.Size = New-Object System.Drawing.Size(360, 20)
    $textBox.Location = New-Object System.Drawing.Point(10, 40)
    $form.Controls.Add($textBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Size = New-Object System.Drawing.Size(75, 30)
    $okButton.Location = New-Object System.Drawing.Point(295, 70)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Size = New-Object System.Drawing.Size(75, 30)
    $cancelButton.Location = New-Object System.Drawing.Point(210, 70)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    $dialogResult = $form.ShowDialog()

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text
    } else {
        return $null
    }
}


# Function to rename a file on the Commodore drive
function Rename-File {
    param (
        [int]$deviceID,
        [string]$oldFileName,
        [string]$newFileName
    )

    $oldFileName=$oldFileName.ToUpper()
    $newFileName=$newFileName.ToUpper()

    $command = "`"$rootPath\cbmctrl`" command $deviceID `"R0:$newFileName=$oldFileName`""
    $statusLabel.Text = "Status: Renaming file..."
    $output = RunCommand -command $command
    UpdateStatus -command $command -status "File renamed" -result $output
}


#Function to update status and last run command
function UpdateStatus {
    param (
        [string]$command,
        [string]$status,
        [string]$result
    )
    $lastRunTextBox.Text = $command
    $lastResultTextBox.Text = $result
    $statusLabel.Text = "Status: " + $status
    Add-LogEntry -command $command -result $result -status $status
}

# Function to add log entry
function Add-LogEntry {
    param (
        [string]$command,
        [string]$result,
        [string]$status
    )
    $logEntry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Command = $command
        Result = $result
        Status = $status
    }
    $logEntry | Export-Csv -Append -NoTypeInformation -Path "OpenCBMGUI.log"
}

# Function to run a command using cmd.exe
function RunCommand {
    param (
        [string]$command
    )
    # Set up the file path
    $tempFilePath = [System.IO.Path]::Combine($env:TEMP, "opencbmgui.tmp")

    # Ensure the file is deleted if it exists
    if (Test-Path $tempFilePath) {
        Remove-Item $tempFilePath -Force
    }

    # Pipe the output of the command to the file, including errors
    $cmd = "cmd.exe /c '$command' 2>&1 > '$tempFilePath'"
    Invoke-Expression -Command $cmd

    # Read the content of the file into the $output variable
    $output = Get-Content $tempFilePath | Out-String

    # Return the output
    return $output
}

# Function to detect drive and select the corresponding radio button
function DetectDrive {
    $command = "`"$rootPath\cbmctrl`" detect"
    $statusLabel.Text = "Status: Detecting..."
    $output = RunCommand -command $command
    UpdateStatus -command $command -status "Detected ID" -result $output # Update status with raw output for debugging
    $detectedID = $null
    try {
        $output.Split("`n") | ForEach-Object {
            Debug-Output "Processing line: '$_'" # Debug output
            if ($_ -match " (\d{1,2}):") {
                $detectedID = $matches[1].Trim()
                Debug-Output "Detected ID: $detectedID" # Debug output
                if ($radioButtons.ContainsKey([int]$detectedID)) {
                    $radioButtons[[int]$detectedID].Checked = $true
                }
            }
        }
    }
    catch {
        UpdateStatus -command $command -status "Error detecting device ID." -result $output
        Debug-Output "Error during detection: $_" # Debug output
        return
    }
    if ($detectedID -eq $null) {
        UpdateStatus -command $command -status "No valid device ID detected." -result $output
        Debug-Output "No valid device ID detected." # Debug output
    } else {
        UpdateStatus -command $command -status "Detected id $($detectedID)" -result $output
        Debug-Output "Final detected ID: $detectedID" # Debug output
    }
}

#Function to get the selected device ID
function GetSelectedDeviceID {
    foreach ($id in $radioButtons.Keys) {
        if ($radioButtons[$id].Checked) {
            return $id
        }
    }
}

# Function to parse directory output
function ParseDirectoryOutput {
    param (
        [string]$output
    )
    $lines = $output -split "`n"
    $title = [regex]::Match($lines[0], '".*?"').Value.Trim('"')
    $freeBlocks = ($lines[-2] -split ' ')[0].Trim()
    $entries = @()

    for ($i = 1; $i -lt $lines.Length - 2; $i++) {
        if ($lines[$i] -match '^\s*(\d+)\s+"(.+?)"\*?\s*(prg|seq|rel|usr|del)') {
            $entries += [PSCustomObject]@{
                Size = $matches[1]
                Filename = $matches[2]
                Extension = $matches[3]
            }
        }
    }

    return [PSCustomObject]@{
        Title = $title
        FreeBlocks = $freeBlocks
        Entries = $entries
    }
}



# Function to populate the directory DataGridView
function PopulateDirectoryGrid {
    param (
        [string]$output
    )

    $parsedOutput = ParseDirectoryOutput -output $output

    # Clear existing rows and columns
    $directoryGrid.Rows.Clear()
    $directoryGrid.Columns.Clear()

    # Add columns
    $directoryGrid.Columns.Add("Size", "Size")
    $directoryGrid.Columns.Add("Filename", "Filename")
    $directoryGrid.Columns.Add("Extension", "Extension")

    # Add rows
    foreach ($entry in $parsedOutput.Entries) {
        $directoryGrid.Rows.Add($entry.Size, $entry.Filename, $entry.Extension)
    }

    # Update the title and free blocks labels
    $diskTitleLabel.Text = "Disk Title: $($parsedOutput.Title)"
    $freeBlocksLabel.Text = "Free Blocks: $($parsedOutput.FreeBlocks)"
}
# Function to print debug output if the debug flag is set
function Debug-Output {
    param (
        [string]$message
    )
    if ($debug) {
        Write-Host $message
    }
}




# Create a new form
$form = New-Object System.Windows.Forms.Form
$form.Text = "OpenCBM GUI v0.4 by dotBtty"
$form.Size = New-Object System.Drawing.Size(1200, 900)  # Increase the size of the form
$form.StartPosition = "CenterScreen"

# Set the font to Courier New for an old-fashioned console look
$font = New-Object System.Drawing.Font("Courier New", 8)

# Create a menu strip
$menuStrip = New-Object System.Windows.Forms.MenuStrip

# Create File menu
$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem("File")
$menuStrip.Items.Add($fileMenu)

# Create Action menu
$actionMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Action")
$menuStrip.Items.Add($actionMenu)

# Create About menu
$aboutMenu = New-Object System.Windows.Forms.ToolStripMenuItem("About")
$menuStrip.Items.Add($aboutMenu)

# Add Copy Method to File menu
$copyMethodLabel = New-Object System.Windows.Forms.ToolStripMenuItem("Copy Method")
$copyMethodComboBox = New-Object System.Windows.Forms.ToolStripComboBox
$copyMethodComboBox.Items.AddRange(@("d64copy", "d82copy", "imgcopy", "cbmcopy"))
$copyMethodComboBox.SelectedIndex = 0
$copyMethodLabel.DropDownItems.Add($copyMethodComboBox)
$fileMenu.DropDownItems.Add($copyMethodLabel)

# Add Transfer to Drive to File menu
$transferToDriveMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("Transfer to Drive")
$transferToDriveMenuItem.Add_Click({
    $deviceID = GetSelectedDeviceID
    $copyMethod = $copyMethodComboBox.SelectedItem
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog

    # Set file dialog filter based on selected copy method
    switch ($copyMethod) {
        "d64copy" { $openFileDialog.Filter = "D64 files (*.d64)|*.d64" }
        "d82copy" { $openFileDialog.Filter = "D80 and D82 files (*.d80;*.d82)|*.d80;*.d82" }
        "imgcopy" { $openFileDialog.Filter = "Image files (*.d64;*.d71;*.d80;*.d81;*.d82)|*.d64;*.d71;*.d80;*.d81;*.d82" }
        "cbmcopy" { $openFileDialog.Filter = "Raw, PC64 (P00) and T64 files (*.prg;*.p00;*.t64;*.bin)|*.prg;*.p00;*.t64;*.bin|All files (*.*)|*.*" }
    }

    if ($openFileDialog.ShowDialog() -eq "OK") {
        $filePath = $openFileDialog.FileName
        $command = switch ($copyMethod) {
            "d64copy" { "`"$rootPath\d64copy`" `"$filePath`" $deviceID" }
            "d82copy" { "`"$rootPath\d82copy`" `"$filePath`" $deviceID" }
            "imgcopy" { "`"$rootPath\imgcopy`" `"$filePath`" $deviceID" }
            "cbmcopy" { "`"$rootPath\cbmcopy`" -w $deviceID `"$filePath`"" }
        }
        $statusLabel.Text = "Status: Transferring to drive..."
        $output = RunCommand -command $command
        UpdateStatus -command $command -status "File transferred to drive" -result $output
    }
})
$fileMenu.DropDownItems.Add($transferToDriveMenuItem)

# Add Transfer from Drive to File menu
$transferFromDriveMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("Transfer from Drive")
$transferFromDriveMenuItem.Add_Click({
    $deviceID = GetSelectedDeviceID
    $copyMethod = $copyMethodComboBox.SelectedItem
    $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog

    if ($copyMethod -eq "cbmcopy") {
        # Open a dialog to get the Commodore file name and the destination file name
        $fileSelectionForm = New-Object System.Windows.Forms.Form
        $fileSelectionForm.Text = "Select Commodore File"
        $fileSelectionForm.Size = New-Object System.Drawing.Size(400, 300)
        $fileSelectionForm.StartPosition = "CenterParent"

        $commodoreFileLabel = New-Object System.Windows.Forms.Label
        $commodoreFileLabel.Location = New-Object System.Drawing.Point(10, 20)
        $commodoreFileLabel.Size = New-Object System.Drawing.Size(360, 20)
        $commodoreFileLabel.Text = "Enter the filename on the Commodore drive:"
        $commodoreFileLabel.Font = $font
        $fileSelectionForm.Controls.Add($commodoreFileLabel)

        $commodoreFileTextBox = New-Object System.Windows.Forms.TextBox
        $commodoreFileTextBox.Location = New-Object System.Drawing.Point(10, 50)
        $commodoreFileTextBox.Size = New-Object System.Drawing.Size(360, 20)
        $commodoreFileTextBox.Font = $font
        $fileSelectionForm.Controls.Add($commodoreFileTextBox)

        $fileSelectionButton = New-Object System.Windows.Forms.Button
        $fileSelectionButton.Location = New-Object System.Drawing.Point(10, 80)
        $fileSelectionButton.Size = New-Object System.Drawing.Size(360, 30)
        $fileSelectionButton.Text = "Select Destination File"
        $fileSelectionButton.Font = $font
        $fileSelectionButton.Add_Click({
            if ($commodoreFileTextBox.Text -ne "") {
                if ($saveFileDialog.ShowDialog() -eq "OK") {
                    $destinationFilePath = $saveFileDialog.FileName
                    $fileSelectionForm.Tag = @{
                        CommodoreFile = $commodoreFileTextBox.Text
                        DestinationFile = $destinationFilePath
                    }
                    $fileSelectionForm.Close()
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show("Please enter the Commodore file name.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        $fileSelectionForm.Controls.Add($fileSelectionButton)

        $fileSelectionForm.ShowDialog()

        if ($fileSelectionForm.Tag -ne $null) {
            $commodoreFile = $fileSelectionForm.Tag.CommodoreFile
            $destinationFile = $fileSelectionForm.Tag.DestinationFile
            $command = "`"$rootPath\cbmcopy`" -r $deviceID `"$commodoreFile`" -o `"$destinationFile`""
            $statusLabel.Text = "Status: Transferring from drive..."
            $output = RunCommand -command $command
            UpdateStatus -command $command -status "File transferred from drive" -result $output
        }
    } else {
        # For other copy methods, just open a save file dialog
        switch ($copyMethod) {
            "d64copy" { $saveFileDialog.Filter = "D64 files (*.d64)|*.d64" }
            "d82copy" { $saveFileDialog.Filter = "D80 and D82 files (*.d80;*.d82)|*.d80;*.d82" }
            "imgcopy" { $saveFileDialog.Filter = "Image files (*.d64;*.d71;*.d80;*.d81;*.d82)|*.d64;*.d71;*.d80;*.d81;*.d82" }
            "cbmcopy" { $saveFileDialog.Filter = "Raw binary files (*.bin)|*.bin|All files (*.*)|*.*" }
        }

        if ($saveFileDialog.ShowDialog() -eq "OK") {
            $filePath = $saveFileDialog.FileName
            $command = switch ($copyMethod) {
                "d64copy" { "`"$rootPath\d64copy`" $deviceID `"$filePath`"" }
                "d82copy" { "`"$rootPath\d82copy`" $deviceID `"$filePath`"" }
                "imgcopy" { "`"$rootPath\imgcopy`" $deviceID `"$filePath`"" }
            }
            $statusLabel.Text = "Status: Transferring from drive..."
            $output = RunCommand -command $command
            UpdateStatus -command $command -status "File transferred from drive" -result $output
        }
    }
})
$fileMenu.DropDownItems.Add($transferFromDriveMenuItem)

# Add Exit option to File menu at the bottom
$exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("Exit")
$exitMenuItem.Add_Click({ $form.Close() })
$fileMenu.DropDownItems.Add($exitMenuItem)
$fileMenu.DropDownItems.Remove($exitMenuItem)
$fileMenu.DropDownItems.Add($exitMenuItem)

# Add About option
$aboutMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("About OpenCBM GUI")
$aboutMenuItem.Add_Click({
    [System.Windows.Forms.MessageBox]::Show("OpenCBM GUI v0.3 by dotBtty`nSee https://github.com/tonnyrh/OpenCBMGUI", "About", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})
$aboutMenu.DropDownItems.Add($aboutMenuItem)

# Add the menu strip to the form
$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

# Create a label for status
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10, 30)
$statusLabel.Size = New-Object System.Drawing.Size(1160, 20)
$statusLabel.Text = "Status: Ready"
$statusLabel.Font = $font
$form.Controls.Add($statusLabel)

# Create radio buttons for device ID selection
$deviceIDLabel = New-Object System.Windows.Forms.Label
$deviceIDLabel.Location = New-Object System.Drawing.Point(10, 70)
$deviceIDLabel.Size = New-Object System.Drawing.Size(100, 20)
$deviceIDLabel.Text = "Device ID:"
$deviceIDLabel.Font = $font
$form.Controls.Add($deviceIDLabel)

$radioButtons = @{}
1..4 | ForEach-Object {
    $id = $_ + 7
    $radioButton = New-Object System.Windows.Forms.RadioButton
    $radioButton.Text = $id.ToString()
    $radioButton.Location = New-Object System.Drawing.Point((120 + (($_ - 1) * 70)), 70)
    $radioButton.AutoSize = $true
    $radioButton.Font = $font
    if ($_ -eq 1) { $radioButton.Checked = $true }
    $form.Controls.Add($radioButton)
    $radioButtons[$id] = $radioButton
} | Out-Null # Suppress the output of the loop

# Create a text box for the last run command
$lastRunLabel = New-Object System.Windows.Forms.Label
$lastRunLabel.Location = New-Object System.Drawing.Point(10, 120)
$lastRunLabel.Size = New-Object System.Drawing.Size(100, 20)
$lastRunLabel.Text = "Last Run:"
$lastRunLabel.Font = $font
$form.Controls.Add($lastRunLabel)

$lastRunTextBox = New-Object System.Windows.Forms.TextBox
$lastRunTextBox.Location = New-Object System.Drawing.Point(120, 120)
$lastRunTextBox.Size = New-Object System.Drawing.Size(650, 20)
$lastRunTextBox.ReadOnly = $true
$lastRunTextBox.Font = $font
$form.Controls.Add($lastRunTextBox)

# Create a text box for the last result
$lastResultLabel = New-Object System.Windows.Forms.Label
$lastResultLabel.Location = New-Object System.Drawing.Point(10, 150)
$lastResultLabel.Size = New-Object System.Drawing.Size(100, 20)
$lastResultLabel.Text = "Last Result:"
$lastResultLabel.Font = $font
$form.Controls.Add($lastResultLabel)

$lastResultTextBox = New-Object System.Windows.Forms.TextBox
$lastResultTextBox.Location = New-Object System.Drawing.Point(120, 150)
$lastResultTextBox.Size = New-Object System.Drawing.Size(650, 120)  # Increase height
$lastResultTextBox.Multiline = $true
$lastResultTextBox.ReadOnly = $true
$lastResultTextBox.ScrollBars = "Vertical"  # Add scroll bars to handle long output
$lastResultTextBox.WordWrap = $false  # Disable word wrap to handle formatted output
$form.Controls.Add($lastResultTextBox)

# Create the DataGridView for directory output
$directoryGrid = New-Object System.Windows.Forms.DataGridView
$directoryGrid.Location = New-Object System.Drawing.Point(800, 140)
$directoryGrid.Size = New-Object System.Drawing.Size(370, 710)
$directoryGrid.ReadOnly = $true
$directoryGrid.AllowUserToAddRows = $false
$directoryGrid.AllowUserToDeleteRows = $false
$directoryGrid.AllowUserToOrderColumns = $true
$directoryGrid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$directoryGrid.MultiSelect = $true  # Enable multi-selection
$form.Controls.Add($directoryGrid)

# Add labels for the disk title and blocks free above the DataGridView
$diskTitleLabel = New-Object System.Windows.Forms.Label
$diskTitleLabel.Location = New-Object System.Drawing.Point(800, 70)
$diskTitleLabel.Size = New-Object System.Drawing.Size(370, 20)
$diskTitleLabel.Font = $font
$form.Controls.Add($diskTitleLabel)

$freeBlocksLabel = New-Object System.Windows.Forms.Label
$freeBlocksLabel.Location = New-Object System.Drawing.Point(800, 100)
$freeBlocksLabel.Size = New-Object System.Drawing.Size(370, 20)
$freeBlocksLabel.Font = $font
$form.Controls.Add($freeBlocksLabel)

# Add the export button
$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Location = New-Object System.Drawing.Point(500, 300)
$exportButton.Size = New-Object System.Drawing.Size(250, 30)
$exportButton.Text = "Export Selected Files"
$exportButton.Font = $font
$exportButton.Add_Click({
    $folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($folderBrowserDialog.ShowDialog() -eq "OK") {
        $destinationFolder = $folderBrowserDialog.SelectedPath
        $selectedFiles = $directoryGrid.SelectedRows | ForEach-Object {
            $_.Cells["Filename"].Value
        }
        foreach ($file in $selectedFiles) {
            $deviceID = GetSelectedDeviceID
            $command = "`"$rootPath\cbmcopy`" -r $deviceID `"$file`" -o `"$destinationFolder\$file`""
            $statusLabel.Text = "Status: Exporting $file..."
            $output = RunCommand -command $command
            UpdateStatus -command $command -status "File exported" -result $output
        }
    }
})
$form.Controls.Add($exportButton)

# Add the import button
$importButton = New-Object System.Windows.Forms.Button
$importButton.Location = New-Object System.Drawing.Point(500, 340)
$importButton.Size = New-Object System.Drawing.Size(250, 30)
$importButton.Text = "Import Files"
$importButton.Font = $font
$importButton.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Multiselect = $true
    $openFileDialog.Filter = "Raw, PC64 (P00) and T64 files (*.prg;*.p00;*.t64;*.bin)|*.prg;*.p00;*.t64;*.bin|All files (*.*)|*.*"
    if ($openFileDialog.ShowDialog() -eq "OK") {
        $filePaths = $openFileDialog.FileNames
        foreach ($filePath in $filePaths) {
            $deviceID = GetSelectedDeviceID
            $command = "`"$rootPath\cbmcopy`" -w $deviceID `"$filePath`""
            $statusLabel.Text = "Status: Importing $filePath..."
            $output = RunCommand -command $command
            UpdateStatus -command $command -status "File imported" -result $output
        }
    }
})
$form.Controls.Add($importButton)


# Add the "Dir" button under the "Import" button
$dirButton = New-Object System.Windows.Forms.Button
$dirButton.Location = New-Object System.Drawing.Point(500, 380)  # Adjust the location as needed
$dirButton.Size = New-Object System.Drawing.Size(250, 30)
$dirButton.Text = "Dir"
$dirButton.Font = $font
$dirButton.Add_Click({
    $deviceID = GetSelectedDeviceID
    $command = "`"$rootPath\cbmctrl`" dir $deviceID"
    $statusLabel.Text = "Status: Retrieving directory..."
    $output = RunCommand -command $command
    Debug-Output $output
    UpdateStatus -command $command -status "Directory retrieved" -result $output
    PopulateDirectoryGrid -output $output
})
$form.Controls.Add($dirButton)

# Add the "Rename" button under the "Dir" button
$renameButton = New-Object System.Windows.Forms.Button
$renameButton.Location = New-Object System.Drawing.Point(500, 420)  # Adjust the location as needed
$renameButton.Size = New-Object System.Drawing.Size(250, 30)
$renameButton.Text = "Rename"
$renameButton.Font = $font
$renameButton.Add_Click({
    # Check if a file is selected in the DataGridView
    if ($directoryGrid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a file to rename.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    # Get the selected file name
    $selectedRow = $directoryGrid.SelectedRows[0]
    $oldFileName = $selectedRow.Cells["Filename"].Value

    # Prompt for the new file name
    $newFileName = Show-InputBox -title "Rename File" -promptText "Enter new file name:" -defaultValue $oldFileName

    # If the new file name is provided, execute the rename command
    if ($newFileName -ne $null -and $newFileName.Trim() -ne "") {
        $deviceID = GetSelectedDeviceID
        Rename-File -deviceID $deviceID -oldFileName $oldFileName -newFileName $newFileName.Trim()
    }
})
$form.Controls.Add($renameButton)

# Run detect drive on startup
DetectDrive

# 

# Create Action menu items
$initDriveMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("Initialize Drive")
$initDriveMenuItem.Add_Click({
    $deviceID = GetSelectedDeviceID
    $command = "`"$rootPath\cbmctrl`" reset"
    $statusLabel.Text = "Status: Initializing..."
    $output = RunCommand -command $command
    UpdateStatus -command $command -status "Drive initialized" -result $output
})
$actionMenu.DropDownItems.Add($initDriveMenuItem)

$detectDriveMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("Detect Drive")
$detectDriveMenuItem.Add_Click({
    DetectDrive
})
$actionMenu.DropDownItems.Add($detectDriveMenuItem)

$resetAllDrivesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("Reset All Drives")
$resetAllDrivesMenuItem.Add_Click({
    $command = "`"$rootPath\cbmctrl`" reset"
    $statusLabel.Text = "Status: Resetting all drives..."
    $output = RunCommand -command $command
    UpdateStatus -command $command -status "All drives reset" -result $output
})
$actionMenu.DropDownItems.Add($resetAllDrivesMenuItem)

$testDriveMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("Test Drive")
$testDriveMenuItem.Add_Click({
    $deviceID = GetSelectedDeviceID
    $command = "`"$rootPath\cbmctrl`" status $deviceID"
    $statusLabel.Text = "Status: Testing..."
    $output = RunCommand -command $command
    UpdateStatus -command $command -status "Drive tested" -result $output
})
$actionMenu.DropDownItems.Add($testDriveMenuItem)

# Create a section for formatting disk
$formatDiskMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem("Format Disk")
$formatDiskMenuItem.Add_Click({
    $formatForm = New-Object System.Windows.Forms.Form
    $formatForm.Text = "Format Disk"
    $formatForm.Size = New-Object System.Drawing.Size(300, 200)
    $formatForm.StartPosition = "CenterParent"

    # Disk Name
    $diskNameLabel = New-Object System.Windows.Forms.Label
    $diskNameLabel.Location = New-Object System.Drawing.Point(10, 20)
    $diskNameLabel.Size = New-Object System.Drawing.Size(100, 20)
    $diskNameLabel.Text = "Disk Name:"
    $diskNameLabel.Font = $font
    $formatForm.Controls.Add($diskNameLabel)

    $diskNameTextBox = New-Object System.Windows.Forms.TextBox
    $diskNameTextBox.Location = New-Object System.Drawing.Point(120, 20)
    $diskNameTextBox.Size = New-Object System.Drawing.Size(150, 20)
    $diskNameTextBox.Text = "empty" # Default disk name
    $diskNameTextBox.Font = $font
    $formatForm.Controls.Add($diskNameTextBox)

    # Disk ID
    $diskIDLabel = New-Object System.Windows.Forms.Label
    $diskIDLabel.Location = New-Object System.Drawing.Point(10, 50)
    $diskIDLabel.Size = New-Object System.Drawing.Size(100, 20)
    $diskIDLabel.Text = "Disk ID:"
    $diskIDLabel.Font = $font
    $formatForm.Controls.Add($diskIDLabel)

    $diskIDTextBox = New-Object System.Windows.Forms.TextBox
    $diskIDTextBox.Location = New-Object System.Drawing.Point(120, 50)
    $diskIDTextBox.Size = New-Object System.Drawing.Size(150, 20)
    $diskIDTextBox.Text = "00" # Default disk ID
    $diskIDTextBox.Font = $font
    $formatForm.Controls.Add($diskIDTextBox)

    # Verify Checkbox
    $verifyCheckbox = New-Object System.Windows.Forms.CheckBox
    $verifyCheckbox.Location = New-Object System.Drawing.Point(10, 80)
    $verifyCheckbox.Size = New-Object System.Drawing.Size(100, 20)
    $verifyCheckbox.Text = "Verify"
    $verifyCheckbox.Font = $font
    $formatForm.Controls.Add($verifyCheckbox)

    # Use cbmforng Checkbox
    $useCbmforngCheckbox = New-Object System.Windows.Forms.CheckBox
    $useCbmforngCheckbox.Location = New-Object System.Drawing.Point(120, 80)
    $useCbmforngCheckbox.Size = New-Object System.Drawing.Size(150, 20)
    $useCbmforngCheckbox.Text = "Use cbmforng"
    $useCbmforngCheckbox.Checked = $true
    $useCbmforngCheckbox.Font = $font
    $formatForm.Controls.Add($useCbmforngCheckbox)

    # Format Button
    $formatButton = New-Object System.Windows.Forms.Button
    $formatButton.Location = New-Object System.Drawing.Point(10, 110)
    $formatButton.Size = New-Object System.Drawing.Size(260, 30)
    $formatButton.Text = "Format Disk"
    $formatButton.Font = $font
    $formatButton.Add_Click({
        $deviceID = GetSelectedDeviceID
        $diskName = $diskNameTextBox.Text
        $diskID = $diskIDTextBox.Text
        $executable = "cbmformat"
        $options = "-s"
        if ($useCbmforngCheckbox.Checked) {
            $executable = "cbmforng"
        }
        if ($verifyCheckbox.Checked) {
            $options += " -v"
        }
        $command = "`"$rootPath\$executable`" $options $deviceID $diskName,$diskID"
        $statusLabel.Text = "Status: Formatting..."
        $output = RunCommand -command $command
        UpdateStatus -command $command -status "Disk formatted" -result $output
        $formatForm.Close()
    })
    $formatForm.Controls.Add($formatButton)

    $formatForm.ShowDialog()
})
$actionMenu.DropDownItems.Add($formatDiskMenuItem)

# Show the form
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()
