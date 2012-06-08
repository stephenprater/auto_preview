" auto_preview.vim: preview html / css in a browser without having to hit
" refresh all of the goddamn time
"
" Maintainer:    Stephen Prater <me@stephenprater.com>
" Last Modified: 2012-06-06 
" Version:       0.0
"
if exists('g:loaded_auto_preview')
    finish
endif
"let g:loaded_auto_preview = 1

let s:save_cpo = &cpo
set cpo&vim

let s:preview_catalog = {}
let g:preview_default_preview = ""
let s:current_file = expand("<sfile>")

" Utility Functions {{{1
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! s:_complete_preview_names(arglead, cmdline, cursorpos)
  return sort(keys(s:preview_catalog))
endfunction

function! s:_get_associated_preview()
  let l:preview = getbufvar(bufnr("%"),"preview_buffer_preview")
  return l:preview ? l:preview : g:preview_default_preview
endfunction
"}}}

" Host Script Interface {{{
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"
" Host Script Abstract Parent Class {{{2
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! s:NewHostScript(preview)
  let l:interface = {}
  let l:interface["preview"] = a:preview

  function! l:interface.open() dict
    throw "AbstractInterface not completed"
  endfunction

  function! l:interface.update() dict
    throw "AbstractInterface not completed"
  endfunction

  function! l:interface.close() dict
    throw "AbstractInterface not completed"
  endfunction

  return l:interface
endfunction
" }}}2 

function! s:OSXHostScript(preview)
  let l:interface = s:NewHostScript(a:preview)
  let l:interface["dir"] = join(split(s:current_file,'\/')[0:-2],"/")

  function! l:interface.open() dict
    call system('qlmanage -p ' . self.preview.mainfile . '&')
    let l:pid = ""
    while l:pid == ""
      let l:pid = system('lsof -c qlmanage | grep ' . self.preview.mainfile . ' | cut -f 2 -d " "')
      sleep 30m
    endwhile
    echomsg "started " . l:pid
    return l:pid
  endfunction

  function! l:interface.get_position() dict
    echomsg "getting position"
    return system('osascript -s s /' . self.dir . '/window_position.scpt ' . self.preview.pid)
  endfunction
  
  function! l:interface.set_position() dict
    echomsg "setting position"
    let l:args = join([self.preview.pid, 1, self.preview.position], " ")
    return system('osascript -s s /' . self.dir . '/window_position.scpt ' . args)
  endfunction

  function! l:interface.update() dict
    if !has_key(self.preview, "position")
      let self.preview.position = self.get_position() 
    else
      let self.preview.position = self.set_position()
    endif
    call self.close()
    echomsg self.preview.position
    call self.open()
  endfunction

  function! l:interface.close() dict
    echomsg "killing " . self.preview.pid
    call system('kill ' . self.preview.pid)
  endfunction

  return l:interface
endfunction

" }}}

" Messaging {{{1
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function! s:NewMessenger(name)

    " allocate a new pseudo-object
    let l:messenger = {}
    let l:messenger["name"] = a:name
    if empty(a:name)
        let l:messenger["title"] = "auto_preview"
    else
        let l:messenger["title"] = "auto_preview(" . l:messenger["name"] . ")"
    endif

    function! l:messenger.format_message(leader, msg) dict
        return self.title . ": " . a:leader.a:msg
    endfunction

    function! l:messenger.format_exception( msg) dict
        return a:msg
    endfunction

    function! l:messenger.send_error(msg) dict
        redraw
        echohl ErrorMsg
        echomsg self.format_message("[ERROR] ", a:msg)
        echohl None
    endfunction

    function! l:messenger.send_warning(msg) dict
        redraw
        echohl WarningMsg
        echomsg self.format_message("[WARNING] ", a:msg)
        echohl None
    endfunction

    function! l:messenger.send_status(msg) dict
        redraw
        echohl None
        echomsg self.format_message("", a:msg)
    endfunction

    function! l:messenger.send_info(msg) dict
        redraw
        echohl None
        echo self.format_message("", a:msg)
    endfunction

    return l:messenger

endfunction

""}}}

