# === CONSOLE RENDERER ===

class UIManager {
    [System.Collections.ArrayList] $Panels

    UIManager() {
        $this.Panels = @()
    }

    [void] AddPanel([Panel]$panel) {
        $this.Panels.Add($panel)
    }

    [void] Render() {
        foreach ($panel in $this.Panels) {
            if (
                $panel -is [ScorePanel] -or
                $panel -is [NextPanel] -or
                $panel -is [StatsPanel] -or
                $panel -is [LinesPanel] -or
                $panel -is [LevelPanel]
            ) {
                $panel.Render()
            } else {
                $panel.DrawFrame()
            }
        }
    }
}

class ConsoleRenderer {
    [int]       $Width
    [int]       $Height
    [hashtable] $Colors
    [hashtable] $AnsiCache
    [System.Collections.Generic.Dictionary[int,string]] $LastDrawn
    [string]    $LastNextPieceId = ""
    [int]       $LeftPanelWidth = 0
    [int]       $Gap            = 30
    [int]       $HorizontalSpacer = 1
    [UIManager] $UI
    [hashtable] $BoardFrame = @{}
    [hashtable] $LastGhostKeys = @{}
    [hashtable] $PreviousGhostBlocks = @{}
    hidden [bool] $_PlayfieldFrameDrawn = $false
    hidden [System.Text.StringBuilder] $_LineBuilder
    hidden [System.Text.StringBuilder] $_FrameBuilder
    hidden [string[]] $_LastGhostKeys = @()
    hidden [string[,]] $_LastDrawnCells
    hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache = @{}

    ConsoleRenderer([int]$width, [int]$height, [hashtable]$colors) {
        $this.Width = $width
        $this.Height = $height
        $this._LastDrawnCells = [string[,]]::new($this.Height, $this.Width)
        $this.Colors = $colors
        $this.UI = [UIManager]::new()
        $this.LastDrawn = [System.Collections.Generic.Dictionary[int,string]]::new()
        $this.BoardFrame = @{ X = 0; Y = 0; W = 0; H = 0 }
        $this._LineBuilder = [System.Text.StringBuilder]::new(256)
        $this._RowCache    = [System.Collections.Generic.Dictionary[int,string]]::new()

        # Precompute ANSI cache once
        $this.AnsiCache = @{}
        $esc = [char]27

        # Add fallback color first
        $this.AnsiCache['Fallback'] = @{ 
            solid = "$esc[37m██$esc[0m"
            ghost = "$esc[37m░░$esc[0m" 
        }

        foreach ($id in $colors.Keys) {
            $rgb = $colors[$id]
            $bg  = $script:bgColors[$id]  # assuming bgColors is script

            $fg  = "$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
            $bgc = "$esc[48;2;$($bg[0]);$($bg[1]);$($bg[2])m"

            $solid = "$fg$bgc$($script:CHAR_SOLID * $script:RENDER_CELL_WIDTH)$esc[0m"
            $ghost = "$fg$($script:CHAR_GHOST * $script:RENDER_CELL_WIDTH)$esc[0m"

            $this.AnsiCache[$id] = @{ solid = $solid; ghost = $ghost }
        }
    }

    [void] DrawBoard(
        [GameState]   $state,
        [string[]]    $ids,
        [hashtable]   $colors,
        [hashtable]   $bgColors,
        [int]         $interiorX,
        [int]         $interiorY
    ) {
        $rows   = $state.Rows
        $idsMap = $state.Ids
        $active = $state.ActivePiece
        $ghost  = $state.GhostPiece

        $cellWidth  = $script:RENDER_CELL_WIDTH
        $fieldWChar = $this.Width * $cellWidth
        $fieldHRows = $this.Height

        if (-not $this._PlayfieldFrameDrawn) {
            $this.DrawFrame($interiorX, $interiorY, $fieldWChar, $fieldHRows, "")
            $this._PlayfieldFrameDrawn = $true
        }

        $inX = $interiorX + 1
        $inY = $interiorY + 1

        $activeBlocks = @{}
        $ghostBlocks  = @{}
        $currentGhostKeys = @()

        if ($active) {
            foreach ($b in $active.GetBlocks()) {
                $idx = $b.X + ($b.Y * $this.Width)
                $activeBlocks[$idx] = $active.Id
            }
        }

        if ($ghost) {
            foreach ($b in $ghost.GetBlocks()) {
                $idx = $b.X + ($b.Y * $this.Width)
                $ghostBlocks[$idx] = $ghost.Id
                $currentGhostKeys += "$($b.X):$($b.Y)"
            }
        }

        for ($y = 0; $y -lt $fieldHRows; $y++) {

            # Build the full line once in a StringBuilder
            $this._LineBuilder.Clear()

            for ($x = 0; $x -lt $this.Width; $x++) {

                $idx = $x + ($y * $this.Width)
                $char = $script:CHAR_EMPTY
                $id = $null

                $cellSet = ($rows[$y] -band (1 -shl $x)) -ne 0

                if ($activeBlocks.ContainsKey($idx)) {
                    $char = $script:CHAR_SOLID
                    $id = $activeBlocks[$idx]
                } elseif ($cellSet) {
                    $char = $script:CHAR_SOLID
                    $id = $idsMap[$y, $x]
                } elseif ($ghostBlocks.ContainsKey($idx)) {
                    $char = $script:CHAR_GHOST
                    $id = $ghostBlocks[$idx]
                }

                if (-not $id -or -not $this.AnsiCache.ContainsKey($id)) {
                    $id = 'Fallback'
                }

                switch ($char) {
                    $script:CHAR_GHOST { $null = $this._LineBuilder.Append($this.AnsiCache[$id]['ghost']) }
                    $script:CHAR_SOLID { $null = $this._LineBuilder.Append($this.AnsiCache[$id]['solid']) }
                    default            { $null = $this._LineBuilder.Append(' ' * $cellWidth) }
                }
            }

            $fullLine = $this._LineBuilder.ToString()
            if ($this._RowCache[$y] -ne $fullLine) {
                [Console]::SetCursorPosition($inX, $inY + $y)
                [Console]::Write($fullLine)
                $this._RowCache[$y] = $fullLine
            }
        }
    }

