" Init {{{1
if !exists("s:init")
    let s:init = 1
    silent! let s:log = logger#getLogger(expand('<sfile>:t'))

    " Initialize
    let sessions = {}
    let s:workspace = {}
    let s:workspace.sessions = sessions

    call vtr#panes#_ParserTmuxSessions()
endif

" Public functions {{{1
function vtr#panes#Refresh()
    call vtr#panes#_ParserTmuxSessions()
endfunction

" @param from name to id
"        sample: #@vim {'session': 'session-name', 'window': 'window-name', 'pane': 'pane-title', }
" echo vtr#panes#GetTarget({'session': 'session-name', 'window': 'window-name', 'pane': 'pane-title', })
" echo vtr#panes#GetTarget({'pane': 'pane-title', })
" echo vtr#panes#GetTarget({})
"   >>> console:5.1
function vtr#panes#GetTarget(confPane)
    let ses_name = get(a:confPane, 'session', s:workspace.session)
    let win_name = get(a:confPane, 'window', s:workspace.window)
    let pane_name = get(a:confPane, 'pane', s:workspace.pane)

    if has_key(s:workspace.sessions, ses_name)
        let tgt_ses = s:workspace.sessions[ses_name]
        if has_key(tgt_ses.windows, win_name)
            let tgt_win = tgt_ses.windows[win_name]
            if has_key(tgt_win.panes, pane_name)
                let tgt_pane = tgt_win.panes[pane_name]
                return "". ses_name. ":". tgt_win['id']. ".". tgt_pane['id']
            endif
        endif
    endif
    return ''
endfunction

" Private functions {{{1
function vtr#panes#_ParserTmuxActivePane()
    call vtr#ShellCmdLog("tmux list-panes -F \"{'session':'#{session_name}', 'window': '#{window_name}', 'pane': '#{pane_title}', 'paneID': #{pane_index}, 'active': #{pane_active}, }\" >". g:VtrCmdOutput)
    if filereadable(g:VtrCmdOutput)
        let lines = readfile(g:VtrCmdOutput)
        for line in lines
            " {'session':'console', 'window': 'second window', 'pane': 'wilson-OptiPlex-3020', 'paneID': 2, 'active': 1}
            try
                try | exec 'let a_pane='. line  | catch | echo v:exception | endtry
            catch /.*/
                echo "outer catch:" v:exception
            endtry

            if a_pane.active
                let s:workspace['session'] = a_pane['session']
                let s:workspace['window'] = a_pane['window']
                let s:workspace['pane'] = a_pane['pane']
                let s:workspace['paneID'] = a_pane['paneID']

                break
            endif
        endfor
    else
        echoerr "vtr:ParserTmuxSessions() fail: file ". g:VtrCmdOutput. " not existed!"
    endif
endfunction

function vtr#panes#_ParserTmuxSessions()
    call vtr#panes#_ParserTmuxActivePane()

    call vtr#ShellCmdLog("tmux list-sessions -F \"#{session_name}\"  >". g:VtrCmdOutput)

    if filereadable(g:VtrCmdOutput)
        let lines = readfile(g:VtrCmdOutput)
        for line in lines
            " console
            let windows = {}
            let one_session = {}
            let one_session.windows = windows
            let s:workspace.sessions[line] = one_session
            let one_session['name'] = line
        endfor
    else
        echoerr "vtr:ParserTmuxSessions() fail: file ". g:VtrCmdOutput. " not existed!"
    endif

    for [session_name, one_session] in items(s:workspace.sessions)
        call vtr#panes#_ParserTmuxWindows(session_name, one_session)
    endfor

    silent! call s:log.info("Tmux workspace: ", s:workspace)
endfunction

function vtr#panes#_ParserTmuxWindows(session_name, one_session)
    call vtr#ShellCmdLog("tmux list-windows -t '". a:session_name. "' -F \"{'window': '#{window_name}', 'windowID': #{window_index}, 'pane': '#{pane_title}', 'paneID': #{pane_index}, }\"  >". g:VtrCmdOutput)

    if filereadable(g:VtrCmdOutput)
        let lines = readfile(g:VtrCmdOutput)
        for line in lines
            " {'session':'console', 'window': 'second window', 'windowID': 1, 'pane': 'first-pane', 'paneID': 2, }
            try
                try | exec 'let a_window='. line  | catch | echo v:exception | endtry
            catch /.*/
                echo "outer catch:" v:exception
            endtry

            silent! call s:log.info("Tmux window: ", a_window)
            let panes = {}
            let one_window = {}
            let one_window.panes = panes
            let a:one_session.windows[a_window.window] = one_window
            let one_window['name'] = a_window.window
            let one_window['id'] = a_window['windowID']
            let one_window['pane'] = a_window['pane']
            let one_window['paneID'] = a_window['paneID']
        endfor
    else
        echoerr "vtr:ParserTmuxWindows() fail: file ". g:VtrCmdOutput. " not existed!"
    endif

    for window in values(a:one_session.windows)
        call vtr#panes#_ParserTmuxPanes(a:session_name, window)
    endfor
endfunction

function vtr#panes#_ParserTmuxPanes(session_name, window)
    call vtr#ShellCmdLog("tmux list-panes -t '". a:session_name. ":". a:window['id']. "' -F \"{'pane': '#{pane_title}', 'paneID': #{pane_index}, }\" >". g:VtrCmdOutput)

    if filereadable(g:VtrCmdOutput)
        let lines = readfile(g:VtrCmdOutput)
        for line in lines
            " {'pane': 'first-pane', 'paneID': 1, }
            try
                try | exec 'let a_pane='. line  | catch | echo v:exception | endtry
            catch /.*/
                echo "outer catch:" v:exception
            endtry

            silent! call s:log.info("Tmux pane: ", a_pane)
            let one_pane = {}
            let a:window.panes[a_pane.pane] = one_pane
            let one_pane['name'] = a_pane['pane']
            let one_pane['id'] = a_pane['paneID']
        endfor
    else
        echoerr "vtr:ParserTmuxPanes() fail: file ". g:VtrCmdOutput. " not existed!"
    endif
endfunction

" vim: set fdm=marker
