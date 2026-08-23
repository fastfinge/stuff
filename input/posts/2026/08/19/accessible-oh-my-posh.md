Title: An Accessible Theme for Oh My Posh
Published: 2026-08-19
Lead: Oh My Posh is a set of configurations and themes for powershell, that allows dynamic modification of the prompt depending on what you're doing. This is the theme I use as my daily driver, and how I have powershell set up as a screen reader user.
Tags:
- articles
Announce: fedi
Fedi: https://fed.interfree.ca/notes/aq3qpoq1maephhwk
---
Microsoft's Powershell has been my favourite shell for several years now. Not only is it an extremely powerful shell on Windows, it also runs perfectly well on mac and Linux; it tends to be the first thing I set up when configuring a new server, in fact. It's deeply configurable, integrates well with DotNet assemblies, and is well documented and logical. If you haven't explored powershell yourself yet, you absolutely should.

On top of powershell is a tool called [Oh My Posh](https://ohmyposh.dev). It easily lets you configure your title bar and prompt, and have those things change based on what you're doing. For example, if the last command failed, you could display "error" in the prompt. Or if you are in a git repo, the prompt could display your current branch and the status of any changes. The prompt can also display things like the execution time of the last command, the battery charge status of your laptop, and much, much more!  Unfortunately, all of the default profiles included with oh-my-posh display this information with inaccessible emoji icons, Unicode, or colour. So I had to extensively modify the default profile to work better with NVDA. It's quite possible that these modifications made it ugly for sighted users, though. 

If you'd like to set it up, here's the way I have my Windows 11 shell configured for my regular work.  First, of course, you need to download and install oh-my-posh. The easiest way is to launch a terminal, and type:
```
winget install JanDeDobbeleer.OhMyPosh 
```

Next, you need to configure your terminal to actually use it. In powershell, you can type:
```
notepad $profile
```
And edit your profile to load oh-my-posh.  

As an example, here's what I currently have in my powershell profile.  You will need to modify this to work for you; it's just an example of what's possible! At least, you must modify the oh-my-posh --init line to point to a file that actually exists on your computer. You can also remove some of the functions, they're just examples to give you ideas. I have dozens of them, I just included these two as inspiration.

``` powershell
if ($host.Name -eq 'InternalHost')
{
    return
}
Import-Module posh-git
oh-my-posh --init --plain -c "C:\Users\samue\OneDrive\Documents\PowerShell\ohmyposh.toml" --shell pwsh | Invoke-Expression
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}
Import-Module PSReadLine
try {
    Import-Module CompletionPredictor -ErrorAction Stop
} catch {
    Write-Warning "Could not load CompletionPredictor: $($_.Exception.Message)"
}
try {
    Import-Module -Name PSPredictor -ErrorAction Stop
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
}
catch {
    Write-Warning "Could not load PSPredictor. Falling back to History only."
    Set-PSReadLineOption -PredictionSource History
}

Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineKeyHandler -Key Alt+RightArrow -Function AcceptSuggestion
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

function wdocker {
    wsl -d Ubuntu docker @Args
}

function omnivoice {
wdocker run --gpus all -p 8880:8880   -v omnivoice_models:/app/models diogod2r/omnivoice-fastapi:latest
}
```

Next, create ohmyposh.toml where ever you configured your powershell profile to find it. It should look something like this:
``` toml
"$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json"
final_space = true
version = 4
cursor_style="default_blinking"
shell_integration=true
extends="C:\\Users\\samue\\OneDrive\\Documents\\PowerShell\\jandedobbeleer-accessible.omp.json"
```

Modify the extends line to point to a real file on your system, and then create jandedobbeleer-accessible.omp.json. Here's a fully screen reader accessible example you can start with:
``` json
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "blocks": [
    {
      "alignment": "left",
      "segments": [
        {
          "background": "#c386f1",
          "foreground": "#ffffff",
          "style": "diamond",
          "template": " {{ .UserName }} ",
          "trailing_diamond": "|",
          "type": "session"
        },
        {
          "background": "#ff479c",
          "foreground": "#ffffff",
          "powerline_symbol": "|",
          "options": {
            "folder_separator_icon": " / ",
            "home_icon": "~",
            "style": "folder"
          },
          "style": "powerline",
          "template": "   {{ .Path }} ",
          "type": "path"
        },
        {
          "background": "#fffb38",
          "background_templates": [
            "{{ if or (.Working.Changed) (.Staging.Changed) }}#FF9248{{ end }}",
            "{{ if and (gt .Ahead 0) (gt .Behind 0) }}#ff4500{{ end }}",
            "{{ if gt .Ahead 0 }}#B388FF{{ end }}",
            "{{ if gt .Behind 0 }}#B388FF{{ end }}"
          ],
          "foreground": "#193549",
          "powerline_symbol": "|",
          "options": {
            "branch_template": "{{ trunc 25 .Branch }}",
            "fetch_status": true,
            "fetch_upstream_icon": true
          },
          "style": "powerline",
          "template": " {{ .UpstreamIcon }}{{ .HEAD }}{{if .BranchStatus }} {{ .BranchStatus }}{{ end }}{{ if .Working.Changed }} [edit] {{ .Working.String }}{{ end }}{{ if and (.Working.Changed) (.Staging.Changed) }} |{{ end }}{{ if .Staging.Changed }} [staged] {{ .Staging.String }}{{ end }}{{ if gt .StashCount 0 }} [stash] {{ .StashCount }}{{ end }} ",
          "type": "git"
        },
        {
          "background": "#6CA35E",
          "foreground": "#ffffff",
          "powerline_symbol": "|",
          "options": {
            "fetch_version": true
          },
          "style": "powerline",
          "template": " [node] {{ if .PackageManagerIcon }}{{ .PackageManagerIcon }} {{ end }}{{ .Full }} ",
          "type": "node"
        },
        {
          "background": "#8ED1F7",
          "foreground": "#111111",
          "powerline_symbol": "|",
          "options": {
            "fetch_version": true
          },
          "style": "powerline",
          "template": " [go] {{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }} ",
          "type": "go"
        },
        {
          "background": "#4063D8",
          "foreground": "#111111",
          "powerline_symbol": "|",
          "options": {
            "fetch_version": true
          },
          "style": "powerline",
          "template": " [julia] {{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }} ",
          "type": "julia"
        },
        {
          "background": "#FFDE57",
          "foreground": "#111111",
          "powerline_symbol": "|",
          "options": {
            "display_mode": "files",
            "fetch_virtual_env": false
          },
          "style": "powerline",
          "template": " [py] {{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }} ",
          "type": "python"
        },
        {
          "background": "#AE1401",
          "foreground": "#ffffff",
          "powerline_symbol": "|",
          "options": {
            "display_mode": "files",
            "fetch_version": true
          },
          "style": "powerline",
          "template": " [rb] {{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }} ",
          "type": "ruby"
        },
        {
          "background": "#FEAC19",
          "foreground": "#ffffff",
          "powerline_symbol": "|",
          "options": {
            "display_mode": "files",
            "fetch_version": false
          },
          "style": "powerline",
          "template": " [az]{{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }} ",
          "type": "azfunc"
        },
        {
          "background_templates": [
            "{{if contains \"default\" .Profile}}#FFA400{{end}}",
            "{{if contains \"jan\" .Profile}}#f1184c{{end}}"
          ],
          "foreground": "#ffffff",
          "powerline_symbol": "|",
          "options": {
            "display_default": false
          },
          "style": "powerline",
          "template": " [aws] {{ .Profile }}{{ if .Region }}@{{ .Region }}{{ end }} ",
          "type": "aws"
        },
        {
          "background": "#ffff66",
          "foreground": "#111111",
          "powerline_symbol": "|",
          "style": "powerline",
          "template": " [root] ",
          "type": "root"
        },
        {
          "background": "#83769c",
          "foreground": "#ffffff",
          "options": {
            "always_enabled": true
          },
          "style": "plain",
          "template": "<transparent>|</> [time] {{ .FormattedMs }} ",
          "type": "executiontime"
        },
        {
          "background": "#00897b",
          "background_templates": [
            "{{ if gt .Code 0 }}#e91e63{{ end }}"
          ],
          "foreground": "#ffffff",
          "options": {
            "always_enabled": true
          },
          "style": "diamond",
          "template": "<parentBackground>|</> {{ if gt .Code 0 }}[fail {{ .Code }}]{{ else }}[ok]{{ end }} ",
          "type": "status"
        }
      ],
      "type": "prompt"
    },
    {
      "segments": [
        {
          "background": "#0077c2",
          "foreground": "#ffffff",
          "style": "plain",
          "template": "<#0077c2,transparent>|</>  {{ .Name }} <transparent,#0077c2>|</>",
          "type": "shell"
        },
        {
          "background": "#1BD760",
          "foreground": "#111111",
          "invert_powerline": true,
          "powerline_symbol": "|",
          "options": {
            "paused_icon": "[paused] ",
            "playing_icon": "[playing] "
          },
          "style": "powerline",
          "template": " [yt] {{ .Icon }}{{ if ne .Status \"stopped\" }}{{ .Artist }} - {{ .Track }}{{ end }} ",
          "type": "ytm"
        },
        {
          "background": "#f36943",
          "background_templates": [
            "{{if eq \"Charging\" .State.String}}#40c4ff{{end}}",
            "{{if eq \"Discharging\" .State.String}}#ff5722{{end}}",
            "{{if eq \"Full\" .State.String}}#4caf50{{end}}"
          ],
          "foreground": "#ffffff",
          "invert_powerline": true,
          "powerline_symbol": "|",
          "options": {
            "charged_icon": "[charged] ",
            "charging_icon": "[charging] ",
            "discharging_icon": "[discharging] "
          },
          "style": "powerline",
          "template": " {{ if not .Error }}{{ .Icon }}{{ .Percentage }}{{ end }}{{ .Error }} ",
          "type": "battery"
        },
        {
          "background": "#2e9599",
          "foreground": "#111111",
          "invert_powerline": true,
          "leading_diamond": "|",
          "style": "diamond",
          "template": " {{ .CurrentDate | date .Format }} ",
          "type": "time"
        }
      ],
      "type": "rprompt"
    }
  ],
  "console_title_template": "{{ .Shell }} in {{ .Folder }}",
  "final_space": true,
  "version": 4
}
```

Once you have all of the above files created and modified for your system, you should have a fully accessible prompt that changes based on what you're doing, a nicer title bar, and an all new understanding of how to get things done in powershell. Enjoy your new superpowers!