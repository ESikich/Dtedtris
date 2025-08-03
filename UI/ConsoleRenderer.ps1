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
    
    # Performance optimization additions - maintain backward compatibility
    hidden [int[]] $_RowHashes
    hidden [hashtable] $_BlockMapCache = @{}
    hidden [bool[]] $_DirtyRows
    hidden [string[]] $_PreAllocatedSpaces
    hidden [int] $_LastActiveHash = 0
    hidden [int] $_LastGhostHash = 0

    ConsoleRenderer([int]$width, [int]$height, [hashtable]$colors) {
        $this.Width = $width
        $this.Height = $height
        $this._LastDrawnCells = [string[,]]::new($this.Height, $this.Width)
        $this.Colors = $colors
        $this.UI = [UIManager]::new()
        $this.LastDrawn = [System.Collections.Generic.Dictionary[int,string]]::new()
        $this.BoardFrame = @{ X = 0; Y = 0; W = 0; H = 0 }
        $this._RowCache    = [System.Collections.Generic.Dictionary[int,string]]::new()

        # Initialize performance optimizations while maintaining compatibility
        $this.InitializePerformanceStructures()

        # Precompute ANSI cache once - enhanced version
        $this.BuildOptimizedAnsiCache()
    }

    [void] InitializePerformanceStructures() {
        # Pre-allocate StringBuilder with optimal capacity to reduce memory allocations
        $maxLineLength = $this.Width * $script:RENDER_CELL_WIDTH * 25  # Buffer for ANSI codes
        $this._LineBuilder = [System.Text.StringBuilder]::new($maxLineLength)
        
        # Hash-based row caching eliminates expensive string comparisons in hot path
        $this._RowHashes = [int[]]::new($this.Height)
        for ($i = 0; $i -lt $this.Height; $i++) {
            $this._RowHashes[$i] = -1  # Sentinel value for "never drawn"
        }
        
        # Dirty row tracking enables selective rendering for better frame rates
        $this._DirtyRows = [bool[]]::new($this.Height)
        
        # Pre-allocate common space strings to avoid runtime allocation overhead
        $this._PreAllocatedSpaces = [string[]]::new(21)
        for ($i = 0; $i -lt 21; $i++) {
            $this._PreAllocatedSpaces[$i] = ' ' * $i
        }
    }

    [void] BuildOptimizedAnsiCache() {
        $this.AnsiCache = @{}
        $esc = [char]27

        # Enhanced ANSI cache with pre-computed strings reduces string concatenation overhead
        $this.AnsiCache['Fallback'] = @{ 
            solid = "$esc[37m██$esc[0m"
            ghost = "$esc[37m░░$esc[0m" 
        }

        foreach ($id in $this.Colors.Keys) {
            $rgb = $this.Colors[$id]
            $bg  = $script:bgColors[$id]

            # Pre-compute full ANSI sequences including background colors for richer display
            $fg  = "$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
            $bgc = "$esc[48;2;$($bg[0]);$($bg[1]);$($bg[2])m"

            $solid = "$fg$bgc$($script:CHAR_SOLID * $script:RENDER_CELL_WIDTH)$esc[0m"
            $ghost = "$fg$($script:CHAR_GHOST * $script:RENDER_CELL_WIDTH)$esc[0m"

            $this.AnsiCache[$id] = @{ solid = $solid; ghost = $ghost }
        }
    }

    [hashtable] BuildBlockMap([Tetromino] $piece) {
        # Convert piece blocks to hash table for O(1) lookup instead of O(n) search
        # This optimization is critical during rendering when checking thousands of cells
        if (-not $piece) { return @{} }
        
        $blockMap = @{}
        foreach ($block in $piece.GetBlocks()) {
            if ($block.Y -ge 0 -and $block.Y -lt $this.Height -and 
                $block.X -ge 0 -and $block.X -lt $this.Width) {
                $idx = $block.X + ($block.Y * $this.Width)
                $blockMap[$idx] = $piece.Id
            }
        }
        return $blockMap
    }

    [void] MarkDirtyRows([GameState] $state, [hashtable] $activeBlocks, [hashtable] $ghostBlocks) {
        # Intelligent dirty tracking minimizes unnecessary screen updates
        # This is essential for maintaining smooth gameplay during rapid piece movement
        
        # Hash current piece positions to detect movement without expensive comparisons
        $activeHash = if ($state.ActivePiece) { 
            "$($state.ActivePiece.Id):$($state.ActivePiece.X):$($state.ActivePiece.Y):$($state.ActivePiece.Rotation)".GetHashCode()
        } else { 0 }
        
        $ghostHash = if ($state.GhostPiece) { 
            "$($state.GhostPiece.Id):$($state.GhostPiece.X):$($state.GhostPiece.Y):$($state.GhostPiece.Rotation)".GetHashCode()
        } else { 0 }
        
        # Only mark rows dirty if pieces have actually moved
        $piecesChanged = ($activeHash -ne $this._LastActiveHash) -or ($ghostHash -ne $this._LastGhostHash)
        
        if ($piecesChanged) {
            # Mark affected rows for redraw when pieces move
            foreach ($idx in $activeBlocks.Keys) {
                $y = [math]::Floor($idx / $this.Width)
                if ($y -ge 0 -and $y -lt $this.Height) {
                    $this._DirtyRows[$y] = $true
                }
            }
            
            foreach ($idx in $ghostBlocks.Keys) {
                $y = [math]::Floor($idx / $this.Width)
                if ($y -ge 0 -and $y -lt $this.Height) {
                    $this._DirtyRows[$y] = $true
                }
            }
            
            # Mark previous positions dirty to clear old piece graphics
            if ($this._LastActiveHash -ne 0 -or $this._LastGhostHash -ne 0) {
                # For safety, mark a reasonable range around piece movement
                # This ensures clean erasing of previous piece positions
                for ($y = 0; $y -lt $this.Height; $y++) {
                    $this._DirtyRows[$y] = $true
                }
            }
        }
        
        $this._LastActiveHash = $activeHash
        $this._LastGhostHash = $ghostHash
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

        # Frame optimization: draw border only once per game session
        if (-not $this._PlayfieldFrameDrawn) {
            $this.DrawFrame($interiorX, $interiorY, $fieldWChar, $fieldHRows, "")
            $this._PlayfieldFrameDrawn = $true
        }

        $inX = $interiorX + 1
        $inY = $interiorY + 1

        # Build optimized lookup tables for piece positions
        $activeBlocks = $this.BuildBlockMap($active)
        $ghostBlocks  = $this.BuildBlockMap($ghost)

        # Determine which rows need updating to minimize console I/O
        $this.MarkDirtyRows($state, $activeBlocks, $ghostBlocks)

        # Render only changed rows for optimal performance
        for ($y = 0; $y -lt $fieldHRows; $y++) {
            # Skip unchanged rows to maintain high frame rates
            if (-not $this._DirtyRows[$y]) { continue }

            # Build complete row string in single pass to minimize string operations
            $this._LineBuilder.Clear()

            for ($x = 0; $x -lt $this.Width; $x++) {
                $idx = $x + ($y * $this.Width)
                $char = $script:CHAR_EMPTY
                $id = $null

                # Priority-based cell determination: active > settled > ghost
                $cellSet = ($rows[$y] -band (1 -shl $x)) -ne 0

                if ($activeBlocks.ContainsKey($idx)) {
                    # Active piece has highest priority for player feedback
                    $char = $script:CHAR_SOLID
                    $id = $activeBlocks[$idx]
                } elseif ($cellSet) {
                    # Settled blocks take priority over ghost to maintain game clarity
                    $char = $script:CHAR_SOLID
                    $id = $idsMap[$y, $x]
                } elseif ($ghostBlocks.ContainsKey($idx)) {
                    # Ghost piece provides landing preview in empty spaces only
                    $char = $script:CHAR_GHOST
                    $id = $ghostBlocks[$idx]
                }

                # Use pre-computed ANSI sequences to eliminate runtime string formatting
                if (-not $id -or -not $this.AnsiCache.ContainsKey($id)) {
                    $id = 'Fallback'
                }

                switch ($char) {
                    $script:CHAR_GHOST { $null = $this._LineBuilder.Append($this.AnsiCache[$id]['ghost']) }
                    $script:CHAR_SOLID { $null = $this._LineBuilder.Append($this.AnsiCache[$id]['solid']) }
                    default            { $null = $this._LineBuilder.Append($this._PreAllocatedSpaces[$cellWidth]) }
                }
            }

            # Hash-based change detection eliminates expensive string comparisons
            $fullLine = $this._LineBuilder.ToString()
            $lineHash = $fullLine.GetHashCode()
            
            if ($this._RowHashes[$y] -ne $lineHash) {
                [Console]::SetCursorPosition($inX, $inY + $y)
                [Console]::Write($fullLine)
                $this._RowHashes[$y] = $lineHash
            }
        }
        
        # Clear dirty flags after successful render
        for ($y = 0; $y -lt $this.Height; $y++) {
            $this._DirtyRows[$y] = $false
        }
    }

    [void] SetupUIPanels([GameState] $state, [hashtable] $colors) {
        $this.Gap = 1  # Consistent spacing between UI elements

        # Stats panel positioned on left side for easy reference
        $statsX     = $this.Gap
        $statsPanel = [StatsPanel]::new(
            $statsX,
            0,
            $script:STATS_PANEL_WIDTH,
            $script:STATS_PANEL_HEIGHT
        )
        $this.UI.AddPanel($statsPanel)

        # Game board centered with proper spacing
        $boardX = $statsX + $script:STATS_PANEL_WIDTH + 2 + $this.Gap
        $boardY = 3  # Space for lines display above board
        $boardW = $script:BOARD_WIDTH  * $script:RENDER_CELL_WIDTH
        $boardH = $script:BOARD_HEIGHT + 2  # Include frame borders

        # Lines counter positioned above game board for visibility
        $linesPanel = [LinesPanel]::new($boardX, 0, $boardW, 1)
        $this.UI.AddPanel($linesPanel)

        # Store board coordinates for DrawBoard method
        $this.BoardFrame = @{
            X = $boardX
            Y = $boardY
            W = $boardW
            H = $boardH
        }

        # Right-side HUD with score, next piece, and level information
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

        # Vertical stacking of HUD panels for organized layout
        LayoutTopStack -startX $hudX -startY 0 -gap 0 -panels @($scorePanel, $nextPanel, $levelPanel)

        $this.UI.AddPanel($scorePanel)
        $this.UI.AddPanel($nextPanel)
        $this.UI.AddPanel($levelPanel)
    }

    [void] Draw([GameState] $state, [hashtable] $colors, [hashtable] $bgColors, [string[]] $ids) {
        # Lazy initialization ensures UI setup only happens when needed
        if (
            $this.UI.Panels.Count -eq 0 -or
            -not $this.BoardFrame.ContainsKey("X") -or
            -not $this.BoardFrame.ContainsKey("Y")
        ) {
            $this.SetupUIPanels($state, $colors)
        }

        # Update panel data from current game state
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

        # Render game board with optimized drawing
        $this.DrawBoard(
            $state,
            $ids,
            $colors,
            $bgColors,
            $this.BoardFrame.X,
            $this.BoardFrame.Y
        )

        # Update UI panels as needed
        $this.UI.Render()
    }

    [void] FlashLines([int[]] $lineIndices, [int] $flickerCount = 4, [int] $frameDelayMs = 80) {
        # Line clear animation provides visual feedback for completed lines
        $esc = [char]27
        $cellW = $script:RENDER_CELL_WIDTH
        $inX = $this.BoardFrame.X + 1
        $inY = $this.BoardFrame.Y + 1

        for ($i = 0; $i -lt $flickerCount; $i++) {
            foreach ($y in $lineIndices) {
                $str = ''
                for ($x = 0; $x -lt $this.Width; $x++) {
                    if ($i % 2 -eq 0) {
                        # Inverted colors create flashing effect
                        $str += "$esc[7m" + (' ' * $cellW) + "$esc[0m"
                    } else {
                        # Clear state between flashes
                        $str += (' ' * $cellW)
                    }
                }
                [Console]::SetCursorPosition($inX, $inY + $y)
                [Console]::Write($str)
                
                # Mark flashed rows as dirty to ensure proper cleanup
                $this._DirtyRows[$y] = $true
                $this._RowHashes[$y] = -1  # Force redraw after animation
            }
            Start-Sleep -Milliseconds $frameDelayMs
        }
    }

    [void] DrawSpacer([int]$x) {
        # Column spacer for UI layout separation
        for ($y = 0; $y -lt $this.Height; $y++) {
            Write-CursorPositionIfChanged ($x + 1) (1 + $y)
            [Console]::Write(" ")
        }
    }

    [void] DrawFrame([int]$x, [int]$y, [int]$wChars, [int]$hRows, [string]$title = "") {
        # Delegate frame drawing to Panel class for consistency
        $panel = [Panel]::new($x, $y, $wChars, $hRows, $title)
        $panel.DrawFrame()
    }

    # Performance monitoring for optimization tuning
    [hashtable] GetRenderingStats() {
        $dirtyRowCount = 0
        for ($y = 0; $y -lt $this.Height; $y++) {
            if ($this._DirtyRows[$y]) { $dirtyRowCount++ }
        }
        
        return @{
            DirtyRowRatio = if ($this.Height -gt 0) { [double]$dirtyRowCount / $this.Height } else { 0.0 }
            CacheSize = $this._RowCache.Count
            AnsiCacheEntries = $this.AnsiCache.Count
        }
    }
}