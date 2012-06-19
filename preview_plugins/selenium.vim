if !has('python')
  echoerr 'Selenium Host Interface requires python support.'
  finish
endif

let g:SeleniumPreviewBrowser = "firefox"

python <<PYTHON
try:
  from selenium import webdriver
  from selenium.webdriver.common.keys import Keys
  import sys
  import uuid
except ImportError:
  vim.command('echoerr "The selenium module is not installed.  Try `pip install selenium`"') 
  vim.command('finish')

previews = {}

def get_preview_id():
  """ Get a random id for this preview """
  cmd = "let l:pid = %s" % repr(uuid.uuid4().hex)
  vim.command(cmd)

def show_previews():
  vim.command('call g:PreviewLog("%s")' % repr(previews))

class Preview:
  def __init__(self, browser):
    self.pid = self.preview()['pid']
    if browser == "firefox":
      self.browser = webdriver.Firefox()
    elif browser == "chrome":
      self.browser = webdriver.Chrome()
    elif browser == "ie":
      self.browser = webdriver.Ie()

  def preview(self):
    return vim.eval('self.preview')

  def open(self):
    self.browser.get(self.preview()['file_target'])

  def close(self):
    self.browser.close()
PYTHON

" Selenium Interface for Web Documents
" This interface requires the Python Web Driver 2 interface and Selenium
" It will check to make sure that it's present, but won't install it for you,
" so you'll have to do that yourself.
function! SeleniumHostInterface(preview)
  let l:interface = g:PreviewNewHostScript(a:preview)
  function! l:interface.open()
    " get a uuid from python and set it to the interface PID
    python get_preview_id()
    let self.preview.pid = l:pid
    " the python script itself assigns the local - it's terribly confusing
    " actuallly - there REALLY should be a better way to do this, i think.
    " http://vim.1045645.n5.nabble.com/How-to-get-returned-value-from-python-functions-in-vim-scripts-td4458113.html
    python previews[vim.eval('self.preview.pid')] = Preview(vim.eval('g:SeleniumPreviewBrowser'))
    let self.preview.file_target = "file://" . fnamemodify(self.preview.mainfile,':p')
    python previews[vim.eval('self.preview.pid')].open()
    return l:pid
  endfunction

  function! l:interface.close()
    python previews[vim.eval('self.preview.pid')].close()
  endfunction

  function! l:interface.update()
    call g:PreviewLog('updating')
    python previews[vim.eval('self.preview.pid')].open()
  endfunction

  return l:interface
endfunction

call PreviewAddInterface('html',function('SeleniumHostInterface'),'BufWritePost',1)
