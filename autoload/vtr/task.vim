" Init {{{1
if !exists("s:init")
    let s:init = 1
    silent! let s:log = logger#getLogger(expand('<sfile>:t'))

    " Initialize
    let sessions = {}
    let s:task = []
    let s:workspace.sessions = sessions
    let s:workspace['haveMark'] = 0
    let s:workspace['haveActive'] = 0

    call vtr#panes#_ParserTmuxSessions()
endif

" Public functions {{{1
function vtr#panes#Refresh()
    call vtr#panes#_ParserTmuxSessions()
endfunction

function vtr#panes#GetUserPane(ses_name, win_name, pane_name, is_alt)
    let ses_name = a:ses_name
    if !ses_name
        let ses_name = s:workspace.currSession
    endif

    let win_name = a:win_name
    if !win_name
        let win_name = s:workspace.currWindow
    endif

    let pane_name = a:pane_name
    if !pane_name
        let pane_name = s:workspace.currPane
    endif

    if has_key(s:workspace.sessions, ses_name)
        let tgt_ses = s:workspace.sessions[ses_name]
        if has_key(tgt_ses.windows, win_name)
            let tgt_win = tgt_ses.windows[win_name]
            if has_key(tgt_win.panes, pane_name)
                let tgt_pane = tgt_win.panes[pane_name]
                if a:is_alt && has_key(tgt_pane, 'haveAlt') && tgt_pane.haveAlt
                    return "". ses_name. ":". tgt_win['id']. ".". tgt_pane['altPaneID']
                else
                    return "". ses_name. ":". tgt_win['id']. ".". tgt_pane['id']
                endif
            endif
        endif
    endif
    return ''
endfunction

" @param from name to id
"        sample: #@vim {'session': 'session-name', 'window': 'window-name', 'pane': 'pane-title', 'alt': 1}
" echo vtr#panes#GetTarget({'session': 'session-name', 'window': 'window-name', 'pane': 'pane-title', })
" echo vtr#panes#GetTarget({'pane': 'pane-title', })
" echo vtr#panes#GetTarget({})
"   >>> console:5.1
function vtr#panes#GetUserDict(confPane)
    let ses_name  = get(a:confPane, 'session', s:workspace.currSession)
    let win_name  = get(a:confPane, 'window', s:workspace.currWindow)
    let pane_name = get(a:confPane, 'pane', s:workspace.currPane)
    let is_alt    = get(a:confPane, 'alt', 1)
    return vtr#panes#GetUserPane(ses_name, win_name, pane_name, is_alt)
endfunction

function vtr#panes#GetMarkPane()
    if s:workspace.haveMark
        return ''. s:workspace['markSession']. ":". s:workspace['markWindowID']. ".". s:workspace['markPaneID']
    endif
    return ''
endfunction

function vtr#panes#GetAltPane(ses_name, win_name, pane_name)
    return vtr#panes#GetUserPane(a:ses_name, a:win_name, a:pane_name, 1)
endfunction

function vtr#panes#GetActivePane()
    if s:workspace.haveActive
        return ''. s:workspace['currSession']. ":". s:workspace['currWindowID']. ".". s:workspace['currPaneID']
    endif
    return ''
endfunction

" @param format should only use single-quota '
function! vtr#panes#TmuxInfo(format, target, out_file)
    " TODO: this should accept optional target pane, default to current.
    " Pass that to TargetedCommand as "display-message", "-p '#{...}')
    let cmdstr = "tmux display-message "
    if empty(a:format)
        silent! call s:log.error("TmuxInfo fail, format is empty! ", a:format)
        return ''
    endif

    if !empty(a:target)
        let cmdstr = cmdstr. " -t '". a:target. "'"
    endif
    let cmdstr = cmdstr. " -p \"" . a:format . "\""
    if !empty(a:out_file)
        let cmdstr = cmdstr. "  > ". a:out_file
    endif
    let out_str = vtr#ShellCmdLog(cmdstr)
    let out_str = vtr#Strip(out_str)
    silent! call s:log.info("TmuxInfo: ", out_str)
    return out_str
endfunction

