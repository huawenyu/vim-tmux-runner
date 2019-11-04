" SafeGuard {{{1
if exists('g:loaded_tmux_runner') || &compatible
    finish
endif
let g:loaded_tmux_runner = 0
command! VtrLoad let g:loaded_tmux_runner = 1

" Config {{{1
if !exists("g:VtrUseVtrMaps")      | let g:VtrUseVtrMaps = 0               | endif
if !exists("g:VtrPercentage")      | let g:VtrPercentage = 20              | endif
if !exists("g:VtrOrientation")     | let g:VtrOrientation = 'v'            | endif
if !exists("g:VtrInitialCommand")  | let g:VtrInitialCommand = ''          | endif
if !exists("g:VtrGitCdUpOnOpen")   | let g:VtrGitCdUpOnOpen = 0            | endif
if !exists("g:VtrClearBeforeSend") | let g:VtrClearBeforeSend = 1          | endif
if !exists("g:VtrPrompt")          | let g:VtrPrompt = 'Command to run: '  | endif
if !exists("g:VtrClearOnReorient") | let g:VtrClearOnReorient = 1          | endif
if !exists("g:VtrClearOnReattach") | let g:VtrClearOnReattach = 1          | endif
if !exists("g:VtrDetachedName")    | let g:VtrDetachedName = 'VTR_Pane'    | endif
if !exists("g:VtrClearSequence")   | let g:VtrClearSequence = ""       | endif
if !exists("g:VtrDisplayPaneNum")  | let g:VtrDisplayPaneNum = 1           | endif
if !exists("g:VtrStripLeadSpace")  | let g:VtrStripLeadSpace = 1           | endif
if !exists("g:VtrClearEmptyLines") | let g:VtrClearEmptyLines = 1          | endif
if !exists("g:VtrAppendNewline")   | let g:VtrAppendNewline = 0            | endif
if !exists("g:VtrWaitSec")         | let g:VtrWaitSec = 4                  | endif
if !exists("g:VtrUseMarkStart")    | let g:VtrUseMarkStart = 'u'           | endif
if !exists("g:VtrUseMarkEnd")      | let g:VtrUseMarkEnd = 'n'             | endif
if !exists("g:VtrCmdOutput")       | let g:VtrCmdOutput = '/tmp/vim.yank'  | endif
if !exists("g:VtrVimPrefix")       | let g:VtrVimPrefix = '#@vim'          | endif

" Constructor {{{1
call vtr#DefineCommands()
call vtr#DefineKeymaps()

" vim: set fdm=marker