" Preview Class {{{1
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! s:NewPreview(name,mainfile,...)
  let l:preview = {} 
  
  if a:0 > 2
    let l:preview["interface"] = call(function(a:3), [l:preview])
  else
    let l:preview["interface"] = call(function(g:preview_host_interface), [l:preview])
  endif

  let l:preview["files"] = []
  let l:preview["name"] = a:name
  let l:preview["mainfile"] = a:mainfile
  let l:preview["expanded"] = 0

  function! l:preview.activate() dict
    echomsg "opening interface for " . self.mainfile
    let self.pid = self.interface.open()
    echomsg "adding file"
    call self.add_file(self.mainfile)
    echomsg "updating interface"
    call self.interface.update()
    echomsg "returning pid"
    return self.pid
  endfunction
 
  function! l:preview.deactivate() dict
    let l:old_number = winnr()
    call self.interface.close()
    for l:file in self.files
      self.remove_file(l:file)
    endfor
    execute l:old_number . "wincmd w"
  endfunction

  function! l:preview.add_file(filename) dict
    if index(self.files, a:filename) >= 0
      call add(self.files,a:filename)
      let l:bufnumber = bufnr(a:filename)
      let l:old_number = winnr()
      buffer l:bufnumber
      autocmd! AutoPreview BufWritePost <buffer> :silent PreviewUpdate(self.name)
      let b:preview_buffer_preview = self.name
      execute l:old_number . "wincmd w"
    else
      call s:_preview_messenger.send_warning("File " . a:filename . "is already associated with " . self.name )
    endif
  endfunction
 
  function! l:preview.remove_file(filename) dict
    let l:old_number = winnr()
    let l:bn = bufnr(a:filename)
    buffer l:bn
    autocmd! AutoPreview BufWritePost <buffer>
    unlet b:preview_buffer_preview
    call filter(self.files,'v:val =~ ' . a:filename)
    execute l:old_number . "wincmd w"
  endfunction

  function! l:preview.update() dict
    call self.interface.update()
  endfunction

  return l:preview
endfunction

"}}}

