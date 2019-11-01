" SafeGuard {{{1
if exists('g:loaded_tmux_runner')
  finish
endif
let g:loaded_tmux_runner = 1
silent! let s:log = logger#getLogger(expand('<sfile>:t'))

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

" VarInit {{{1
let s:osprompt = ''
let s:runner_marker = 0
let s:runner_window = -1
let s:vtr_percentage = g:VtrPercentage
let s:vtr_orientation = g:VtrOrientation
let s:vtr_wait_period = 300  | "milliseconds.
let s:vtr_wait_sec = g:VtrWaitSec * 1000
let s:vtr_wait_count = s:vtr_wait_sec / s:vtr_wait_period

" @result: 0 not-waiting,
"          1 waiting, 2 wait-succ, 3 wait-timeout
"         -1 request err
"         -2 interrupt by user: active paste from tmux-buffer
"
" @stop_mode:   0 wait prompt, 1 wait lines
" @output_mode: 0 ignore, 1 insert here
let s:vtr_wait_result = {'async': 0, 'stop_mode': 0, 'output_mode': 0, 'min': 0, 'max': 0, 'timer': 0, 'timer_cnt': 0, 'result': 0, }

" Functions {{{1
function! s:DictFetch(dict, key, default)
    if has_key(a:dict, a:key)
        return a:dict[a:key]
    else
        return a:default
    endif
endfunction

function! s:CreateRunnerPane(...)
    if exists("a:1")
        let s:vtr_orientation = s:DictFetch(a:1, 'orientation', s:vtr_orientation)
        let s:vtr_percentage = s:DictFetch(a:1, 'percentage', s:vtr_percentage)
        let g:VtrInitialCommand = s:DictFetch(a:1, 'cmd', g:VtrInitialCommand)
    endif
    let s:vim_window = s:ActiveWindowIndex()
    let s:vim_pane = s:ActivePaneIndex()
    let cmd = join(["split-window -p", s:vtr_percentage, "-".s:vtr_orientation])
    call s:SendTmuxCommand(cmd)
    let s:runner_window = s:ActiveWindowIndex()
    let s:runner_pane = s:ActivePaneIndex()
    call s:FocusVimPane()
    if g:VtrGitCdUpOnOpen
        call s:GitCdUp()
    endif
    if g:VtrInitialCommand != ""
        call s:SendKeys(g:VtrInitialCommand)
    endif
endfunction

function! s:DetachRunnerPane()
    if !s:ValidRunnerPaneSet() | return | endif
    call s:BreakRunnerPaneToTempWindow()
    let cmd = join(["rename-window -t", s:detached_window, g:VtrDetachedName])
    call s:SendTmuxCommand(cmd)
endfunction

function! s:ValidRunnerPaneSet()
    let marked_pane = s:SendTmuxCommand("display-message -p -t '~'")
    if marked_pane !=# 'no marked target'
        let s:runner_marker = 1
        let s:runner_window = s:MarkedWindowIndex()
        let s:runner_pane = s:MarkedPaneIndex()
        return 1
    endif

    if !exists("s:runner_pane")
        call s:EchoError("No runner pane attached.")
        return 0
    endif
    if !s:ValidRunnerPaneNumber(s:runner_pane)
        call s:EchoError("Runner pane setting (" . s:runner_pane . ") is invalid. Please reattach.")
        return 0
    endif
    return 1
endfunction

function! s:DetachedWindowOutOfSync()
  let window_map = s:WindowMap()
  if index(keys(window_map), s:detached_window) == -1
    return 1
  endif
  if s:WindowMap()[s:detached_window] != g:VtrDetachedName
    return 1
  endif
  return 0
endfunction

function! s:DetachedPaneAvailable()
  if exists("s:detached_window")
    if s:DetachedWindowOutOfSync()
      call s:EchoError("Detached pane out of sync. Unable to kill")
      unlet s:detached_window
      return 0
    endif
  else
    call s:EchoError("No detached runner pane.")
    return 0
  endif
  return 1
endfunction

function! s:RequireLocalPaneOrDetached()
    if !exists('s:detached_window') && !exists('s:runner_pane')
        call s:EchoError("No pane, local or detached.")
        return 0
    endif
    return 1
endfunction

