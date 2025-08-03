# === UI PANEL IMPLEMENTATIONS ===

class ScorePanel : Panel {
    [int] $Score
    [int] $Lines
    [int] $Level
    [hashtable] $LastDrawnValue = @{}
    hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache

    ScorePanel([int]$x, [int]$y, [int]$w, [int]$h) : base($x, $y, $w, $h, "SCORE") {
        $this._RowCache = [System.Collections.Generic.Dictionary[int,string]]::new()
    }

    [void] Render() {
        $current = @{ Score = $this.Score }
        if (-not (Compare-Hashtable $this.LastDrawnValue $current)) {
            $this.DrawFrame()

            $label = "Score: $($this.Score)"
            $pad   = ' ' * [Math]::Max(0, $this.Width - $label.Length)
            $final = $label + $pad

            $rowY = $this.Y + 1
            $rowX = $this.X + 1

            if (-not $this._RowCache.ContainsKey($rowY) -or $this._RowCache[$rowY] -ne $final) {
                [Console]::SetCursorPosition($rowX, $rowY)
                [Console]::Write($final)
                $this._RowCache[$rowY] = $final
            }

            $this.LastDrawnValue = $current.Clone()
        }
    }
}

class LinesPanel : Panel {
    [int] $Lines
    [int] $LastDrawnLines = -1

    LinesPanel([int]$x, [int]$y, [int]$w, [int]$h) : base($x, $y, $w, $h, "") { }

    [void] Render() {
        if ($this.Lines -ne $this.LastDrawnLines) {
            $this.DrawFrame()

            $label = "LINES - " + $this.Lines.ToString("D3")
            $textX = $this.X + [int](($this.Width - $label.Length) / 2) + 1
            $textY = $this.Y + 1  # First line inside the frame

            # Clear the entire text line inside the frame
            Write-CursorPositionIfChanged ($this.X + 1) $textY
            [Console]::Write(' ' * $this.Width)

            # Write the label centered
            Write-CursorPositionIfChanged $textX $textY
            [Console]::Write($label)

            $this.LastDrawnLines = $this.Lines
        }
    }
}

class LevelPanel : Panel {
    [int] $Level
    [int] $LastDrawnLevel = -1
    hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache

    LevelPanel([int]$x, [int]$y, [int]$w, [int]$h) : base($x, $y, $w, $h, "") {
        $this._RowCache = [System.Collections.Generic.Dictionary[int,string]]::new()
    }

    [void] Render() {
        if ($this.Level -ne $this.LastDrawnLevel) {
            $this.DrawFrame()

            $label1 = "LEVEL"
            $label2 = $this.Level.ToString("D2")

            $textY1 = $this.Y + 1
            $textY2 = $this.Y + 2

            $textX1 = $this.X + [int](($this.Width - $label1.Length) / 2) + 1
            $textX2 = $this.X + [int](($this.Width - $label2.Length) / 2) + 1

            # First row
            if (-not $this._RowCache.ContainsKey($textY1) -or $this._RowCache[$textY1] -ne $label1) {
                [Console]::SetCursorPosition($textX1, $textY1)
                [Console]::Write($label1)
                $this._RowCache[$textY1] = $label1
            }

            # Second row
            if (-not $this._RowCache.ContainsKey($textY2) -or $this._RowCache[$textY2] -ne $label2) {
                [Console]::SetCursorPosition($textX2, $textY2)
                [Console]::Write($label2)
                $this._RowCache[$textY2] = $label2
            }

            $this.LastDrawnLevel = $this.Level
        }
    }
}

class NextPanel : Panel {
    [string] $NextId
    [hashtable] $Colors
    [string] $LastDrawnId = ''
    hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache
    hidden [System.Text.StringBuilder] $_LineBuilder

    NextPanel([int]$x, [int]$y, [int]$w, [int]$h, [hashtable]$colors) : base($x, $y, $w, $h, "NEXDT") {
        $this.Colors = $colors
        $this._RowCache = [System.Collections.Generic.Dictionary[int,string]]::new()
        $this._LineBuilder = [System.Text.StringBuilder]::new(128)
    }

    [void] Render() {
        if ($this.NextId -ne $this.LastDrawnId) {
            $this.DrawFrame()
            $this.DrawNextPreview()
            $this.LastDrawnId = $this.NextId
        }
    }

