$s = (New-Object -ComObject WScript.Shell).CreateShortcut('C:\Users\Acer\Desktop\Ghita Edit.lnk')
Write-Host "TARGET: $($s.TargetPath)"
Write-Host "ARGS: $($s.Arguments)"
Write-Host "WORKDIR: $($s.WorkingDirectory)"