function! s:KillLocalRunner()
    if s:ValidRunnerPaneSet()
      let targeted_cmd = s:TargetedTmuxCommand("kill-pane", s:runner_pane)
      call s:SendTmuxCommand(targeted_cmd)
      unlet s:runner_pane
    endif
endfunction

function! s:WindowMap()
  let window_pattern = '\v(\d+): ([-_a-zA-Z]{-})[-\* ]\s.*'
  let window_map = {}
  for line in split(s:SendTmuxCommand("list-windows"), "\n")
    let dem = split(substitute(line, window_pattern, '\1:\2', ""), ':')
    let window_map[dem[0]] = dem[1]
  endfor
  return window_map
endfunction

function! s:KillDetachedWindow()
    if !s:DetachedPaneAvailable() | return | endif
    let cmd = join(["kill-window", '-t', s:detached_window])
    call s:SendTmuxCommand(cmd)
    unlet s:detached_window
endfunction

function! s:KillRunnerPane()
    if !s:RequireLocalPaneOrDetached() | return | endif
    if exists("s:runner_pane")
        call s:KillLocalRunner()
    else
        call s:KillDetachedWindow()
    endif
endfunction

function! s:ActiveWindowIndex()
    return str2nr(s:SendTmuxCommand("display-message -p '#{window_index}'"))
endfunction

function! s:ActivePaneIndex()
    return str2nr(s:SendTmuxCommand("display-message -p '#{pane_index}'"))
endfunction

function! s:MarkedWindowIndex()
    return str2nr(s:SendTmuxCommand("display-message -t '~' -p '#{window_index}'"))
endfunction

function! s:MarkedPaneIndex()
    return str2nr(s:SendTmuxCommand("display-message -t '~' -p '#{pane_index}'"))
endfunction

function! s:TmuxPanes()
    let panes = s:SendTmuxCommand("list-panes")
    return split(panes, '\n')
endfunction

function! s:FocusTmuxPane(pane_number)
    let targeted_cmd = s:TargetedTmuxCommand("select-pane", a:pane_number)
    call s:SendTmuxCommand(targeted_cmd)
endfunction

function! s:RunnerPaneDimensions()
    let panes = s:TmuxPanes()
    for pane in panes
        if pane =~ '^'.s:runner_pane
            let pattern = s:runner_pane.': [\(\d\+\)x\(\d\+\)\]'
            let pane_info =  matchlist(pane, pattern)
            return {'width': pane_info[1], 'height': pane_info[2]}
        endif
    endfor
endfunction

function! s:FocusRunnerPane(should_zoom)
    if !s:ValidRunnerPaneSet() | return | endif
    call s:FocusTmuxPane(s:runner_pane)
    if a:should_zoom
        call s:SendTmuxCommand("resize-pane -Z")
    endif
endfunction

function! s:Strip(string)
    return substitute(a:string, '^\s*\(.\{-}\)\s*\n\?$', '\1', '')
endfunction

function! s:SendTmuxCommand(command)
    let prefixed_command = "tmux " . a:command
    let out_str = s:Strip(system(prefixed_command))

    if a:command =~# 'send-keys .*'
        silent! call s:log.info("TmuxKeys=[", a:command, "]")
    else
        silent! call s:log.info('TmuxCmd=[', a:command, ']')
    endif
    return out_str
endfunction

function! s:TargetedTmuxCommand(command, target_pane)
    if s:runner_marker
        return a:command . " -t " . s:runner_window . ".". a:target_pane
    else
        return a:command . " -t ". a:target_pane
    endif
endfunction

function! s:_SendKeys(keys)
    let targeted_cmd = s:TargetedTmuxCommand("send-keys", s:runner_pane)
    let full_command = join([targeted_cmd, a:keys])
    call s:SendTmuxCommand(full_command)
endfunction

function! s:SendKeys(keys)
    let cmd = g:VtrClearBeforeSend ? g:VtrClearSequence.a:keys : a:keys
    call s:_SendKeys(cmd)
    call s:SendEnterSequence()
endfunction

function! s:SendEnterSequence()
    call s:_SendKeys("Enter")
endfunction

function! s:SendClearSequence()
    if !s:ValidRunnerPaneSet() | return | endif
    call s:SendTmuxCopyModeExit()
    call s:_SendKeys(g:VtrClearSequence)
