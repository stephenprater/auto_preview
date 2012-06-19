if !has('macunix')
  finish
endif

let s:current_file = expand('<sfile>')

" OSX Applescript and QLManage Interface {{{1
" This is THE most basic kind of interface.  It simply calls the qlmanage
" program everytime an associated buffer is written.  It's stupid, but it works
" and if you're not interested in having it work *well* it's perfectly adequate
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! OSXHostScript(preview) 
  let l:interface = g:PreviewNewHostScript(a:preview)
  let l:interface["dir"] = join(split(s:current_file,'\/')[0:-2],"/")
  echomsg string(l:interface)

  function! l:interface.open() dict
    call system('qlmanage -p ' . self.preview.mainfile . '&')
    let l:pid = ""
    while l:pid == ""
      let l:pid = system('lsof -c qlmanage | grep ' . self.preview.mainfile . ' | cut -f 2 -d " "') 
      if l:pid =~ "[\r\n]"
        let l:pid = split(l:pid,"\n")[0]
      endif
      sleep 30m
    endwhile
    let self.preview.pid = l:pid
    return l:pid
  endfunction

  function! l:interface.get_position() dict
    let l:position_string = system('osascript -s s /' . self.dir . '/window_position.scpt ' . self.preview.pid) 
    if l:position_string =~ "[\r\n]"
      let l:position_string = split(l:position_string,"\n")[0]
    endif
    return l:position_string
  endfunction
  
  function! l:interface.set_position() dict
    let l:args = join([self.preview.pid, 1, "'" . self.preview.position . "'" ], " ")
    let l:comstr = 'osascript -s s /' . self.dir . '/window_position.scpt ' . l:args
    call system(l:comstr)
  endfunction

  function! l:interface.update() dict
       
    let self.preview.position = self.get_position() 
    
    call self.close()
    call self.open()
    
    call self.set_position()
  endfunction

  function! l:interface.close() dict
    call system('kill ' . self.preview.pid)
  endfunction

  return l:interface
endfunction
" 1}}}

call PreviewAddInterface('html,*',function("OSXHostScript"),'BufWritePost',1)

