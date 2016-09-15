param([Parameter(ValueFromPipeline=$true)][String] $userOU = "ou=Users,dc=localdomain,dc=internal",
	  $userOUScope = "OneLevel",
	  [String] $logPrefix,
	  [String] $resourceDomain = "target.domain",
	  [String[]] $Properties = @("thumbnailPhoto", "physicalDeliveryOfficeName", "telephoneNumber", "mail", "title", "department", "company"),
	  [Switch] $ToResourceDomain = $true,
	  [Switch] $WhatIf = $false,
	  [String] $credentialUser = "target\useraccount",
	  [String] $credentialPasswordFile = "c:\scripts\useraccount-password-file.txt"
)
	  
# Author: Neale Lonslow
# Date: 6/3/2013
#
# Purpose: To synchronise AD properties between user objects and Exchange linked accounts in a user/resource forest scenario.
#
# Notes: Create a /logs/ folder in the working folder to store the logs.
#
# Parameters:
# $userOU - the OU that contains the users we want to sync. This is in the user forest.
# $userOUScope - OneLevel/Subtree. This is whether we search the $userOU, it's immediate children, or everything underneath.
# $logPrefix - a string that is used to identify instances of the script based upon running parameters. i.e. can relate to $userOU.
# $resourceDomain - the domain that holds the linked accounts.
# $Properties - an array representing a list of the properties to synchronise.
# $ToResourceDomain - the direction of synchronisation. Defaults to $true, set to $false to copy values from resource to user.
# $WhatIf - Don't make any changes, will log all potential changes.
# $credentialUser - The user name (prefixed with short domain name) for the domain making changes.
# $credentialPasswordFile - The file that contains the secure password.
#
# Permissions:
#
# This script should run as a user with write permissions on the objects in the domain that we are writing to.
# A trust will have been set up for Exchange so the user should certainly have read permissions on the other domain.
#

# Keep 4 weeks worth of logs.
$logretentionDays = 28

# Create the Logging object/
$log = New-Object System.IO.StreamWriter (($PWD.Path) + "\logs\sync-" + $logPrefix + "-" + $(get-date -format "yyyyMdd-HHmmss") + ".txt"), 1

# Write configuration information.
$rt = get-date -format "HH:mm dddd dd MMMM yyyy"
$log.WriteLine("*********************************************************************")
$log.WriteLine("Synchronisation started at " + $rt)
$log.WriteLine("User OU: " + $userOU + " with a scope of " + $userOUScope)
if ($WhatIf -eq $true) {
	$log.WriteLine("## WhatIf is set to true. No Changes will be made: the following is indicative of what would happen.")
}

# Ensure we've got AD Tools available.
import-module activedirectory -erroraction silentlycontinue

# Create the MBXG Credential
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $credentialUser, $(cat $credentialPasswordFile | convertto-securestring)

# Setup the DirectorySearcher object with the options that won't change.
$objSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$resourceDomain")
$objSearcher.PageSize = 10
$objSearcher.SearchScope = "Subtree"
$objSearcher.PropertiesToLoad.Add("msExchMasterAccountSid") | out-null

# Add the desired properties to the DirectorySearcher configuration
$line = "Properties: "
foreach ($i in $Properties) {
	$line += $i
	$line += ", "
    $objSearcher.PropertiesToLoad.Add($i) | out-null
}
$log.WriteLine($line)

# Get all the users in the $userOU provided by the script.
$users = get-aduser -filter * -searchbase $userOU -properties * -searchScope $userOUScope