endfunction

function! s:SendQuitSequence()
    if !s:ValidRunnerPaneSet() | return | endif
    call s:_SendKeys("q")
endfunction

function! s:GitCdUp()
    let git_repo_check = "git rev-parse --git-dir > /dev/null 2>&1"
    let cdup_cmd = "cd './'$(git rev-parse --show-cdup)"
    let cmd = shellescape(join([git_repo_check, '&&', cdup_cmd]))
    call s:SendTmuxCopyModeExit()
    call s:SendKeys(cmd)
    call s:SendClearSequence()
endfunction

function! s:FocusVimPane()
    call s:FocusTmuxPane(s:vim_pane)
endfunction

function! s:LastWindowNumber()
    return split(s:SendTmuxCommand("list-windows"), '\n')[-1][0]
endfunction

function! s:ToggleOrientationVariable()
    let s:vtr_orientation = (s:vtr_orientation == "v" ? "h" : "v")
endfunction

function! s:BreakRunnerPaneToTempWindow()
    let targeted_cmd = s:TargetedTmuxCommand("break-pane", s:runner_pane)
    let full_command = join([targeted_cmd, "-d"])
    call s:SendTmuxCommand(full_command)
    let s:detached_window = s:LastWindowNumber()
    let s:vim_pane = s:ActivePaneIndex()
    unlet s:runner_pane
endfunction

function! s:RunnerDimensionSpec()
    let dimensions = join(["-p", s:vtr_percentage, "-".s:vtr_orientation])
    return dimensions
endfunction

function! s:TmuxInfo(message)
  " TODO: this should accept optional target pane, default to current.
  " Pass that to TargetedCommand as "display-message", "-p '#{...}')
  return s:SendTmuxCommand("display-message -p '#{" . a:message . "}'")
endfunction

function! s:PaneCount()
  return str2nr(s:TmuxInfo('window_panes'))
endfunction

function! s:PaneIndices()
  let index_slicer = 'str2nr(substitute(v:val, "\\v(\\d+):.*", "\\1", ""))'
  return map(s:TmuxPanes(), index_slicer)
endfunction

function! s:AvailableRunnerPaneIndices()
  return filter(s:PaneIndices(), "v:val != " . s:ActivePaneIndex())
endfunction

function! s:AltPane()
  if s:PaneCount() == 2
    return s:AvailableRunnerPaneIndices()[0]
  else
    echoerr "AltPane only valid if two panes open"
  endif
endfunction

function! s:AttachToPane(...)
  if exists("a:1") && a:1 != ""
    call s:AttachToSpecifiedPane(a:1)
  elseif s:PaneCount() == 2
    call s:AttachToSpecifiedPane(s:AltPane())
  else
    call s:PromptForPaneToAttach()
  endif
endfunction

function! s:PromptForPaneToAttach()
  if g:VtrDisplayPaneNum
    call s:SendTmuxCommand('source ~/.tmux.conf && tmux display-panes')
  endif
  echohl String | let desired_pane = input('Pane #: ') | echohl None
  if desired_pane != ''
    call s:AttachToSpecifiedPane(desired_pane)
  else
    call s:EchoError("No pane specified. Cancelling.")
  endif
endfunction

function! s:CurrentMajorOrientation()
  let orientation_map = { '[': 'v', '{': 'h' }
  let layout = s:TmuxInfo('window_layout')
  let outermost_orientation = substitute(layout, '[^[{]', '', 'g')[0]
  return orientation_map[outermost_orientation]
endfunction

function! s:AttachToSpecifiedPane(desired_pane)
  let desired_pane = str2nr(a:desired_pane)
  if s:ValidRunnerPaneNumber(desired_pane)
    let s:runner_pane = desired_pane
    let s:vim_pane = s:ActivePaneIndex()
    let s:vtr_orientation = s:CurrentMajorOrientation()
    echohl String | echo "\rRunner pane set to: " . desired_pane | echohl None
  else
    call s:EchoError("Invalid pane number: " . desired_pane)
  endif
endfunction

function! s:EchoError(message)
  echohl ErrorMsg | echo "\rVTR: ". a:message | echohl None
endfunction

function! s:DesiredPaneExists(desired_pane)
  return count(s:PaneIndices(), a:desired_pane) == 0
