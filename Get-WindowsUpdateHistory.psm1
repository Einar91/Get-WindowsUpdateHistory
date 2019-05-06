function Get-WindowsUpdateHistory {
    <#
    .SYNOPSIS
    .DESCRIPTION
    .PARAMETER
    .EXAMPLE
    Get-WindowsUpdateHistory -ComputerName SRV1 -DaysBack 15 -MaxRecords
    #>    
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$True,
        ValueFromPipeline=$True,
        ValueFromPipelineByPropertyName=$True,
        Position=1)]
    [Alias('CN','MachineName','HostName','Name')]
    [string[]]$ComputerName,

    [Parameter(Mandatory=$false)]
    [int]$DaysBack = 15,

    [Parameter(Mandatory=$false)]
    [int]$MaxRecords = 50,

    [Parameter(Mandatory=$false)]
    [Switch]$CheckIfOnline
    )


BEGIN {
    #Define date for how far back we want to retrive log data
    $Days = ((Get-Date).AddDays(-$DaysBack))
    
    #Timestamp function for our verbos output and logs
    function TimeStamp{
        #Create TimeStamp function for our logging
        (get-date -Format "dd.MM.yyyy hh:mm:ss").ToString()
    } # Function TimeStamp
} #BEGIN


PROCESS {
    #Check which servers are online, so we skip invoke-command to offline computer(s) and create a lot of delay
    if($CheckIfOnline -eq $True){
        Write-Verbose "$(TimeStamp) Info.. Testing connection to remote computer(s)."
        #Variable to store our online computers
        $OnlineComputers = @()
        #Variable to store our offline computers
        $OfflineComputers = @()
        
        #Test connection per computer and store them in correct variable
        foreach($computer in $ComputerName){
            $TestCon = Test-Connection -ComputerName $computer -Count 2 -Quiet
            if($TestCon -eq $True){
                Write-Verbose "$(TimeStamp) Info... Connection to $computer was successful."
                $OnlineComputers += $computer
            } else{
                Write-Verbose "$(TimeStamp) Error.. Connection to $computer failed."
                $OfflineComputers += $computer
            } #Else
        } #Foreach
        
        #Output the failed connections
        foreach($OffComp in $OfflineComputers){
        $OffProperties = @{'ComputerName'=$OffComp
                        'Result'='Ping to computer failed.'}
        New-Object psobject -Property $OffProperties
        }

        #Set our $ComputerName parameter to check only online computers
        $ComputerName = $OnlineComputers
    } #If


    #We will send our entire script to execute on the remote computer, as session for Microsoft.Update must be created to query.
    #This will also allow us to get a faster completion with a lot of computers, as Invoke-Command will send simultaneously to multiple remote computers.

    Write-Verbose "$(TimeStamp) Info.. Sending query to remote computer(s)."
    Invoke-Command -ComputerName $ComputerName -ScriptBlock{
        
        #Function for converting the log status codes to readable status names.
        function Convert-WuaResultCodeToName{
            param(
                [Parameter(Mandatory=$true)]
                [int]$ResultCode
            )

            $Result = $ResultCode
                switch($ResultCode){
                    0
                        {
                        $Result = "Not Started"
                        } #0
                    1
                        {
                        $Result = "In Progress"            
                        } #1
                    2
                        {
                        $Result = "Succeeded"            
                        } #2
                    3
                        {
                        $Result = "Succeeded With Errors"            
                        } #3
                    4
                        {
                        $Result = "Failed"            
                        } #4
                    5
                        {
                        $Result = "Aborted"            
                        } #5
                } #Switch
                Return $Result
        } #Function Convert-WuaResultCodeToName

        #Open our session to prepeare to query result
        $UpdateSession = (New-Object -ComObject 'Microsoft.Update.Session' -ErrorVariable $UpdateSessionError)

        #Query the number of records specified in $MaxRecords and restrict it to a number of days back with $DaysBack
        $history = $UpdateSession.QueryHistory("",0,$using:MaxRecords)

        Foreach($update in $history){
            $NamedResult = Convert-WuaResultCodeToName -ResultCode $update.ResultCode
            $Properties = @{'ComputerName'=$env:COMPUTERNAME
                            'Result' = $NamedResult
                            'Date'=$update.Date
                            'Title'=$update.Title
                            'SupportUrl'=$update.SupportUrl
                            'Product'=$update.Categories[0].Name
                            'UpdateId'=$update.UpdateIdentity.UpdateId
                            'RevisionNumber'=$update.UpdateIdentity.RevisionNumber}

            $obj = New-Object psobject -Property $Properties
            $obj | Where-Object -FilterScript {$_.Date -gt $Using:Days}
        }

        if($UpdateSessionError){
            $UpdateSessionErrorProperties = @{'ComputerName'=$env:COMPUTERNAME
                                                'Result'='Session error'}
            New-Object -TypeName psobject -Property $UpdateSessionErrorProperties
        }
    } -HideComputerName -ErrorAction SilentlyContinue -ErrorVariable FailedConnections

    #Check for failed connections or errors from invoke-command
    $FailedMachines = @()
    $FailedMachines += $FailedConnections.TargetObject | Select-Object -Unique
    $FailedMachines += $FailedConnections.OriginInfo | Select-Object -Unique -ExpandProperty PSComputerName

    if($FailedMachines){
        foreach($FailedItem in $FailedMachines){
            $FailedProp = @{'ComputerName'=$FailedItem
                            'Result'='Querying computer failed.'}
            New-Object psobject -Property $FailedProp
        } #Foreach
    } #If

    Write-Verbose "$(TimeStamp) Info.. Querying done, ending script."
} #PROCESS

END{
    #Left empty
}

} #Function