" Preview Manager Window {{{
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"
function! s:NewPreviewManager()
  let l:preview_manager = {}
  let l:preview_manager["line_map"] = {}
  let l:preview_manager["bufnum"] = -1 

  function! l:preview_manager.create_buffer() dict
    let self.bufnum = bufnr('__Previews__',1)
    echomsg self.bufnum
    call self.activate_viewport()
    call setbufvar("%","preview_manager",self)
    call setbufvar("%","preview_manager",self)
    call self.setup_buffer_opts()
    call self.setup_buffer_syntax()
    call self.setup_buffer_commands()
    call self.render_buffer()
  endfunction

  function! l:preview_manager.activate_viewport() dict
    let l:bfwn = bufwinnr(self.bufnum)
    if l:bfwn == winnr()
      " we are the current buffer
      return 
    elseif l:bfwn >= 0
      execute l:bfwn . "wincmd w"
    else
      execute 'silent keepalt keepjumps vertical bot ' . self.bufnum
      call self.render_buffer()
      setlocal winfixwidth
    endif
  endfunction

  function! l:preview_manager.setup_buffer_opts() dict
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal nowrap
    set bufhidden=hide
    setlocal nobuflisted
    setlocal nolist
    setlocal noinsertmode
    setlocal nonumber
    setlocal cursorline
    setlocal nospell
    setlocal matchpairs=""
    set ft="preview_manager"
  endfunction

  function! l:preview_manager.setup_buffer_commands() dict
    command! b ToggleFold :call <SID>ToggleFold()
  endfunction

  function! l:preview_manager.setup_buffer_syntax() dict
    if has("syntax") && !(exists('b:did_syntax'))
      syn region PreviewArea start='^[▾▸]' end='^$' transparent contains=PreviewControl,PreviewTitle,PreviewParent,PreviewFile
      syn match PreviewControl '^[▾▸]' contained nextgroup=PreviewTitle skipwhite
      syn match PreviewTitle '\w.\{-\}/'me=e-1 contained nextgroup=PreviewMainFile
      syn match PreviewMainFile '/.\{-\}$' contained nextgroup=PreviewFile
      syn match PreviewFile '\s\{2\}.\{-\}$' contained nextgroup=PreviewFile

      highlight link PreviewControl Statement
      highlight link PreviewTitle Type 
      highlight link PreviewMainFile String 
      highlight link PreviewFile Comment
    endif
  endfunction

  function! l:preview_manager.toggle_fold() dict
    let l:preview_name = self.line_map(string(line("."))
    let l:state = s:preview_catalog[l:preview_name]["expanded"]
    if l:state == 0
      s:preview_catalog[l:preview_name]["expanded"] = 1
    else
      s:preview_catalog[l:preview_name]["expanded"] = 0
    endif
    call self.render_buffer()
  endfunction

  function! l:preview_manager.render_buffer() dict
    execute self.bufnum . "wincmd w"
    setlocal modifiable
    let l:previews = [""]
    let l:line_no = 2
    for l:preview in keys(s:preview_catalog)
      if l:preview.expanded
        let l:lines = []
        let l:line_no += 1
        call add(l:lines, "▾ " . l:preview.name . " " . l:preview.mainfile)
        for l:file in l:preview.files
          let l:child_line = "  "  . l:file
          call add(l:lines,l:child_line) 
          let l:line_no += 1
        endfor
        call add(l:lines,"")
        let self.line_map[string(l:line_no)] = l:preview_name
      else
        let l:line_no += 1
        call add(l:previews, "▸ " . l:preview.name . " (" . len(l:preview.files) . " files)")
        let self.line_map[string(l:line_no)] = l:preview_name
      endif
    endfor
    normal ggdGz
    call append(line("$")-1,l:previews)
    setlocal nomodifiable
  endfunction

  return l:preview_manager
endfunction
" }}}

" Functions Support Commands {{{
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! s:AddFileToPreview(...)
  let l:preview = (a:0 > 0) ? a:1 : s:_get_associated_preview()
  call s:preview_catalog[l:preview].add_file(expand("%"))
endfunction

function! s:DeleteFileFromPreview(...)
  let l:preview = (a:0 > 0) ? a:1 : s:_get_associated_preview()
  call s:preview_catalog[l:preview].remove_file(expand("%"))
endfunction

function! s:UpdatePreview(...)
  let l:preview = (a:0 > 0) ? a:1 : s:_get_associated_preview()
  let s:preview_catalog[l:preview].position = s:preview_catalog[l:preview].get_position()
  call s:preview_catalog[l:preview].update()
endfunction

function! s:DeletePreview(...)
  let l:preview = (a:0 > 0) ? a:1 : s:_get_associated_preview()
  call s:preview_catalog[l:preview].deactivate()
  call remove(s:preview_catalog, l:preview)
endfunction

function! s:NewPreviewObject(overwrite,...)
  echomsg string(a:000)
  if a:0 > 1 
    let l:name = a:2
    let l:notice = 0
  else
    let l:name = expand("%:t:r")
    let l:notice = 1
  endif

  if a:overwrite != ""
    if has_key(s:preview_catalog,l:name)
      remove(s:preview_catalog,l:name) 
    endif
  endif

  let s:preview_catalog[l:name] = s:NewPreview(l:name, expand("%"))
  call s:preview_catalog[l:name].activate()
  echomsg string("activated successfully")

  if l:notice
    call s:_preview_messenger.send_status("Created a preview named '" . l:name . "' for this buffer.")
  endif
endfunction

function! s:TogglePreviewManager()
  if bufnr('__Previews__') > 0
    call s:_preview_manager.activate_viewport()
  else
    call s:_preview_manager.create_buffer()
  endif
endfunction
" }}}

let s:_preview_messenger = s:NewMessenger("")
let s:_preview_manager = s:NewPreviewManager()

command! -bang -nargs=? PreviewNew :call <SID>NewPreviewObject('<bang>',<f-args>)
command! -complete=customlist,<SID>_complete_preview_names -nargs=? PreviewAddFile :call <SID>AddFileToPreview('<f-args>)
command! -complete=customlist,<SID>_complete_preview_names -nargs=? PreviewRemoveFile :call <SID>DeleteFileFromPreiew(<f-args>)
command! -complete=customlist,<SID>_complete_preview_names -nargs=? PreviewUpdate :call <SID>UpdatePreview(<f-args>)
command! -complete=customlist,<SID>_complete_preview_names -nargs=? PreviewClose :call <SID>DeletePreview(<f-args>)
command! PreviewToggleManager :call <SID>TogglePreviewManager()

let g:preview_host_interface = "s:OSXHostScript"

let &cpo = s:save_cpo