endfunction

function! s:ValidRunnerPaneNumber(desired_pane)
  if a:desired_pane == s:ActivePaneIndex() | return 0 | endif
  if s:DesiredPaneExists(a:desired_pane) | return 0 | endif
  return 1
endfunction

function! s:ReattachPane()
    if !s:DetachedPaneAvailable() | return | endif
    let s:vim_pane = s:ActivePaneIndex()
    call s:_ReattachPane()
    call s:FocusVimPane()
    if g:VtrClearOnReattach
        call s:SendClearSequence()
    endif
endfunction

function! s:_ReattachPane()
    let join_cmd = join(["join-pane", "-s", ":".s:detached_window.".0",
        \ s:RunnerDimensionSpec()])
    call s:SendTmuxCommand(join_cmd)
    unlet s:detached_window
    let s:runner_pane = s:ActivePaneIndex()
endfunction

function! s:ReorientRunner()
    if !s:ValidRunnerPaneSet() | return | endif
    call s:BreakRunnerPaneToTempWindow()
    call s:ToggleOrientationVariable()
    call s:_ReattachPane()
    call s:FocusVimPane()
    if g:VtrClearOnReorient
        call s:SendClearSequence()
    endif
endfunction

function! s:HighlightedPrompt(prompt)
    echohl String | let input = shellescape(input(a:prompt)) | echohl None
    return input
endfunction

function! s:FlushCommand()
    if exists("s:user_command")
        unlet s:user_command
    endif
endfunction

function! s:SendTmuxCopyModeExit()
    let l:session = s:TmuxInfo('session_name')
    let l:win = s:TmuxInfo('window_index')
    let l:target_cmd = join([l:session.':'.l:win.".".s:runner_pane])
    if s:SendTmuxCommand("display-message -p -F '#{pane_in_mode}' -t " . l:target_cmd)
        call s:SendQuitSequence()
    endif
endfunction

function! s:SendCommandToRunner(ensure_pane, ...)
    if a:ensure_pane | call s:EnsureRunnerPane() | endif
    if !s:ValidRunnerPaneSet() | return | endif
    if exists("a:1") && a:1 != ""
        let s:user_command = shellescape(a:1)
    endif
    if !exists("s:user_command")
        let s:user_command = s:HighlightedPrompt(g:VtrPrompt)
    endif
    let escaped_empty_string = "''"
    if s:user_command == escaped_empty_string
        unlet s:user_command
        call s:EchoError("command string required")
        return
    endif
    call s:SendTmuxCopyModeExit()
    if g:VtrClearBeforeSend
        call s:SendClearSequence()
    endif
    call s:SendKeys(s:user_command)
endfunction

function! s:EnsureRunnerPane(...)
    if exists('s:detached_window')
        call s:ReattachPane()
    elseif exists('s:runner_pane')
        return
    else
        if exists('a:1')
            call s:CreateRunnerPane(a:1)
        else
            call s:CreateRunnerPane()
        endif
    endif
endfunction

function! s:SendLinesToRunner(ensure_pane) range
    if a:ensure_pane | call s:EnsureRunnerPane() | endif
    if !s:ValidRunnerPaneSet() | return | endif
    call s:SendTmuxCopyModeExit()

    " Try check mark first: xX as start-end region
    let line_s = line("'x")
    let line_e = line("'X")
    if line_s > 0 && line_e > 0
        call s:SendTextToRunner(getline(line_s, line_e))
    else
        call s:SendTextToRunner(getline(a:firstline, a:lastline))
    endif
endfunction

function! s:PrepareLines(lines)
    let prepared = a:lines
    if g:VtrStripLeadSpace
        let prepared = map(a:lines, 'substitute(v:val,"^\\s*","","")')
    endif
    if g:VtrClearEmptyLines
        let prepared = filter(prepared, "!empty(v:val)")
    endif
    if g:VtrAppendNewline && len(a:lines) > 1
        let prepared = add(prepared, "\r")
    endif
    return prepared
endfunction

function! s:SendTextToRunner(lines)
    if !s:ValidRunnerPaneSet() | return | endif
    let prepared = s:PrepareLines(a:lines)
    let joined_lines = join(prepared, "\r") . "\r"
    let send_keys_cmd = s:TargetedTmuxCommand("send-keys", s:runner_pane)
    let s:user_command = shellescape(joined_lines)
    let targeted_cmd = send_keys_cmd . ' ' . s:user_command
    call s:SendTmuxCommand(targeted_cmd)