    [void] SetupUIPanels([GameState] $state, [hashtable] $colors) {
        $this.Gap = 1  # one-column gutter everywhere

        # 1. Stats panel (left)
        $statsX     = $this.Gap
        $statsPanel = [StatsPanel]::new(
            $statsX,
            0,
            $script:STATS_PANEL_WIDTH,
            $script:STATS_PANEL_HEIGHT
        )
        $this.UI.AddPanel($statsPanel)

        # 2. Game board (center)
        $boardX = $statsX + $script:STATS_PANEL_WIDTH + 2 + $this.Gap
        $boardY = 3  # leave space above for Lines panel
        $boardW = $script:BOARD_WIDTH  * $script:RENDER_CELL_WIDTH
        $boardH = $script:BOARD_HEIGHT + 2  # with frame

        # Lines label panel above the game board
        $linesPanel = [LinesPanel]::new($boardX, 0, $boardW, 1)
        $this.UI.AddPanel($linesPanel)

        # Store where the board is located for DrawBoard()
        $this.BoardFrame = @{
            X = $boardX
            Y = $boardY
            W = $boardW
            H = $boardH
        }

        # 3. HUD column (right side)
        $hudX = $boardX + $boardW + 2 + $this.Gap

        $scorePanel = [ScorePanel]::new(
            0,
            0,
            $script:SCORE_PANEL_WIDTH,
            $script:SCORE_PANEL_HEIGHT
        )

        $nextPanel = [NextPanel]::new(
            0,
            0,
            $script:NEXT_PANEL_WIDTH,
            $script:NEXT_PANEL_HEIGHT,
            $colors
        )

        $levelPanel = [LevelPanel]::new(
            0,
            0,
            $script:NEXT_PANEL_WIDTH,
            2
        )

        # Stack the HUD panels vertically on the right
        LayoutTopStack -startX $hudX -startY 0 -gap 0 -panels @($scorePanel, $nextPanel, $levelPanel)

        $this.UI.AddPanel($scorePanel)
        $this.UI.AddPanel($nextPanel)
        $this.UI.AddPanel($levelPanel)
    }

    [void] Draw([GameState] $state, [hashtable] $colors, [hashtable] $bgColors, [string[]] $ids) {
        # Ensure UI and board layout are set up before drawing
        if (
            $this.UI.Panels.Count -eq 0 -or
            -not $this.BoardFrame.ContainsKey("X") -or
            -not $this.BoardFrame.ContainsKey("Y")
        ) {
            $this.SetupUIPanels($state, $colors)
        }

        # Update panel contents with latest game state
        foreach ($panel in $this.UI.Panels) {
            if ($panel -is [ScorePanel]) {
                $panel.Score = $state.Score
                $panel.Lines = $state.Lines
                $panel.Level = $state.Level
            } elseif ($panel -is [LevelPanel]) {
                $panel.Level = $state.Level
            } elseif ($panel -is [NextPanel]) {
                $panel.NextId = $state.NextPieceId
            } elseif ($panel -is [StatsPanel]) {
                $panel.Counts = $state.PieceStats
            } elseif ($panel -is [LinesPanel]) {
                $panel.Lines = $state.Lines
            }
        }

        # Draw the playfield
        $this.DrawBoard(
            $state,
            $ids,
            $colors,
            $bgColors,
            $this.BoardFrame.X,
            $this.BoardFrame.Y
        )

        # Render HUD/UI
        $this.UI.Render()
    }

    [void] FlashLines([int[]] $lineIndices, [int] $flickerCount = 4, [int] $frameDelayMs = 80) {
        $esc = [char]27
        $cellW = $script:RENDER_CELL_WIDTH
        $inX = $this.BoardFrame.X + 1
        $inY = $this.BoardFrame.Y + 1

        for ($i = 0; $i -lt $flickerCount; $i++) {
            foreach ($y in $lineIndices) {
                $str = ''
                for ($x = 0; $x -lt $this.Width; $x++) {
                    if ($i % 2 -eq 0) {
                        $str += "$esc[7m" + (' ' * $cellW) + "$esc[0m"  # Inverted
                    } else {
                        $str += (' ' * $cellW)                          # Clear
                    }
                }
                [Console]::SetCursorPosition($inX, $inY + $y)
                [Console]::Write($str)
            }
            Start-Sleep -Milliseconds $frameDelayMs
        }
    }

    [void] DrawSpacer([int]$x) {
        for ($y = 0; $y -lt $this.Height; $y++) {
            Write-CursorPositionIfChanged ($x + 1) (1 + $y)
            [Console]::Write(" ")
        }
    }

    [void] DrawFrame([int]$x, [int]$y, [int]$wChars, [int]$hRows, [string]$title = "") {
        $panel = [Panel]::new($x, $y, $wChars, $hRows, $title)
        $panel.DrawFrame()
    }
}