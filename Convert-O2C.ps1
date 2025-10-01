[CmdletBinding()]
param(
   [Parameter(Mandatory=$true)]
   [string]$InputFile,
   [Parameter(Mandatory=$false)]
   [string]$OutputFile = ""
)
$Content = Get-Content -Path $InputFile -Raw -Encoding UTF8
# Convert
# H1-H6
$content = [regex]::Replace($content, '^(#{1,6})\s+(.+)$', {
   $level = $args[0].Groups[1].Value.Length
   "h$level. " + "**" + $args[0].Groups[2].Value + "**"
}, 'Multiline')
# Italic text (*text* → _text_)
$content = [regex]::Replace($content, '(?<!\*)\*([^*]+)\*(?!\*)', '_$1_', 'Multiline')
# Bold text (**text** → *text*)
$content = [regex]::Replace($content, '\*\*([^*]+)\*\*', '*$1*', 'Multiline')
# Strike through (~~text~~* → -text-)
$content = [regex]::Replace($content, '\~\~([^*]+)\~\~', '-$1-', 'Multiline')

# Numbered List (1. → #)
# Bullet List (- or * → *)
function Convert-NestedLists {
   param([string]$content, [int]$indentSize = 2)
   # 番号付きリスト変換
   $content = [regex]::Replace($content, '^(\s*)\d+\.\s+(.+)$', {
       $indent = $args[0].Groups[1].Value
       $text = $args[0].Groups[2].Value
       # タブを指定されたスペース数に変換
       $normalizedIndent = $indent -replace '\t', (' ' * 4)
       $level = [math]::Floor($normalizedIndent.Length / $indentSize) + 1
       $level = [math]::Max(1, $level)  # 最小レベル1
       ('#' * $level) + ' ' + $text
   }, 'Multiline')
   # 箇条書きリスト変換
   $content = [regex]::Replace($content, '^(\s*)[-*+]\s+(.+)$', {
       $indent = $args[0].Groups[1].Value
       $text = $args[0].Groups[2].Value
       # タブを指定されたスペース数に変換
       $normalizedIndent = $indent -replace '\t', (' ' * 4)
       $level = [math]::Floor($normalizedIndent.Length / $indentSize) + 1
       $level = [math]::Max(1, $level)  # 最小レベル1
       ('*' * $level) + ' ' + $text
   }, 'Multiline')
   return $content
}
$content = Convert-NestedLists $content 4 #4スペースインデント

# コードブロック (```lang → {code:lang})
$content = [regex]::Replace($content, '```$', '{code}', 'Multiline')
$content = [regex]::Replace($content, '```([^`]+?)$', '{code:$1}', 'Multiline')

