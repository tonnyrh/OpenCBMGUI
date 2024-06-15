#OpenCBMGUI by dotBtty v0.1
#See https://github.com/tonnyrh/OpenCBMGUI


#################################################################################################################################################
#OpenCBM GUI is a graphical user interface for the OpenCBM software, which allows users to interact with Commodore disk drives. 				#
#This GUI is built using PowerShell and Windows Forms, providing an intuitive way to manage disk operations without using the command line.		#
#################################################################################################################################################

# Import the necessary assembly for Windows Forms
Add-Type -AssemblyName System.Windows.Forms

# Define the root path for OpenCBM
$rootPath = "C:\Program Files\opencbm"  # Using a fixed path for clarity

# Define a debug flag
$debug = $false

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
$form.Text = "OpenCBM GUI v0.1 by dotBtty"
$form.Size = New-Object System.Drawing.Size(800, 850)  # Increase the size of the form
$form.StartPosition = "CenterScreen"

# Set the font to Courier New for an old-fashioned console look
$font = New-Object System.Drawing.Font("Courier New", 8)

# Create a label for status
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10, 10)
$statusLabel.Size = New-Object System.Drawing.Size(760, 20)
$statusLabel.Text = "Status: Ready"
$statusLabel.Font = $font
$form.Controls.Add($statusLabel)

# Create radio buttons for device ID selection
$deviceIDLabel = New-Object System.Windows.Forms.Label
$deviceIDLabel.Location = New-Object System.Drawing.Point(10, 50)
$deviceIDLabel.Size = New-Object System.Drawing.Size(100, 20)
$deviceIDLabel.Text = "Device ID:"
$deviceIDLabel.Font = $font
$form.Controls.Add($deviceIDLabel)

$radioButtons = @{}
1..4 | ForEach-Object {
    $id = $_ + 7
    $radioButton = New-Object System.Windows.Forms.RadioButton
    $radioButton.Text = $id.ToString()
    $radioButton.Location = New-Object System.Drawing.Point((120 + (($_ - 1) * 70)), 50)
    $radioButton.AutoSize = $true
    $radioButton.Font = $font
    if ($_ -eq 1) { $radioButton.Checked = $true }
    $form.Controls.Add($radioButton)
    $radioButtons[$id] = $radioButton
}

# Create a text box for the last run command
$lastRunLabel = New-Object System.Windows.Forms.Label
$lastRunLabel.Location = New-Object System.Drawing.Point(10, 650)
$lastRunLabel.Size = New-Object System.Drawing.Size(100, 20)
$lastRunLabel.Text = "Last Run:"
$lastRunLabel.Font = $font
$form.Controls.Add($lastRunLabel)

$lastRunTextBox = New-Object System.Windows.Forms.TextBox
$lastRunTextBox.Location = New-Object System.Drawing.Point(120, 650)
$lastRunTextBox.Size = New-Object System.Drawing.Size(650, 20)
$lastRunTextBox.ReadOnly = $true
$lastRunTextBox.Font = $font
$form.Controls.Add($lastRunTextBox)

# Create a text box for the last result
$lastResultLabel = New-Object System.Windows.Forms.Label
$lastResultLabel.Location = New-Object System.Drawing.Point(10, 680)
$lastResultLabel.Size = New-Object System.Drawing.Size(100, 20)
$lastResultLabel.Text = "Last Result:"
$lastResultLabel.Font = $font
$form.Controls.Add($lastResultLabel)

$lastResultTextBox = New-Object System.Windows.Forms.TextBox
$lastResultTextBox.Location = New-Object System.Drawing.Point(120, 680)
$lastResultTextBox.Size = New-Object System.Drawing.Size(650, 120)  # Increase height
$lastResultTextBox.Multiline = $true
$lastResultTextBox.ReadOnly = $true
$lastResultTextBox.ScrollBars = "Vertical"  # Add scroll bars to handle long output
$lastResultTextBox.WordWrap = $false  # Disable word wrap to handle formatted output
$lastResultTextBox.Font = $font
$form.Controls.Add($lastResultTextBox)