" Private functions {{{1
function vtr#panes#_ParserTmuxActivePane()
    let _func = "vtr#ParserTmuxActivePane() "
    let s:workspace['haveActive'] = 0
    let outstr = vtr#panes#TmuxInfo("{'session':'#{session_name}', 'window': '#{window_name}', 'windowID': '#{window_index}', 'pane': '#{pane_title}', 'paneID': '#{pane_index}', }",
                                    \ '', '')
    if !empty(outstr)
        " {'session':'work', 'window': 'console', 'pane': 'pane1', 'paneID': 5, }
        try
            silent! call s:log.debug(_func, outstr)
            exec 'let a_pane='. outstr

            let s:workspace['haveActive'] = 1
            let s:workspace['currSession'] = a_pane['session']
            if g:VtrFindWindowByName
                let s:workspace['currWindow'] = a_pane['window']
            else
                let s:workspace['currWindow'] = a_pane['windowID']
            endif
            let s:workspace['currWindowID'] = a_pane['windowID']
            if g:VtrFindPaneByName
                let s:workspace['currPane'] = a_pane['pane']
            else
                let s:workspace['currPane'] = a_pane['paneID']
            endif
            let s:workspace['currPaneID'] = a_pane['paneID']
        catch
            "echo v:exception
            silent! call s:log.error(_func, "exception:", v:exception, " outstr=", outstr)
        endtry
    else
        "echoerr "vtr:ParserTmuxActivePane() fail! ". outstr
        silent! call s:log.error(_func, "our_str is empty! ", outstr)
    endif
endfunction

" Only one marked-pane shared by all sessions/windows
function vtr#panes#_ParserTmuxMarkedPane()
    let _func = "vtr#ParserTmuxMarkedPane() "

    let s:workspace['haveMark'] = 0
    let outstr = vtr#panes#TmuxInfo("{'session':'#{session_name}', 'window': '#{window_name}', 'windowID': '#{window_index}', 'pane': '#{pane_title}', 'paneID': '#{pane_index}', }",
                                    \ '~', '')
    if !empty(outstr)
        " Only one line
        "   'no marked target'
        " <or>
        "   {'session':'work', 'window': 'console', 'pane': 'pane1', 'paneID': 6, }
        if outstr !=# 'no marked target'
            try
                silent! call s:log.debug(_func, outstr)
                exec 'let a_pane='. outstr
                let s:workspace['haveMark'] = 1

                let s:workspace['markSession'] = a_pane['session']

                if g:VtrFindWindowByName
                    let s:workspace['markWindow'] = a_pane['window']
                else
                    let s:workspace['markWindow'] = a_pane['windowID']
                endif

                let s:workspace['markWindowID'] = a_pane['windowID']

                if g:VtrFindPaneByName
                    let s:workspace['markPane'] = a_pane['pane']
                else
                    let s:workspace['markPane'] = a_pane['paneID']
                endif

                let s:workspace['markPaneID'] = a_pane['paneID']
            catch
                "echo v:exception
                silent! call s:log.error(_func, "exception:", v:exception, " outstr=", outstr)
            endtry
        endif
    else
        "echoerr "vtr:ParserTmuxMarkedPane() fail: ". outstr
        silent! call s:log.error(_func, " out_str is empty!", outstr)
    endif
endfunction

function vtr#panes#_ParserTmuxSessions()
    let _func = "vtr#ParserTmuxSessions() "

    call vtr#panes#_ParserTmuxMarkedPane()
    call vtr#panes#_ParserTmuxActivePane()
    call vtr#panes#TmuxInfo("#{session_name}", '', g:VtrCmdOutput)

    if filereadable(g:VtrCmdOutput)
        let lines = readfile(g:VtrCmdOutput)
        for line in lines
            let line = vtr#Strip(line)
            if empty(line) | continue | endif

            " console
            let windows = {}
            let one_session = {}
            let one_session.windows = windows
            let s:workspace.sessions[line] = one_session
            let one_session['name'] = line
        endfor
    else
        "echoerr "vtr:ParserTmuxSessions() fail: file ". g:VtrCmdOutput. " not existed!"
        silent! call s:log.error(_func, "fail: file ", g:VtrCmdOutput, " not existed!")
    endif

    for [session_name, one_session] in items(s:workspace.sessions)
        call vtr#panes#_ParserTmuxWindows(session_name, one_session)
    endfor

    silent! call s:log.info(_func, "Tmux workspace: ", s:workspace)
endfunction