endfunction

function! s:SendCtrlD()
  if !s:ValidRunnerPaneSet() | return | endif
  call s:SendTmuxCopyModeExit()
  call s:SendKeys('')
endfunction

function! s:SendFileViaVtr(ensure_pane)
    let runners = s:CurrentFiletypeRunners()
    if has_key(runners, &filetype)
        write
        let runner = runners[&filetype]
        let local_file_path = expand('%')
        let run_command = substitute(runner, '{file}', local_file_path, 'g')
        call VtrSendCommand(run_command, a:ensure_pane)
    else
        echoerr 'Unable to determine runner'
    endif
endfunction

function! s:CurrentFiletypeRunners()
    let default_runners = {
            \ 'elixir': 'elixir {file}',
            \ 'javascript': 'node {file}',
            \ 'python': 'python {file}',
            \ 'ruby': 'ruby {file}',
            \ 'sh': 'sh {file}'
            \ }
    if exists("g:vtr_filetype_runner_overrides")
      return extend(copy(default_runners), g:vtr_filetype_runner_overrides)
    else
      return default_runners
    endif
endfunction

function! VtrSendCommand(command, ...) range
    let ensure_pane = 0
    if exists("a:1")
        let ensure_pane = a:1
    endif

    call s:SendCommandToRunner(ensure_pane, a:command)
endfunction

function! VtrSendCommandEx(mode)
    if a:mode ==# 'n'
        " Try check mark first: xX as start-end region
        let cur_line = line('.')
        let mark_1 = line("'". g:VtrUseMarkStart)
        let mark_2 = line("'". g:VtrUseMarkEnd)
        if mark_1 > 0 && mark_2 > 0
            silent! call s:log.info("Mark-mode start=", mark_1, " end=", mark_2)
            call s:SendTextToRunner(getline(mark_1, mark_2))
        else
            silent! call s:log.info("CurrentLine-mode=", getline(cur_line, cur_line))
            call s:SendTextToRunner(getline(cur_line, cur_line))
        endif
        return
    elseif a:mode ==# 'v'
        let [select_1, col1] = getpos("'<")[1:2]
        let [select_2, col2] = getpos("'>")[1:2]
        if select_1 > 0 && select_2 > 0
            call s:SendTextToRunner(getline(select_1, select_2))
            return
        endif
    endif
endfunction

function! s:ShellCmd(log, strcmd)
    let strcmd = s:Strip(a:strcmd)
    if a:log | silent! call s:log.info("ShellCmd=[", strcmd, "]") | endif
    return system(strcmd)
endfunction

" Same as VtrSendCommandEx, but capture the output
function! VtrExecuteCommand(mode)
    if s:GuessOSPrompt() < 2
        call s:SendClearSequence()
    endif

    call s:SendClearSequence()
    call s:ShellCmd(1, "tmux clear-history -t '~'")

    call VtrSendCommandEx(a:mode)

    call s:WaitCmdResultAsync(0, 0, 0, 1)
    "call s:SendTmuxCommand("save-buffer -b REPL ". g:VtrCmdOutput)
endfunction

function s:CaptureOutput(strcmd)
    let line_cnt = str2nr(s:Strip(s:ShellCmd(0, a:strcmd)))
    silent! call s:log.info("Lines[", line_cnt, "]: ", a:strcmd)
    return line_cnt
endfunc

function s:TimerProcessResult(timer, result)
    if a:timer | call timer_stop(a:timer) | endif

    " take-action
    if s:vtr_wait_result.async
        let s:vtr_wait_result.result = 0
        if s:vtr_wait_result.output_mode
            exec "read ". g:VtrCmdOutput
        endif
    else
        let s:vtr_wait_result.result = a:result
    endif
endfunc

