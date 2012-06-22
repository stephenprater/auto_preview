" auto_preview.vim: preview html / css in a browser without having to hit
" refresh all of the goddamn time
" it also provides a plugin interface to write preview modules for other kinds
" of files.  like maybe a JPG file you're generating from imagemagick or
" something
"
" Maintainer:    Stephen Prater <me@stephenprater.com>
" Last Modified: 2012-06-06 
" Version:       0.0
"
if exists('g:loaded_auto_preview')
    finish
endif

"let g:loaded_auto_preview = 1
"
let s:save_cpo = &cpo
set cpo&vim

let s:this_vim = $VIM 
let s:preview_catalog = {}
let s:interface_catalog = {}

" Utility Functions {{{1
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! s:_complete_preview_names(arglead, cmdline, cursorpos)
  return sort(keys(s:preview_catalog))
endfunction

function! s:_get_interface_for_file(filename)
  let l:ftype = ""
  if bufnr(a:filename) > 0
    let l:ftype = getbufvar(bufnr(a:filename),'&filetype')
  else
    let l:ftype = expand(a:filename . ":e")
  endif
  let l:interface_arr = get(s:interface_catalog,l:ftype,s:interface_catalog["*"])
  return l:interface_arr
endfunction

function! s:_get_associated_preview()
  let l:preview = getbufvar(bufnr("%"),"preview_buffer_preview")
  return l:preview ? l:preview : g:preview_default_preview
endfunction

function! s:_format_fixed_width(str, len)
  if len(a:str) > a:len
    return strpart(a:str, 0, a:len - 4) . " ..."
  elseif len(a:str) < a:len
    let l:padding = repeat(" ", a:len - len(a:str))
    return a:str . l:padding
  endif
  return a:str
endfunction

"function! g:PreviewLog(string)
"  exec 'redir >> ' . expand("~/auto_preview.log")
"  echo (a:string)
"  exec 'redir END'
"endfunction

"}}}

" Host Script Interface {{{
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"
" Host Script Abstract Parent Class {{{2
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! g:PreviewNewHostScript(preview)
  let l:interface = {}
  let l:interface["preview"] = a:preview
  let l:interface["messenger"] = s:_preview_messenger
  let l:interface["manager"] = s:_preview_manager

  function! l:interface.open() dict
    s:_preview_messenger.send_error("Preview would have opened, but is not setup.")
  endfunction

  function! l:interface.update() dict
    s:_preview_messenger.send_error("Preview would have updated, but is not setup.")
  endfunction

  function! l:interface.close() dict
    s:_preview_messenger.send_error("Preview would have closed, but is not setup.")
  endfunction

  return l:interface
endfunction
" }}}2 

" }}}