# Function to update status and last run command
function UpdateStatus {
    param (
        [string]$command,
        [string]$status,
        [string]$result
    )
    $lastRunTextBox.Text = $command
    $lastResultTextBox.Text = $result #+ [Environment]::NewLine
    $statusLabel.Text = "Status: " + $status
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

# Run detect drive on startup
DetectDrive

# Function to get the selected device ID
function GetSelectedDeviceID {
    foreach ($id in $radioButtons.Keys) {
        if ($radioButtons[$id].Checked) {
            return $id
        }
    }
}

# Create a dropdown menu for selecting the copy method
$copyMethodLabel = New-Object System.Windows.Forms.Label
$copyMethodLabel.Location = New-Object System.Drawing.Point(500, 50)
$copyMethodLabel.Size = New-Object System.Drawing.Size(100, 20)
$copyMethodLabel.Text = "Copy Method:"
$copyMethodLabel.Font = $font
$form.Controls.Add($copyMethodLabel)

$copyMethodComboBox = New-Object System.Windows.Forms.ComboBox
$copyMethodComboBox.Location = New-Object System.Drawing.Point(610, 50)
$copyMethodComboBox.Size = New-Object System.Drawing.Size(150, 20)
$copyMethodComboBox.Font = $font
$copyMethodComboBox.Items.AddRange(@("d64copy", "d82copy", "imgcopy", "cbmcopy"))
$copyMethodComboBox.SelectedIndex = 0
$form.Controls.Add($copyMethodComboBox)

# Create a button to initialize the drive
$initButton = New-Object System.Windows.Forms.Button
$initButton.Location = New-Object System.Drawing.Point(10, 110)
$initButton.Size = New-Object System.Drawing.Size(150, 30)
$initButton.Text = "Initialize Drive"
$initButton.Font = $font
$initButton.Add_Click({
    $deviceID = GetSelectedDeviceID
    $command = "`"$rootPath\cbmctrl`" reset"
    $statusLabel.Text = "Status: Initializing..."
    $output = RunCommand -command $command
    UpdateStatus -command $command -status "Drive initialized" -result $output
})
$form.Controls.Add($initButton)

# Create a button to detect the drive
$detectButton = New-Object System.Windows.Forms.Button
$detectButton.Location = New-Object System.Drawing.Point(10, 150)
$detectButton.Size = New-Object System.Drawing.Size(150, 30)
$detectButton.Text = "Detect Drive"
$detectButton.Font = $font
$detectButton.Add_Click({
    DetectDrive
})
$form.Controls.Add($detectButton)

# Create a button to reset all drives on the IEC bus
$resetAllButton = New-Object System.Windows.Forms.Button
$resetAllButton.Location = New-Object System.Drawing.Point(10, 190)
$resetAllButton.Size = New-Object System.Drawing.Size(150, 30)
$resetAllButton.Text = "Reset All Drives"
$resetAllButton.Font = $font
$resetAllButton.Add_Click({
    $command = "`"$rootPath\cbmctrl`" reset"
    $statusLabel.Text = "Status: Resetting all drives..."
    $output = RunCommand -command $command
    UpdateStatus -command $command -status "All drives reset" -result $output
})
$form.Controls.Add($resetAllButton)

# Create a button to display the directory
$dirButton = New-Object System.Windows.Forms.Button
$dirButton.Location = New-Object System.Drawing.Point(10, 230)
$dirButton.Size = New-Object System.Drawing.Size(150, 30)
$dirButton.Text = "Dir"
$dirButton.Font = $font
$dirButton.Add_Click({
    $deviceID = GetSelectedDeviceID
    $command = "`"$rootPath\cbmctrl`" dir $deviceID"
    $statusLabel.Text = "Status: Retrieving directory..."
    $output = RunCommand -command $command
    Debug-Output $output
    UpdateStatus -command $command -status "Directory retrieved" -result $output
})
$form.Controls.Add($dirButton)

# Create a button to transfer a file to the drive
$transferToButton = New-Object System.Windows.Forms.Button
$transferToButton.Location = New-Object System.Drawing.Point(500, 110)
$transferToButton.Size = New-Object System.Drawing.Size(150, 30)
$transferToButton.Text = "Transfer to Drive"
$transferToButton.Font = $font
$transferToButton.Add_Click({
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
$form.Controls.Add($transferToButton)

# Create a button to transfer a file from the drive
$transferFromButton = New-Object System.Windows.Forms.Button
$transferFromButton.Location = New-Object System.Drawing.Point(500, 150)
$transferFromButton.Size = New-Object System.Drawing.Size(150, 30)
$transferFromButton.Text = "Transfer from Drive"
$transferFromButton.Font = $font
$transferFromButton.Add_Click({
    $deviceID = GetSelectedDeviceID
    $copyMethod = $copyMethodComboBox.SelectedItem
    $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog

    # Set file dialog filter based on selected copy method
    switch ($copyMethod) {
        "d64copy" { $saveFileDialog.Filter = "D64 files (*.d64)|*.d64" }
        "d82copy" { $saveFileDialog.Filter = "D80 and D82 files (*.d80;*.d82)|*.d80;*.d82" }
        "imgcopy" { $saveFileDialog.Filter = "Image files (*.d64;*.d71;*.d80;*.d81;*.d82)|*.d64;*.d71;*.d80;*.d81;*.d82" }
        "cbmcopy" { $saveFileDialog.Filter = "Raw binary files (*.bin)|*.bin|All files (*.*)|*.*" }
    }

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
})
$form.Controls.Add($transferFromButton)

# Create a button to test the drive connection
$testButton = New-Object System.Windows.Forms.Button
$testButton.Location = New-Object System.Drawing.Point(10, 270)
$testButton.Size = New-Object System.Drawing.Size(150, 30)
$testButton.Text = "Test Drive"
$testButton.Font = $font
$testButton.Add_Click({
    $deviceID = GetSelectedDeviceID
    $command = "`"$rootPath\cbmctrl`" status $deviceID"
    $statusLabel.Text = "Status: Testing..."
    $output = RunCommand -command $command
    UpdateStatus -command $command -status "Drive tested" -result $output
})
$form.Controls.Add($testButton)

# Create a section for formatting disk
$formatLabel = New-Object System.Windows.Forms.Label
$formatLabel.Location = New-Object System.Drawing.Point(10, 310)
$formatLabel.Size = New-Object System.Drawing.Size(150, 20)
$formatLabel.Text = "Disk Formatting"
$formatLabel.Font = $font
$form.Controls.Add($formatLabel)

# Disk Name
$diskNameLabel = New-Object System.Windows.Forms.Label
$diskNameLabel.Location = New-Object System.Drawing.Point(10, 340)
$diskNameLabel.Size = New-Object System.Drawing.Size(100, 20)
$diskNameLabel.Text = "Disk Name:"
$diskNameLabel.Font = $font
$form.Controls.Add($diskNameLabel)

$diskNameTextBox = New-Object System.Windows.Forms.TextBox
$diskNameTextBox.Location = New-Object System.Drawing.Point(120, 340)
$diskNameTextBox.Size = New-Object System.Drawing.Size(150, 20)
$diskNameTextBox.Text = "NEWDISK" # Default disk name
$diskNameTextBox.Font = $font
$form.Controls.Add($diskNameTextBox)

# Disk ID
$diskIDLabel = New-Object System.Windows.Forms.Label
$diskIDLabel.Location = New-Object System.Drawing.Point(10, 370)
$diskIDLabel.Size = New-Object System.Drawing.Size(100, 20)
$diskIDLabel.Text = "Disk ID:"
$diskIDLabel.Font = $font
$form.Controls.Add($diskIDLabel)

$diskIDTextBox = New-Object System.Windows.Forms.TextBox
$diskIDTextBox.Location = New-Object System.Drawing.Point(120, 370)
$diskIDTextBox.Size = New-Object System.Drawing.Size(150, 20)
$diskIDTextBox.Text = "00" # Default disk ID
$diskIDTextBox.Font = $font
$form.Controls.Add($diskIDTextBox)

# Verify Checkbox
$verifyCheckbox = New-Object System.Windows.Forms.CheckBox
$verifyCheckbox.Location = New-Object System.Drawing.Point(10, 400)
$verifyCheckbox.Size = New-Object System.Drawing.Size(100, 20)
$verifyCheckbox.Text = "Verify"
$verifyCheckbox.Font = $font
$form.Controls.Add($verifyCheckbox)

# Use cbmforng Checkbox
$useCbmforngCheckbox = New-Object System.Windows.Forms.CheckBox
$useCbmforngCheckbox.Location = New-Object System.Drawing.Point(120, 400)
$useCbmforngCheckbox.Size = New-Object System.Drawing.Size(150, 20)
$useCbmforngCheckbox.Text = "Use cbmforng"
$useCbmforngCheckbox.Checked = $true
$useCbmforngCheckbox.Font = $font
$form.Controls.Add($useCbmforngCheckbox)

# Create a button to format the disk
$formatButton = New-Object System.Windows.Forms.Button
$formatButton.Location = New-Object System.Drawing.Point(10, 430)
$formatButton.Size = New-Object System.Drawing.Size(150, 30)
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
})
$form.Controls.Add($formatButton)

# Show the form
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()