# Inline Code
$content = [regex]::Replace($content, '`([^`]+)`', '{{$1}}', 'Multiline')

 
# テーブルヘッダー行の変換
function Convert-ObsidianTables {
   param([string]$content)
   # テーブルブロックのみを正確にマッチ
   $content = [regex]::Replace($content, '(?m)^(\|[^\r\n]+\|)\r?\n(\|[-\s:|]+\|)\r?\n((?:^\|[^\r\n]+\|\r?\n?)+?)(?=\r?\n\r?\n|\r?\n(?!\|)|\z)', {
       $headerLine = $args[0].Groups[1].Value.Trim()
       $dataLines = $args[0].Groups[3].Value.Trim()
       # ヘッダー行の変換
       $headerCells = ($headerLine -replace '^\||\|$', '' -split '\|') | ForEach-Object { $_.Trim() }
       $confluenceHeader = '|| ' + ($headerCells -join ' || ') + ' ||'
       # データ行の処理
       $confluenceDataLines = ($dataLines -split '\r?\n' | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
           $line = $_.Trim()
           if ($line -match '^\|.*\|$') {
               $cells = ($line -replace '^\||\|$', '' -split '\|') | ForEach-Object { $_.Trim() }
               '| ' + ($cells -join ' | ') + ' |'
           }
       })
       return $confluenceHeader + "`r`n" + ($confluenceDataLines -join "`r`n")
   }, 'Multiline')
   return $content
}
$content = Convert-ObsidianTables $content
# Obsidian Calloutsとquotes
function Convert-CalloutsAndQuotes {
   param([string]$content)
   $lines = $content -split '\r?\n'
   $result = @()
   $i = 0
   while ($i -lt $lines.Length) {
       $line = $lines[$i]
       # Calloutの開始を検出
       if ($line -match '^>\s*\[!(INFO|NOTE|TIP|SUCCESS|QUESTION|CAUTION|FAILURE|WARNING|DANGER|BUG|EXAMPLE|QUOTE)\](.*)$') {
           $calloutType = $matches[1]
           $title = $matches[2].Trim()
           # スタイル定義
           $styles = @{
               'INFO'     = 'borderColor=#2196f3|titleBGColor=#e3f2fd|bgColor=#f8fdff'
               'NOTE'     = 'borderColor=#2196f3|titleBGColor=#e3f2fd|bgColor=#f8fdff'
               'TIP'      = 'borderColor=#39b9d3|titleBGColor=#e3f9fc|bgColor=#f7feff'
               'SUCCESS'  = 'borderColor=#6fd339|titleBGColor=#edfce3|bgColor=#fafff7'
               'QUESTION' = 'borderColor=#8b6bd3|titleBGColor=#e9e3fc|bgColor=#f8f7ff'
               'CAUTION'  = 'borderColor=#ff9800|titleBGColor=#fff3e0|bgColor=#fffbf5'
               'WARNING'  = 'borderColor=#ff9800|titleBGColor=#fff3e0|bgColor=#fffbf5'
               'FAILURE'  = 'borderColor=#f22121|titleBGColor=#ffe0e0|bgColor=#fff4f4'
               'DANGER'   = 'borderColor=#f22121|titleBGColor=#ffe0e0|bgColor=#fff4f4'
               'BUG'      = 'borderColor=#f22121|titleBGColor=#ffe0e0|bgColor=#fff4f4'
               'EXAMPLE'  = 'borderColor=#c57cd6|titleBGColor=#f6e3fc|bgColor=#fcf7ff'
               'QUOTE'    = 'borderColor=#9e9e9e|titleBGColor=#f5f5f5|bgColor=#fafafa'
           }
           $panelParams = $styles[$calloutType]
           if ($title -ne '') {
               $panelParams = "title=$title|$panelParams"
           }
           $result += "{panel:$panelParams}"
           $i++
           # Calloutの本文を収集（Calloutでない > 行のみ）
           while ($i -lt $lines.Length -and $lines[$i] -match '^>\s*([^[].*|$)') {
               $bodyLine = $lines[$i] -replace '^>\s*', ''
               $result += $bodyLine
               $i++
           }
           $result += "{panel}"
       }
       # 通常の引用行
       elseif ($line -match '^>\s*([^[].*|$)') {
           $quoteText = $line -replace '^>\s*', ''
           $result += "{quote}$quoteText{quote}"
           $i++
       }
       # その他の行
       else {
           $result += $line
           $i++
       }
   }
   return $result -join "`r`n"
}
$content = Convert-CalloutsAndQuotes $content

# リンクの段階的な変換
function Convert-ObsidianLinks {
   param([string]$content)
   # 1. 最も単純なケース（記号なし）
   $content = [regex]::Replace($content, '\[([a-zA-Z0-9\s\-_]+)\]\(([^)]+)\)', '[$1|$2]', 'Multiline')
   # 2. 括弧を含むケース
   $content = [regex]::Replace($content, '\[([^\[\]]+)\]\(([^()]*(?:\([^()]*\)[^()]*)*)\)', '[$1|$2]', 'Multiline')
   # 3. 角括弧を含むケース
   $content = [regex]::Replace($content, '\[([^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*)\]\(([^)]+)\)', '[$1|$2]', 'Multiline')
   return $content
}
$content = Convert-ObsidianLinks $content
#
# 出力ファイル名の決定
if ($OutputFile -eq "") {
   $OutputFile = [System.IO.Path]::ChangeExtension($InputFile, ".confluence.txt")
}
# ファイルに出力
$Content | Out-File -FilePath $OutputFile -Encoding UTF8
