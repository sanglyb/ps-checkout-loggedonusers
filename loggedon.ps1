<#
    .SYNOPSIS
        Search on which computers in domain user is currently logged on
    .DESCRIPTION
		This script searches where specified user currenty loggen on
    .EXAMPLE
        #.\loggedon.ps1 -user "someuser" -AllServer $true -threads 100
    .PARAMETER user
        Whom we are searching for.
	.PARAMETER $comps
		where a user should be searched. By defalt the search is going on all active domain machines.
	.PARAMETER maxtheads
		Set maximum theads, by default - 50.
	.PARAMETER AllServers
		Make search through all servers.
    #>
    param (
        [PARAMETER(Mandatory=$True,Position=0)][String]$user,
        [PARAMETER(Mandatory=$False,Position=1)][String[]]$comps,
		[PARAMETER(Mandatory=$False,Position=2)][int]$maxthreads,
		[PARAMETER(Mandatory=$False,Position=3)][Bool]$AllServers
        )



import-module activedirectory
$sid=get-aduser $user -erroraction stop
if ($maxthreads -eq 0){
	$maxthreads=50
}
if ($comps -eq $null -and $AllServers -ne $True){
	$comps=(get-adcomputer -filter {enabled -eq "True"} -erroraction stop).name
} 
if ($AllServers -eq $True){
	$comps=(Get-ADComputer -Filter {enabled -eq "True"} -erroraction stop | ?{$_.DistinguishedName -like "*server*"}).name
}
$csvPath=".\result.csv"
$pstoolsPath="$PSScriptRoot\"
$total=$comps.count
foreach ($comp in $comps){
			$job={
				$pstoolsPath=$args[2]
				if (!(test-path "$($pstoolspath)psexec.exe")){
					write-host "psexec not found"
					return
				}
				$path="REGISTRY::HKEY_USERS\$($args[1])"
				if (Test-Connection $args[0] -Count 2){
					try {
						$test=invoke-command -erroraction stop -computername $args[0] {
															param($path)
															Test-Path $path 
															} -ArgumentList $path
						if ($test -eq $True){
							$result="true"
						}
						elseif ($test -eq $False) {
							$result="false"
						}
						else {
							$result="powershell error"
						}
					}
					catch{
						cd $pstoolsPath
						$test=(.\psexec.exe -nobanner -accepteula \\$($args[0]) powershell.exe -nologo -NonInteractive -noprofile -command "Test-Path $path")
						
						if ($test -eq "True"){
							$result="true"
						}
						elseif ($test -eq "False") {
							$result="false"
						}
						else {
							$result="error"
						}
					}
				} else {
					$result="unavailable"
				}
				write-host "$($args[0]);$result"
			}
			$maxthreads
			Start-Job -Name $comp -ScriptBlock $job -argumentlist @($comp,$sid.sid,$pstoolsPath)
			
			While (@(Get-Job | Where { $_.State -eq "Running" }).Count -gt $maxthreads) {
				$completed=((Get-Job | Where { $_.State -ne "Running" }).Count)
				$percentCompleted=($completed*100/$total)
				Write-Progress -Activity "Search in progress..." -status "$percentCompleted% Completed" -PercentComplete $percentCompleted
				Start-Sleep -Seconds 3
			}
}
While (@(Get-Job | Where { $_.State -eq "Running" }).Count -gt 0) {
	$completed=((Get-Job | Where { $_.State -ne "Running" }).Count)
	$percentCompleted=($completed*100/$total)
	Write-Progress -Activity "Search in progress..." -status "$percentCompleted% Completed" -PercentComplete $percentCompleted
	Start-Sleep -Seconds 3
}
$final=get-job | receive-job 6>&1
get-job | remove-job
"computer;result" |  Out-File $csvPath -Encoding utf8
$final | Out-String |  Out-File $csvPath -Encoding utf8 -append