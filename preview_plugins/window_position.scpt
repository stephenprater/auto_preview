on run argv
  if count of argv is greater than 1
    set myPosition to set_window_position(item 1 of argv, item 3 of argv)
  else
    set myPosition to get_window_position(item 1 of argv) 
  end
  tell application "MacVim" to activate
  return myPosition
end run


on get_window_position(pid)
  set theSize to {}
  set thePosition to {}
  
  tell application "System Events"
    repeat with theProcess in (every process whose name is "qlmanage")
      if the unix id of theProcess is (pid as integer) then
        set theSize to the size of window 1 of theProcess
        set thePosition to the position of window 1 of theProcess
      end if
    end repeat
  end tell
  
  return {theSize, thePosition}
end

on set_window_position(pid, location)
  set theLocation to run script location
  set theSize to item 1 of theLocation 
  set thePosition to item 2 of theLocation

  tell application "System Events"
    repeat with theProcess in (every process whose name is "qlmanage")
      if the unix id of theProcess is (pid as integer) then
        set the size of window 1 of theProcess to theSize
        set the position of window 1 of theProcess to thePosition
      end if
    end repeat
  end tell
  
  return {theSize, thePosition}
end