function vtr#panes#_ParserTmuxWindows(session_name, one_session)
    let _func = "vtr#ParserTmuxWindows() "
    call vtr#panes#TmuxInfo("{'window': '#{window_name}', 'windowID': '#{window_index}', 'pane': '#{pane_title}', 'paneID': '#{pane_index}', }",
                            \ '', g:VtrCmdOutput)

    if filereadable(g:VtrCmdOutput)
        let lines = readfile(g:VtrCmdOutput)
        for line in lines
            " {'session':'console', 'window': 'second window', 'windowID': 1, 'pane': 'first-pane', 'paneID': 2, }
            let line = vtr#Strip(line)
            if empty(line) | continue | endif
            try
                silent! call s:log.debug(_func, "Tmux window: ", line)
                exec 'let a_window='. line

                let panes = {}
                let one_window = {}
                let one_window.panes = panes
                if g:VtrFindWindowByName
                    let a:one_session.windows[a_window.window] = one_window
                else
                    let a:one_session.windows[a_window.windowID] = one_window
                endif
                let one_window['name'] = a_window.window
                let one_window['id'] = a_window['windowID']
                let one_window['pane'] = a_window['pane']
                let one_window['paneID'] = a_window['paneID']
            catch /.*/
                echo "outer catch:" v:exception
            endtry
        endfor
    else
        "echoerr "vtr:ParserTmuxWindows() fail: file ". g:VtrCmdOutput. " not existed!"
        silent! call s:log.error(_func, "file ", g:VtrCmdOutput, " not existed!")
    endif

    for window in values(a:one_session.windows)
        call vtr#panes#_ParserTmuxPanes(a:session_name, window)
    endfor
endfunction

function vtr#panes#_ParserTmuxPanes(session_name, window)
    let _func = "vtr#ParserTmuxPanes() "
    call vtr#ShellCmdLog("tmux list-panes -t '". a:session_name. ":". a:window['id']. "' -F \"{'pane': '#{pane_title}', 'paneID': '#{pane_index}', }\" >". g:VtrCmdOutput)

    if filereadable(g:VtrCmdOutput)
        let lines = readfile(g:VtrCmdOutput)

        let haveAltPane = 0
        if len(lines) == 2
            let haveAltPane = 1
            let paneFirst = ''
            let panePeer = ''
        endif

        for line in lines
            " {'pane': 'first-pane', 'paneID': 1, }
            let line = vtr#Strip(line)
            if empty(line) | continue | endif

            try
                silent! call s:log.debug(_func, "Tmux pane: ", line)
                exec 'let a_pane='. line

                let one_pane = {}
                if g:VtrFindPaneByName
                    let a:window.panes[a_pane.pane] = one_pane
                else
                    let a:window.panes[a_pane.paneID] = one_pane
                endif
                let one_pane['name'] = a_pane['pane']
                let one_pane['id'] = a_pane['paneID']

                if haveAltPane
                    if empty(paneFirst)
                        if g:VtrFindPaneByName
                            let paneFirst = a_pane['pane']
                        else
                            let paneFirst = a_pane['paneID']
                        endif
                    elseif empty(panePeer)
                        if g:VtrFindPaneByName
                            let panePeer = a_pane['pane']
                        else
                            let panePeer = a_pane['paneID']
                        endif
                    endif
                endif
            catch /.*/
                echo "outer catch:" v:exception
            endtry
        endfor

        if haveAltPane && !empty(paneFirst) && !empty(panePeer)
              \ && paneFirst !~# panePeer
              \ && has_key(a:window.panes, paneFirst)
              \ && has_key(a:window.panes, panePeer)
            let pane1 = a:window.panes[paneFirst]
            let pane2 = a:window.panes[panePeer]

            let pane1['haveAlt'] = 1
            let pane1['altPane'] = pane2['name']
            let pane1['altPaneID'] = pane2['id']

            let pane2['haveAlt'] = 1
            let pane2['altPane'] = pane1['name']
            let pane2['altPaneID'] = pane1['id']
        endif
    else
        "echoerr "vtr:ParserTmuxPanes() fail: file ". g:VtrCmdOutput. " not existed!"
        silent! call s:log.error(_func, "file ", g:VtrCmdOutput, " not existed!")
    endif
endfunction

" vim: set fdm=marker