" Messaging {{{1
" generalized messenger class
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
function! s:NewPreview(name,mainfile,interface)
  let l:preview = {} 

  echomsg string(call(a:interface['func'], [l:preview]))
  
  let l:preview["interface"] = call(a:interface['func'], [l:preview])
  let l:preview["interface_name"] = string(a:interface['func'])
  let l:preview["event"] = a:interface['event']
  let l:preview["delay"] = a:interface['delay']
  let l:preview["files"] = []
  let l:preview["name"] = a:name
  let l:preview["mainfile"] = a:mainfile
  let l:preview["expanded"] = 0
  let l:preview["info"] = 0

  function! l:preview.activate() dict
    call self.interface.open()
    call self.add_file(self.mainfile)
    call self.interface.update()
    return self.pid
  endfunction
 
  function! l:preview.deactivate() dict
    let l:old_number = winnr()
    call self.interface.close()
    let self.deleting = 1
    for l:file in self.files
      call self.remove_file(l:file)
    endfor
    execute l:old_number . "wincmd w"
  endfunction

  function! l:preview.add_file(filename) dict
    if index(self.files, a:filename) <= 0
      call add(self.files,a:filename)
      let l:bufnumber = bufwinnr(bufnr(a:filename))
      let l:old_number = winnr()
      execute l:bufnumber . "wincmd w"
      augroup AutoPreview
        execute "autocmd! AutoPreview " . self.event . " <buffer> :silent PreviewUpdate " . self.name
      augroup END

      let b:preview_buffer_preview = self.name
      execute l:old_number . "wincmd w"
    else
      call s:_preview_messenger.send_warning("File " . a:filename . "is already associated with " . self.name )
    endif
  endfunction
 
  function! l:preview.remove_file(filename) dict
    " well fuck. no combination of \\s and + seems to work here.
    " well, WTF, I know it's always going to be two, so two it is
    let l:filename = substitute(a:filename,"^\\s\\s","","")

    echomsg self.mainfile
    if l:filename == self.mainfile && !has_key(self,"deleting")
      call s:_preview_messenger.send_warning("Removed primary file from the preview.")
    endif
   
    let l:old_number = winnr()
    let l:bn = bufnr(l:filename)
    execute bufwinnr(l:bn) . "wincmd w"
    execute "autocmd! AutoPreview " . self.event . " <buffer>"
    call filter(self.files,'v:val != "' . l:filename . '"')
    echomsg string(self.files)
    execute l:old_number . "wincmd w"
  endfunction

  function! l:preview.update(immediate) dict
    if self.delay > 0 && has("clientserver") && v:servername != ''
      system("(sleep " . self.delay "; " . s:this_vim " --servername " . v:servername . " --remote-send ':UpdatePreview! ". self.name . "<CR>')&")
      echomsg "delayed update called"
      return
    endif

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
  let l:preview_manager["show_help"] = 0

  function! l:preview_manager.create_buffer() dict
    let self.bufnum = bufnr('__Previews__',1)
    call self.activate_viewport()
    call setbufvar("%","preview_manager",self)
    call self.setup_buffer_opts()
    call self.setup_buffer_syntax()
    call self.setup_buffer_commands()
    call self.render_buffer()
  endfunction

  function! l:preview_manager.render_help() dict
    " NOTE - if you add help here, make sure the change the number of lines
    " added to the buffer in the render function
    let old_h = @h

    let @h =  "┌─────────────────────────────────────────────────────────┐\n"
    let @h=@h."| " . self.keys_for_action('expand') .  ": Show files associated with the        |\n"
    let @h=@h."|                   the selected previews.                |\n"
    let @h=@h."| " . self.keys_for_action('jump') .    ": Jump to buffer containing file.       |\n"
    let @h=@h."| " . self.keys_for_action('refresh') . ": Refresh selected preview.             |\n"
    let @h=@h."|                   Also - reopen an accidentally closed  |\n"
    let @h=@h."|                   preview window.                       |\n"
    let @h=@h."| " . self.keys_for_action('edit') .    ": Change preview property               |\n"
    let @h=@h."| " . self.keys_for_action('redraw') .  ": Refresh the preview manager window.   |\n"
    let @h=@h."| " . self.keys_for_action('delete') .  ": Remove file from selected preview.    |\n"
    let @h=@h."| " . self.keys_for_action('info') .    ": Close and delete selected preview.    |\n"
    let @h=@h."| " . self.keys_for_action('wipe') .    ": Show information about the preview.   |\n"
    let @h=@h."| " . self.keys_for_action('help') .     ": This help.                            |\n"
    let @h=@h."└─────────────────────────────────────────────────────────┘"
    silent! put h
    let @h = old_h
  endfunction

  function! l:preview_manager.keys_for_action(action) dict
    return s:_format_fixed_width(join(s:preview_manager_keys[a:action],","), 16)
  endfunction

  function! l:preview_manager.toggle_help() dict
    let self.show_help = self.show_help ? 0 : 1
  endfunction

  function! l:preview_manager.redraw() dict
    call self.activate_viewport()
  endfunction

  function! l:preview_manager.activate_viewport() dict
    if self.bufnum == -1
      call self.create_buffer()
      return
    endif
      
    let l:bfwn = bufwinnr(self.bufnum)
    if l:bfwn == winnr()
      " we are the current bufferif l:bfwn >= 0
      call self.render_buffer()
      return
    elseif l:bfwn >= 0
      execute l:bfwn . "wincmd w"
    else
      echomsg self.bufnum
      execute 'silent vertical bot sb ' . self.bufnum
      setlocal winfixwidth
    endif
    call self.render_buffer()
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
    command! -b ExpandLine call b:preview_manager.line_action("expand",line("."))
    command! -b JumpLine call b:preview_manager.line_action("jump",line("."))
    command! -b RefreshLine call b:preview_manager.line_action("refresh",line("."))
    command! -b EditLine call b:preview_manager.line_action("edit",line("."))
    command! -b DeleteLine call b:preview_manager.line_action("delete",line("."))
    command! -b WipeLine call b:preview_manager.line_action("wipe",line("."))
    command! -b InfoLine call b:preview_manager.line_action("info",line("."))
    " Buffer wide actions 
    command! -b RedrawBuffer call b:preview_manager.redraw() 
    command! -b DisplayHelp call b:preview_manager.toggle_help() | RedrawBuffer

    noremap <Plug>ExpandLine :ExpandLine<CR>
    noremap <Plug>JumpLine :JumpLine<CR>
    noremap <Plug>RefreshLine :RefreshLine<CR>
    noremap <Plug>EditLine :EditLine<CR>
    noremap <Plug>DeleteLine :DeleteLine<CR>
    noremap <Plug>WipeLine :WipeLine<CR>
    noremap <Plug>InfoLine :InfoLine<CR>

    noremap <Plug>RedrawBuffer :<SID>RedrawBuffer<CR>
    noremap <Plug>DisplayHelp :<SID>DisplayHelp<CR>

    let l:actions = ['help', 'redraw']

    for l:key in s:preview_manager_keys['help']
      execute "map <buffer> " . l:key . " <Plug>DisplayHelp"
    endfor

    for l:key in s:preview_manager_keys['redraw']
      execute "map <buffer> " . l:key . " <Plug>RedrawBuffer"
    endfor
    
    let l:actions = ['expand', 'jump', 'refresh', 'edit', 'redraw', 'delete', 'info', 'wipe']
    for l:action in l:actions
      let l:plug = toupper(l:action[0]) . l:action[1:-1] . "Line"
      for l:key in s:preview_manager_keys[l:action]
        execute "map <buffer> " . l:key . " <Plug>" . l:plug
      endfor
    endfor 
    
  endfunction

  function! l:preview_manager.setup_buffer_syntax() dict
    if has("syntax") && !(exists('b:did_syntax'))
      syn region PreviewArea start='^[▾▸]' end='^$' transparent contains=PreviewControl,PreviewTitle,PreviewParent,PreviewFile,PreviewInfo
      syn region PreviewHelp start="^┌─*─┐" end="^└─*─┘"
      syn region PreviewInfo start='^\s\s┌─*─┐' end='^\s\s└─*─┘'  contains=PreviewAttributeRO, PreviewAttributeValue
      syn match PreviewControl '^[▾▸]' contained nextgroup=PreviewTitle skipwhite
      syn match PreviewTitle '\w.\{-\}\s'me=e-1 contained nextgroup=PreviewMainFile
      syn match PreviewMainFile '\s.\{-\}$' contained nextgroup=PreviewFile
      syn match PreviewFile '\s\{2\}[^|┌└]\{-\}$' contained nextgroup=PreviewFile
      syn match PreviewAttributeRO '\(Preview Id\).\{-\}|'me=e-1 contained
      syn match PreviewAttributeValue ':\s.\{-\}|'ms=s+2,me=e-2 contained
      syn match PreviewNoActive '\[No Active Previews\]'

      highlight link PreviewControl Statement
      highlight link PreviewTitle Type 
      highlight link PreviewMainFile Identifier 
      highlight link PreviewFile String 
      highlight link PreviewHelp Comment
      highlight link PreviewInfo PreviewHelp
      highlight link PreviewAttributeValue StatusLineNC 
      highlight link PreviewAttributeRO Constant 
      highlight link PreviewNoActive Type
      call setbufvar("%","did_syntax",1)
    endif
  endfunction

  function! l:preview_manager.line_action(action, line_no) dict
    if !has_key(self.line_map,string(a:line_no))
      " there's no warning or anything the mapping just doesn't work
      call s:_preview_messenger.send_info("Not a valid key for that line")
      return
    endif
    
    let l:preview = self.line_map[string(a:line_no)]
    if has_key(l:preview, a:action)
      if a:action == "expand"
        call self.toggle_state("expanded",l:preview["name"])
      elseif a:action == "jump"
        call self.jump_to_file(l:preview[a:action])
      elseif a:action == "refresh"
        call s:_preview_catalog[l:preview["name"]].update()
      elseif a:action == "edit"
        call self.edit_attribute(l:preview["name"],l:preview[a:action])
      elseif a:action == "delete"
        call s:_preview_catalog(l:preview["name"]).remove_file(l:preview[a:action])
      elseif a:action == "info"
        call self.toggle_state("info",l:preview["name"])
      elseif a:action == "wipe"
        call s:_preview_catalog(l:preview["name"]).deactivate()
      endif
    endif
  endfunction
  
  function! l:preview_manager.jump_to_file(file) dict
    " AGAIN - why can't i make this freaking sub work right?
    let l:bfnr = bufwinnr(bufnr(a:file))
    if l:bfnr > 0
      execute l:bfnr . "wincmd w"
    else
      " jump to the previous windows, split horizontally and open
      " the requested buffer.  this functionality could be classier
      " so at somepoint i probably want to deal with the windowing
      " issues a little better
      let l:bfnr = bufnr(a:file) 
      if l:bfnr > 0
        execute "wincmd p | sb " . l:bfnr
      endif
    endif
  endfunction

  function! l:preview_manager.toggle_state(preview, state) dict
    if !has_key(self.line_map, string(a:line_no))
      call s:_preview_messenger.send_info("No preview at line " . string(a:line_no))
      return
    endif
    let l:preview_name = self.line_map[string(a:line_no)]
    let l:state = s:preview_catalog[l:preview_name][a:state]
    if l:state == 0
      let s:preview_catalog[l:preview_name][a:state] = 1
    else
      let s:preview_catalog[l:preview_name][a:state] = 0
    endif
    call self.render_buffer()
  endfunction

  function! l:preview_manager.line_out(line, ...)
    if !has_key(self, "lines")
      let self["lines"] = []
    endif
    let l:map_line = string(len(self.lines)+1)
    call add(self.lines, a:line)
    return l:map_line
  endfunction

  function! l:preview_manager.current_line()
    if !has_key(self, "lines")
      return 0
    else
      return len(self.lines) + 1
    endif
  endfunction

  function! l:preview_manager.actions_for_previous_lines(length, preview, actions)
    let l:current_line = self.current_line()
    if l:current_line - a:length <= 0 
      throw "Whoops - that would associate lines with the wrong actions"
    endif

    let l:line_offset = (l:current_line - (a:length + 1)) - 1) 

    for l:key in keys(a:action)
      if type(a:action[l:key]) == 3 "list?
        let l:actions = a:action[l:key]
      else
        let l:actions = [a:action[l:key]]
      endif

      if l:key == "*"
        let l:op_lines = range((l:current_line - a:length + 1) - 1, l:current_line)
      else
        let l:op_line = str2nr(l:key) + l:line_offset
      endif
      
      for l:op_line in         for l:action in l:actions
          let l:action_info = matchlist('edit','\(\w\{1,\}\)\(,\s\?\(\w\{1,\}\)\)\?$')
          let l:action = l:action_info[1]
          let l:subject = l:action_info[3]
          call self.add_action_to_line(l:op_line, a:preview, l:action, l:subject 
      endfor
 
      let l:op_line = str2nr(l:key) + l:line_offset
      call self.add_action_to_line(l:op_line,a:action[l:key])

      endif

    endfor
  endfunction

  function! l:preview_manager.add_action_to_line(line_no,...)
    if a:0 > 0 && !empty(a:1)
      let l:preview_name = a:1 
    endif
    if a:0 > 1 && !empty(a:2)
      let l:action = a:2
    endif
    if a:0 > 2 && !empty(a:3)
      let l:subject = a:3
    endif

    " if it exists for a preview, then add mapping for it
    if exists(l:preview_name)
      let self.line_map[a:line_no][l:preview_name] = {}
      if exists(l:action)
        if exists(l:subject)
          " if the action has a particular subject, store it
          let self.line_map[a:line_no][l:action] = l:subject
        else
          let self.line_map[a:line_no][l:action] = 1
        endif
      endif
    endif
  endfunction

  function! l:preview_manager.show_info(preview)
    let l:preview = a:preview
    if l:preview.info
       call self.line_out("  ┌──────────────────────────────────────────────┐",l:preview)                     "1
       call self.line_out("  | Preview Id  :  " . s:_format_fixed_width(l:preview.pid,30) . "|")              "2
       call self.line_out("  | Script Type :  " . s:_format_fixed_width(l:preview.interface_name,30) . "|")   "3
       call self.line_out("  | Delay       :  " . s:_format_fixed_width(l:preview.delay,30). "|")             "4
       call self.line_out("  | Event       :  " . s:_format_fixed_width(l:preview.event,30). "|")             "5
       call self.line_out("  └──────────────────────────────────────────────┘",l:preview)                     "6
       call self.previous_line_actions(6,l:preview.name, {
             \ "*" : "info",
             \ "3" : "edit, interface",
             \ "4" : "edit, delay",
             \ "5" : "edit, event",
             \ })
    endif
  endfunction

  function! l:preview_manager.render_buffer() dict
    let l:current_line = line(".")
    execute self.bufnum . "wincmd w"
    setlocal modifiable
    let self.line_map = {}
    for l:preview_key in keys(s:preview_catalog)
      let l:preview = s:preview_catalog[l:preview_key]
      if l:preview.expanded
        let l:line_no = self.line_out("▾ " . l:preview.name . " " . l:preview.mainfile, l:preview.name, 'expand')
        call self.add_action_to_line(l:line_no,"info",l:preview.name)
        call self.show_info(l:preview)
        for l:file in l:preview.files
          let l:child_line = "  "  . l:file
          call self.line_out(l:child_line, l:preview,'jump',l:file)
        endfor
        call self.line_out("","")
      else
        call self.line_out("▸ " . l:preview.name . " (" . len(l:preview.files) . " files)", l:preview.name, 'expand')
        call self.show_info(l:preview)
      endif
    endfor
    "jump to the top of the buffer, delete to the end, then append
    "the rendered lines, then jump back to the top
    normal ggdGz
    if len(keys(s:preview_catalog)) == 0
      "wow... that's excessive
      let old_h = @h
      let @h = "  [No Active Previews]  "
      silent! put h
      let @h = old_h
    else
      echomsg string(keys(s:preview_catalog))
      call append(line("$")-1, self.lines)
      call remove(self,"lines")
    endif
    
    if self.show_help
      call self.render_help()
    endif
    execute ":" . l:current_line
    setlocal nomodifiable
  endfunction

  return l:preview_manager
endfunction
" }}}

" Functions Support Commands {{{
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! s:AddFileToPreview(...)
  let l:preview = (a:0 > 0) ? a:1 : s:_get_associated_preview()
  let l:file_name = (a:0 > 1) ? a:2 : expand("%")
  call s:preview_catalog[l:preview].add_file(expand("%"))
  call s:UpdatePreviewManager()
endfunction

function! s:DeleteFileFromPreview(...)
  let l:preview = (a:0 > 0) ? a:1 : s:_get_associated_preview()
  let l:file_name = (a:0 > 1) ? a:2 : expand("%")
  call s:preview_catalog[l:preview].remove_file(l:file_name)
  call s:UpdatePreviewManager()
endfunction

function! s:UpdatePreview(immediate, ...)
  let l:preview = (a:0 > 0) ? a:1 : s:_get_associated_preview()
  let l:immediate = (a:immediate != "!" ) ? 0 : 1 
  call s:preview_catalog[l:preview].update(l:immediate)
endfunction

function! s:DeletePreview(...)
  let l:preview = (a:0 > 0) ? a:1 : s:_get_associated_preview()
  call s:preview_catalog[l:preview].deactivate()
  call remove(s:preview_catalog, l:preview)
  call s:UpdatePreviewManager()
  call s:_preview_messenger.send_status("Deleted preview " . l:preview)
endfunction

function! s:NewPreviewObject(overwrite, ...)

  " l:name - the name of the preview to create
  " l:filename - the 'mainfile' which is the file that get's
  "    actually opened by the previewer
  
  if a:0 > 1 
    let l:name = a:2
  else
   let l:name = expand("%:t:r")
  endif

  if a:0 > 2 
    let l:filename = a:3
  else
    let l:filename = expand("%")
  endif
  
  if has_key(s:preview_catalog,l:name)
    if a:overwrite != "!"
      call s:_preview_messenger.send_warning("Preview " . l:name . "already exists.  Add ! to overwrite")
      return
    else
      remove(s:preview_catalog,l:name) 
    endif
  endif

  " determine which interface to use
  let l:interface = s:_get_interface_for_file(l:filename)

  let s:preview_catalog[l:name] = s:NewPreview(l:name, l:filename, l:interface)
  call s:preview_catalog[l:name].activate()

  call s:_preview_messenger.send_status("Created a preview named '" . l:name . "' for this buffer.")
  call s:UpdatePreviewManager()
endfunction

function! s:TogglePreviewManager()
  if bufnr('__Previews__') > 0
    call s:_preview_manager.activate_viewport()
  else
    call s:_preview_manager.create_buffer()
  endif
endfunction

function! s:UpdatePreviewManager()
  let l:preview_manager = bufwinnr(bufnr('__Previews__'))
  if l:preview_manager > 0
    let l:current_buffer = bufnr("%")
    call s:_preview_manager.activate_viewport()
    execute bufwinnr(l:current_buffer) . "wincmd w"
  endif
endfunction
" }}}

" Public API Functions {{{
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function! PreviewAddInterface(filetype, func, event, ... )
  let l:overwrite = 0
  if a:0 > 0
    let l:overwrite = a:1
  endif

  let l:filetypes = split(a:filetype,",")
  for l:ftype in l:filetypes
    if has_key(s:interface_catalog, l:ftype) && !l:overwrite
      call s:_preview_messenger.send_warning('Interface ' . l:ftype . ' already exists.')
      continue
    endif
    let s:interface_catalog[l:ftype] = {
          \ 'func' : a:func,
          \ 'event' : a:event,
          \ 'delay' : 0,
          \ }
  endfor
endfunction
"}}}

let s:_preview_messenger = s:NewMessenger("")
let s:_preview_manager = s:NewPreviewManager()

let g:previews = s:preview_catalog
let g:interfaces = s:interface_catalog

command! -bang -complete=file -nargs=* PreviewNew :call <SID>NewPreviewObject('<bang>',<f-args>)
command! -complete=customlist,<SID>_complete_preview_names -nargs=? PreviewAddFile :call <SID>AddFileToPreview(<f-args>)
command! -complete=customlist,<SID>_complete_preview_names -nargs=? PreviewRemoveFile :call <SID>DeleteFileFromPreview(<f-args>)
command! -bang -complete=customlist,<SID>_complete_preview_names -nargs=? PreviewUpdate :call <SID>UpdatePreview('<bang>',<f-args>)
command! -complete=customlist,<SID>_complete_preview_names -nargs=? PreviewClose :call <SID>DeletePreview(<f-args>)
command! PreviewManager :call <SID>TogglePreviewManager()

" this is the default previewer, which simply messages that it would have
" previewed if it could, and only on 'User' events, which are never
" fired by default
call PreviewAddInterface('*',function('g:PreviewNewHostScript'),'User')

" Load additional interfaces
runtime! preview_plugins/**/*.vim

if exists('g:preview_manager_keys')
  let s:preview_manager_keys = g:preview_manager_keys
else
  let s:preview_manager_keys = { 
      \ 'expand'  : ["o","c","<Space>"],
      \ 'jump'    : ["<CR>"],
      \ 'refresh' : ["r","u","<F5>"],
      \ 'edit'    : ["e","c","i"],
      \ 'redraw'  : ["R"],
      \ 'delete'  : ["D"],
      \ 'info'    : ["i"],
      \ 'wipe'    : ["X"],
      \ 'help'    : ["?"],
      \ }
endif

let &cpo = s:save_cpo