    [void] DrawNextPreview() {
        $blocks = $global:TetrominoShapes[$this.NextId][0]
        $rgb    = $this.Colors[$this.NextId]

        $mm = [Panel]::GetMinMax($blocks)
        $minX = $mm.MinX
        $maxX = $mm.MaxX
        $minY = $mm.MinY
        $maxY = $mm.MaxY

        $pieceWidth  = $maxX - $minX + 1
        $pieceHeight = $maxY - $minY + 1

        $cellWidth = $script:RENDER_CELL_WIDTH
        $panelCols = $this.Width / $cellWidth
        $panelRows = $this.Height

        $offsetX = [math]::Floor(($panelCols  - $pieceWidth) / 2)
        $offsetY = [math]::Floor(($panelRows - $pieceHeight) / 2)

        # Build a map of which (x,y) cells are occupied
        $occupied = @{}
        foreach ($b in $blocks) {
            $x = $b.X - $minX + $offsetX
            $y = $b.Y - $minY + $offsetY
            if ($x -ge 0 -and $x -lt $panelCols -and $y -ge 0 -and $y -lt $panelRows) {
                $occupied["{$x}:{$y}"] = $true
            }
        }

        $esc = [char]27
        $ansiBlock = "$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m██$esc[0m"
        $blank = ' ' * $cellWidth

        for ($row = 0; $row -lt $this.Height; $row++) {
            $this._LineBuilder.Clear()

            for ($col = 0; $col -lt $panelCols; $col++) {
                $key = "{$col}:{$row}"
                if ($occupied.ContainsKey($key)) {
                    $null = $this._LineBuilder.Append($ansiBlock)
                } else {
                    $null = $this._LineBuilder.Append($blank)
                }
            }

            $str = $this._LineBuilder.ToString()
            $consoleY = $this.Y + 1 + $row
            $consoleX = $this.X + 1

            if (-not $this._RowCache.ContainsKey($consoleY) -or $this._RowCache[$consoleY] -ne $str) {
                [Console]::SetCursorPosition($consoleX, $consoleY)
                [Console]::Write($str)
                $this._RowCache[$consoleY] = $str
            }
        }
    }
}

class StatsPanel : Panel {
    [hashtable] $Counts
    [hashtable] $LastDrawnCounts = @{}
    hidden [System.Text.StringBuilder] $_LineBuilder
    hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache

    StatsPanel([int]$x, [int]$y, [int]$w, [int]$h) : base($x, $y, $w, $h, "SDTADTS") {
        $this.Counts = @{}
        $this._RowCache = [System.Collections.Generic.Dictionary[int,string]]::new()
    }

    [void] Render() {
        if (-not (Compare-Hashtable $this.LastDrawnCounts $this.Counts)) {
            $this.DrawFrame()

            if (-not $this._LineBuilder) {
                $this._LineBuilder = [System.Text.StringBuilder]::new(128)
            }

            $row = 0
            $esc = [char]27

            $this._RowCache.Clear()

            foreach ($id in $script:TETROMINO_IDS) {
                $count = if ($this.Counts.ContainsKey($id)) { $this.Counts[$id] } else { 0 }
                $blocks = $global:TetrominoShapes[$id][0]
                $color = $script:colors[$id]
                $rgb   = "$esc[38;2;$($color[0]);$($color[1]);$($color[2])m"
                $reset = "$esc[0m"

                $mm = [Panel]::GetMinMax($blocks)
                $minX = $mm.MinX; $minY = $mm.MinY
                $offsetX = -$minX + 1
                $offsetY = -$minY + 2

                $occupied = @{}
                foreach ($b in $blocks) {
                    $x = $b.X + $offsetX
                    $y = $b.Y + $offsetY
                    $occupied["{$x}:{$y}"] = $true
                }

                for ($dy = 0; $dy -lt 4; $dy++) {
                    $this._LineBuilder.Clear()

                    for ($dx = 0; $dx -lt 4; $dx++) {
                        $key = "{$dx}:{$dy}"
                        if ($occupied.ContainsKey($key)) {
                            $null = $this._LineBuilder.Append("$rgb▓▓$reset")
                        } else {
                            $null = $this._LineBuilder.Append("  ")
                        }
                    }

                    $drawY = $this.Y + 1 + $row + $dy
                    if ($drawY -ge ($this.Y + $this.Height)) { continue }

                    $drawX = $this.X + 1
                    $rowStr = $this._LineBuilder.ToString()

                    if (-not $this._RowCache.ContainsKey($drawY) -or $this._RowCache[$drawY] -ne $rowStr) {
                        [Console]::SetCursorPosition($drawX, $drawY)
                        [Console]::Write($rowStr)
                        $this._RowCache[$drawY] = $rowStr
                    }
                }

                # Draw piece count (right-aligned)
                $countStr = $count.ToString("D3")
                $labelX = $this.X + 12
                $labelY = $this.Y + $row + 3

                if (-not $this._RowCache.ContainsKey($labelY) -or $this._RowCache[$labelY] -ne $countStr) {
                    [Console]::SetCursorPosition($labelX, $labelY)
                    [Console]::Write($countStr)
                    $this._RowCache[$labelY] = $countStr
                }

                $row += 4
                if (($this.Y + 1 + $row) -ge ($this.Y + $this.Height)) { break }
            }

            $this.LastDrawnCounts = $this.Counts.Clone()
        }
    }
}

# Utility function for comparing hashtables
function Compare-Hashtable($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($key in $a.Keys) {
        if (-not $b.ContainsKey($key)) { return $false }
        if ($a[$key] -ne $b[$key]) { return $false }
    }
    return $true
}