function! VtrTimerHandlerLine(timer)
    if s:vtr_wait_result.result <= 0
        if a:timer | call timer_stop(a:timer) | endif
        return
    endif

    let s:vtr_wait_result.timer_cnt += 1
    let get_output = "tmux capture-pane -S- -t '~' -p | sed '/^$/d' | tee ". g:VtrCmdOutput." | wc -l"

    if s:vtr_wait_result.timer_cnt >= s:vtr_wait_count
        call s:CaptureOutput(get_output)
        call s:TimerProcessResult(a:timer, 3)
    elseif s:vtr_wait_result.result > 0
        let out_cnt = s:CaptureOutput(get_output)
        "call s:DumpWaitResult("handle line")
        "silent! call s:log.info("out_cnt=", out_cnt)
        if out_cnt >= s:vtr_wait_result.min && out_cnt <= s:vtr_wait_result.max
            call s:TimerProcessResult(a:timer, 2)
        endif
    endif
endfunc

function! VtrTimerHandlerPrompt(timer)
    if s:vtr_wait_result.result <= 0
        if a:timer | call timer_stop(a:timer) | endif
        return
    endif

    let s:vtr_wait_result.timer_cnt += 1
    let get_output = "tmux capture-pane -S- -t '~' -p | awk 'BEGIN{RS=\"\";ORS=\"\\n\\n\"}1' | tee ". g:VtrCmdOutput." | sed -n '2,$s/". s:osprompt ."/&/p' | wc -l"

    if s:vtr_wait_result.timer_cnt >= s:vtr_wait_count
        call s:CaptureOutput(get_output)
        call s:TimerProcessResult(a:timer, 3)
    elseif s:vtr_wait_result.result > 0
        let has_prompt = s:CaptureOutput(get_output)
        if has_prompt > 0
            call s:TimerProcessResult(a:timer, 2)
        endif
    endif
endfunc

function s:DumpWaitResult(funcname)
    silent! call s:log.info("Dump WaitRequest from ", a:funcname, ":", s:vtr_wait_result)
endfunction

" @return bool
function s:WaitCmdInit(_func, async, stop_mode, line_min, line_max, output_mode)

    call s:WaitStopTimer()
    let s:vtr_wait_result.async = a:async
    let s:vtr_wait_result.stop_mode = a:stop_mode
    let s:vtr_wait_result.output_mode = a:output_mode
    if a:stop_mode == 0   | " @stop_mode:   0 wait prompt, 1 wait lines
        if len(s:osprompt) <= 1
            let info = ''. a:_func. "prompt stop_mode but no osprompt, wait timer guess os-prompt!"
            silent! call s:log.info(_func, )
            echomsg "vim-tmux-runner: ". info
            return 0
        endif
    elseif a:stop_mode == 1
        if a:line_min <= 0 && a:line_max <= 0
            let info = ''. a:_func. "line stop_mode but no (min,max) assign!"
            silent! call s:log.info(_func, info)
            echomsg "vim-tmux-runner: ". info
            return 0
        endif
    else
        silent! call s:log.info(_func, "unkown stop_mode!")
        return 0
    endif
    let s:vtr_wait_result.min = a:line_min
    let s:vtr_wait_result.max = a:line_max
    call s:DumpWaitResult(a:_func)
    return 1
endfunction

function s:WaitStopTimer()
    if s:vtr_wait_result.timer
        call timer_stop(s:vtr_wait_result.timer)
        let s:vtr_wait_result.timer = 0
    endif
    let s:vtr_wait_result.timer_cnt = 0
endfunction

" @return when stop_mode=line: the cmd output
"         '': empty line
function s:WaitCmdResult(stop_mode, line_min, line_max, output_mode)
    let _func = 'WaitCmdResult() '

    let chk = s:WaitCmdInit(_func, 0, a:stop_mode, a:line_min, a:line_max, a:output_mode)
    if !chk | let s:vtr_wait_result.result = -1 | return | endif
    let s:vtr_wait_result.result = 1

    let sec = 0
    while sec < s:vtr_wait_sec
        let sec += s:vtr_wait_period
        exec 'sleep '. s:vtr_wait_period. 'm'

        if s:vtr_wait_result.stop_mode == 1
            call VtrTimerHandlerLine(0)
        elseif s:vtr_wait_result.stop_mode == 0
            call VtrTimerHandlerPrompt(0)
        endif

        if s:vtr_wait_result.result < 1 || s:vtr_wait_result.result == 2
            break
        endif
    endwhile

    " Timeout
    if s:vtr_wait_result.result > 0 && sec >= s:vtr_wait_sec
        let s:vtr_wait_result.result = 3
    " Succ
    elseif s:vtr_wait_result.result == 2 && s:vtr_wait_result.stop_mode == 1
        return s:Strip(join(readfile(g:VtrCmdOutput), "\n"))
    endif

    return ''