foreach ($i in $users) {
	#$log.WriteLine($($i.samaccountname));
	$log.flush();

	# Assemble the filter to search the entire resource domain for the linked account. Then search.
	$objSearcher.Filter = "((msExchMasterAccountSid=" + ($i.SID) + "))"
	$results = $objSearcher.FindAll()

	# If no results, output this.
	if ($results.Count -eq 0) {
		$log.WriteLine("## There are no results for a linked account for $($i.Name) - $($i.samaccountname).")
		continue;
	}
	
	# If more than one result, warn us.
	if ($results.Count -gt 1) {
		$log.WriteLine("## There is more than 1 result for a linked account for the user " + $usr.Name + ". This is not good.")
		continue;
	}

	# Get our one and only entry. Fail if we can't.
	$usr = ($results[0]).GetDirectoryEntry();
	if ($usr -eq $null) {
		$log.WriteLine("## Could not get the linked object in the resource domain for the user account " + $usr.Name);
		continue;
	}

	# Enumerate through each desired property.
	foreach ($prop in $Properties) {
		#$log.WriteLine($prop);
		$log.flush();

		# Thumbnails are a special case as they are a byte array.
		if ($prop -eq "thumbnailPhoto") {	
			# Special processing if we're looking at the photo. Need to deal with a byte array.
			$resourceAccount = get-aduser -identity $($usr.samaccountname) -server $resourceDomain -properties thumbnailPhoto
			if ($resourceAccount -eq $Null) {
				continue;
			}

			$resourceValue = $resourceAccount.thumbnailPhoto;
			$userPhoto = $i.thumbnailPhoto

			if ($resourceValue -eq $Null -And $userPhoto -eq $Null) {
				continue;

			} elseif ($ToResourceDomain -eq $True -And $resourceValue -ne $Null -And $userPhoto -eq $Null) {
				$log.WriteLine("$($usr.Name): Clearing attribute: thumbnailPhoto");
				$log.flush();
				if ($WhatIf -eq $False) {
					set-aduser $($usr.samaccountname) -server $resourceDomain -clear "thumbnailPhoto" -Credential $cred
				}

			} elseif ($ToResourceDomain -eq $False -And $userPhoto -ne $Null -And $resourceValue -eq $Null) {
				$log.WriteLine("$($usr.Name): Clearing attribute: thumbnailPhoto");
				$log.flush();
				if ($WhatIf -eq $False) {
					set-aduser $($i.samaccountname) -clear "thumbnailPhoto"
				}
				
			} else {
				$copyPhoto = $false;

				if ($resourceValue -ne $Null -And $userPhoto -ne $Null) {
					if (@(Compare-Object $resourceValue $userPhoto -SyncWindow 0).length -ne 0) {
						# The Two are different.
						$copyPhoto = $true;

					}
					
				} else {
					# This means that the destination is null and the source has something to copy.
					# So we copy.
					$copyPhoto = $true

				}
					
				if ($copyPhoto -eq $true) {
					$log.WriteLine("$($usr.Name): Setting attribute: thumbnailPhoto");
					$log.flush();

					if ($WhatIf -eq $false) {
						if ($ToResourceDomain -eq $false) {
							# Copy resourcePhoto to $userPhoto
							set-aduser $($i.samaccountname) -replace @{thumbnailPhoto=$resourceValue}
									
						} else {
							# Copy $userPhoto to $resourcePhoto
							set-aduser $($usr.samaccountname) -server $resourceDomain -replace @{thumbnailPhoto=$userPhoto} -Credential $cred
									
						}
					}
				}
			}
			
		} else {
			# Get the value.
			$resourceValue = $usr.psbase.Properties.Item($prop).Value
			
			if ($ToResourceDomain -eq $True -And ($($i.psbase.Item($prop)) -eq $Null -Or $($i.psbase.Item($prop)).Length -eq 0) -And ($resourceValue -ne $Null -And $resourceValue.Length -gt 0)) {
				$log.WriteLine("$($usr.Name): Clearing attribute: " + $prop + ". Value was " + $resourceValue);			
				$log.flush();

				if ($WhatIf -eq $false) {
					set-aduser $($usr.samaccountname) -server $resourceDomain -clear $prop -Credential $cred
				}

			} elseif ($ToResourceDomain -eq $False -And ($resourceValue -eq $Null -Or $resourceValue.Length -eq 0) -And ($($i.psbase.Item($prop)) -ne $Null -And $($i.psbase.Item($prop)).Length -gt 0)) {
				$log.WriteLine("$($usr.Name): Clearing attribute: " + $prop + ". Value was " + $($i.psbase.Item($prop)));
				$log.flush();
				
				if ($WhatIf -eq $false) {
					if ($cred -ne $Null) {
						set-aduser $($i.samaccountname) -clear $prop -Credential $cred

					} else {
						set-aduser $($i.samaccountname) -clear $prop
					}
				}
		
			} elseif ($resourceValue -ne $($i.psbase.Item($prop))) {
				# Set the value.								
				if ($ToResourceDomain -eq $false) {
					$log.WriteLine("$($usr.Name): Changing attribute: " + $prop + " from " + $i.psbase.Item($prop) + " to " + $resourceValue);
					$log.flush();

					if ($WhatIf -eq $false) {
						if ($cred -ne $Null) {
							Write-Host "Using Credentials"
							invoke-expression "set-aduser $($i.samaccountname) -replace @{$prop='$resourceValue'} -Credential `$cred"

						} else {
							invoke-expression "set-aduser $($i.samaccountname) -replace @{$prop='$resourceValue'}"

						}
					}

				} else {
					$log.WriteLine("$($usr.Name): Changing attribute: " + $prop + " from " + $resourceValue + " to " + $i.psbase.Item($prop));
					$log.flush();

					if ($WhatIf -eq $false) {
						#Write-Host "set-aduser $($usr.samaccountname) -server $resourceDomain -replace @{$prop='$($i.psbase.Item($prop))'}"
						invoke-expression "set-aduser $($usr.samaccountname) -server $resourceDomain -replace @{$prop='$($i.psbase.Item($prop))'} -Credential `$cred"
					}
					
				}
			}
		}
	}
}

$log.WriteLine("Script completed at " + $(get-date -format 'dd/MM/yyyy HH:mm:ss')")
$log.Close()

# Get rid of files older than the retention date.
$compareDate = (Get-Date).AddDays(0 - $logretentionDays)
Get-ChildItem $(($PWD.Path) + "\logs\*.txt") | Where-Object {$_.LastWriteTime -lt $compareDate} | Remove-Item