endfunction

function s:WaitCmdResultAsync(stop_mode, line_min, line_max, output_mode)
    let _func = 'WaitCmdResultAsync() '

    let chk = s:WaitCmdInit(_func, 1, a:stop_mode, a:line_min, a:line_max, a:output_mode)
    if !chk | let s:vtr_wait_result.result = -1 | return | endif
    let s:vtr_wait_result.result = 1

    if a:stop_mode == 1
        let s:vtr_wait_result.timer = timer_start(s:vtr_wait_period, 'VtrTimerHandlerLine', {'repeat': s:vtr_wait_count})
    elseif a:stop_mode == 0
        let s:vtr_wait_result.timer = timer_start(s:vtr_wait_period, 'VtrTimerHandlerPrompt', {'repeat': s:vtr_wait_count})
    endif
endfunction

function s:GuessOSPrompt()
    if len(s:osprompt) == 0
        call s:SendClearSequence()
        call s:ShellCmd(1, "tmux clear-history -t '~'")
        "1sleep
        let s:osprompt = s:WaitCmdResult(1, 1, 1, 0)
        if s:vtr_wait_result.result != 2
            let s:osprompt = ''
        endif
        silent! call s:log.info("osprompt=[", s:osprompt, "]")
        let s:vtr_wait_result.result = 0
        return 2
    endif
    return 1
endfunction

function s:BufferPasteHere()
    let s:vtr_wait_result.result = -2
    call s:WaitStopTimer()
    call s:ShellCmd(1, "tmux capture-pane -S- -t '~' -p | awk 'BEGIN{RS=\"\";ORS=\"\\n\\n\"}1' > ". g:VtrCmdOutput)
    exec "read ". g:VtrCmdOutput
endfunction

function! s:DefineCommands()
    command! -bang -nargs=? VtrSendCommandToRunner call s:SendCommandToRunner(<bang>0, <f-args>)
    command! -bang -range VtrSendLinesToRunner <line1>,<line2>call s:SendLinesToRunner(<bang>0)
    command! -bang VtrSendFile call s:SendFileViaVtr(<bang>0)
    command! -nargs=? VtrOpenRunner call s:EnsureRunnerPane(<args>)
    command! VtrKillRunner call s:KillRunnerPane()
    command! -bang VtrFocusRunner call s:FocusRunnerPane(<bang>!0)
    command! VtrReorientRunner call s:ReorientRunner()
    command! VtrDetachRunner call s:DetachRunnerPane()
    command! VtrReattachRunner call s:ReattachPane()
    command! VtrClearRunner call s:SendClearSequence()
    command! VtrFlushCommand call s:FlushCommand()
    command! VtrSendCtrlD call s:SendCtrlD()
    command! VtrBufferPasteHere call s:BufferPasteHere()
    command! VtrDebugPrompt call s:GuessOSPrompt()
    command! -bang -nargs=? -bar VtrAttachToPane call s:AttachToPane(<f-args>)
endfunction

function! s:DefineKeymaps()
    if g:VtrUseVtrMaps
        nnoremap <leader>va :VtrAttachToPane<cr>
        nnoremap <leader>ror :VtrReorientRunner<cr>
        nnoremap <leader>sc :VtrSendCommandToRunner<cr>
        nnoremap <leader>sl :VtrSendLinesToRunner<cr>
        vnoremap <leader>sl :VtrSendLinesToRunner<cr>
        nnoremap <leader>or :VtrOpenRunner<cr>
        nnoremap <leader>kr :VtrKillRunner<cr>
        nnoremap <leader>fr :VtrFocusRunner<cr>
        nnoremap <leader>dr :VtrDetachRunner<cr>
        nnoremap <leader>cr :VtrClearRunner<cr>
        nnoremap <leader>fc :VtrFlushCommand<cr>
        nnoremap <leader>sf :VtrSendFile<cr>
    endif
endfunction


" Constructor {{{1
call s:DefineCommands()
call s:DefineKeymaps()

" vim: set fdm=marker
