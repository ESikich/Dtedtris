# === BITBOARD CLASS ===

class BitBoard {
    [int] $Width = 10
    [int] $Height = 22
    [System.UInt16[]] $Rows
    [string[,]] $Ids
    
    # Performance optimization: cache frequently computed values
    hidden [hashtable] $_ShiftCache = @{}
    hidden [System.UInt16] $_FullRowMask = 0x3FF  # Precomputed mask for full row (all 10 bits set)
    hidden [int[]] $_BitCountLookup

    BitBoard() {
        $this.Rows = @(0) * $this.Height
        $this.Ids = [string[,]]::new($this.Height, $this.Width)
        $this.InitializeOptimizations()
    }

    [void] InitializeOptimizations() {
        # Precompute bit count lookup table for faster full line detection
        # This eliminates the need for expensive bit counting operations
        $this._BitCountLookup = [int[]]::new(1024)  # 2^10 = 1024 possible row states
        for ($i = 0; $i -lt 1024; $i++) {
            $count = 0
            $val = $i
            # Brian Kernighan's algorithm for counting set bits
            while ($val -ne 0) {
                $val = $val -band ($val - 1)
                $count++
            }
            $this._BitCountLookup[$i] = $count
        }
    }

    [bool] IsInside([int]$x, [int]$y) {
        # Bounds checking for tetromino placement validation
        return $x -ge 0 -and $x -lt $this.Width -and $y -ge 0 -and $y -lt $this.Height
    }

    [bool] CanPlaceMask([int[]]$mask, [int]$x, [int]$y) {
        # Core collision detection using bitwise operations for maximum performance
        # This method is called extensively during piece movement and rotation
        
        # Create cache key for shift operations to avoid redundant calculations
        $shiftKey = "$x"
        if (-not $this._ShiftCache.ContainsKey($shiftKey)) {
            $this._ShiftCache[$shiftKey] = @{}
        }
        
        for ($i = 0; $i -lt 4; $i++) {
            $rowBits = $mask[$i]
            if ($rowBits -eq 0) { continue }  # Skip empty rows for performance

            $yy = $y + $i
            if ($yy -ge $this.Height) { return $false }  # Below floor boundary

            # Optimize bit shifting with caching for common positions
            $maskCacheKey = "$rowBits"
            if (-not $this._ShiftCache[$shiftKey].ContainsKey($maskCacheKey)) {
                if ($x -lt 0) {
                    $shift = -$x
                    # Check if bits would fall off the left edge before shifting
                    if (($rowBits -band ((1 -shl $shift) - 1)) -ne 0) { 
                        $this._ShiftCache[$shiftKey][$maskCacheKey] = -1  # Invalid position marker
                    } else {
                        $this._ShiftCache[$shiftKey][$maskCacheKey] = $rowBits -shr $shift
                    }
                } else {
                    $shifted = $rowBits -shl $x
                    # Check if any bit extends past column 9 (0x3FF = 10 bits)
                    if ($shifted -gt $this._FullRowMask) { 
                        $this._ShiftCache[$shiftKey][$maskCacheKey] = -1  # Invalid position marker
                    } else {
                        $this._ShiftCache[$shiftKey][$maskCacheKey] = $shifted
                    }
                }
            }
            
            $shifted = $this._ShiftCache[$shiftKey][$maskCacheKey]
            if ($shifted -eq -1) { return $false }  # Invalid position from cache

            # Collision detection with existing blocks using fast bitwise AND
            if ($yy -ge 0) {
                if (($this.Rows[$yy] -band $shifted) -ne 0) { return $false }
            }
        }

        return $true
    }

    [void] PlaceMask([int[]]$mask, [int]$x, [int]$y, [string]$id) {
        # Permanently place tetromino into game board after collision validation
        # This method handles both the bitfield representation and color mapping
        
        for ($i = 0; $i -lt 4; $i++) {
            $yy = $y + $i
            if ($yy -lt 0 -or $yy -ge $this.Height) { continue }

            # Use cached shift calculations when available for consistency
            $shiftKey = "$x"
            $maskCacheKey = "$($mask[$i])"
            
            $shifted = 0
            if ($this._ShiftCache.ContainsKey($shiftKey) -and 
                $this._ShiftCache[$shiftKey].ContainsKey($maskCacheKey)) {
                $shifted = $this._ShiftCache[$shiftKey][$maskCacheKey]
                if ($shifted -eq -1) { continue }  # Skip invalid cached positions
            } else {
                # Fallback calculation if not in cache
                if ($x -lt 0) {
                    $shifted = $mask[$i] -shr (-$x)
                } else {
                    $shifted = $mask[$i] -shl $x
                }
            }

            if ($shifted -eq 0) { continue }  # Nothing to place in this row

            # Update bitfield representation for fast collision detection
            $this.Rows[$yy] = $this.Rows[$yy] -bor $shifted

            # Update color/ID mapping for rendering system
            for ($bit = 0; $bit -lt $this.Width; $bit++) {
                if ($shifted -band (1 -shl $bit)) {
                    $this.Ids[$yy, $bit] = $id
                }
            }
        }
    }

    [int] ClearLines() {
        # Remove completed lines and compact remaining blocks downward
        # This is the core of Tetris line clearing mechanics
        
        $newRows = @(0) * $this.Height
        $newIds = [string[,]]::new($this.Height, $this.Width)
        $writeIndex = $this.Height - 1  # Start from bottom
        $cleared = 0
        
        # Process from bottom to top, keeping non-full lines
        for ($readIndex = $this.Height - 1; $readIndex -ge 0; $readIndex--) {
            if ($this.Rows[$readIndex] -eq $this._FullRowMask) {
                # Line is full - skip it (effectively removing it)
                $cleared++
                continue
            }
            
            # Copy non-full line to new position
            $newRows[$writeIndex] = $this.Rows[$readIndex]
            for ($c = 0; $c -lt $this.Width; $c++) {
                $newIds[$writeIndex, $c] = $this.Ids[$readIndex, $c]
            }
            $writeIndex--
        }
        
        # Update board state with compacted lines
        $this.Rows = $newRows
        $this.Ids = $newIds
        
        # Clear shift cache after line clearing to ensure fresh calculations
        $this._ShiftCache.Clear()
        
        return $cleared
    }

    [int[]] GetFullLines() {
        # Identify all completed lines for animation and clearing
        # Uses precomputed full row mask for fast comparison
        $lines = @()
        for ($r = 0; $r -lt $this.Height; $r++) {
            if ($this.Rows[$r] -eq $this._FullRowMask) {
                $lines += $r
            }
        }
        return $lines
    }

    # Performance monitoring and optimization methods
    [hashtable] GetBoardStats() {
        $filledCells = 0
        $fullRows = 0
        
        for ($r = 0; $r -lt $this.Height; $r++) {
            $bitCount = $this._BitCountLookup[$this.Rows[$r]]
            $filledCells += $bitCount
            if ($bitCount -eq $this.Width) {
                $fullRows++
            }
        }
        
        return @{
            FilledCells = $filledCells
            FullRows = $fullRows
            ShiftCacheSize = $this._ShiftCache.Count
            BoardDensity = [double]$filledCells / ($this.Width * $this.Height)
        }
    }

    [void] OptimizeCaches() {
        # Periodic cache cleanup to prevent memory bloat during extended play
        if ($this._ShiftCache.Count -gt 200) {
            # Keep only most recently used shift calculations
            $recentKeys = $this._ShiftCache.Keys | Select-Object -Last 50
            $newCache = @{}
            foreach ($key in $recentKeys) {
                $newCache[$key] = $this._ShiftCache[$key]
            }
            $this._ShiftCache = $newCache
        }
    }

    [void] ResetBoard() {
        # Complete board reset for new game initialization
        for ($r = 0; $r -lt $this.Height; $r++) {
            $this.Rows[$r] = 0
            for ($c = 0; $c -lt $this.Width; $c++) {
                $this.Ids[$r, $c] = $null
            }
        }
        $this._ShiftCache.Clear()
    }
}

# === OPTIMIZED GHOST PIECE CALCULATION ===
function Get-GhostPieceFrom([BitBoard]$board, [Tetromino]$active, [string[]]$ids) {
    # Calculate where active piece would land if dropped immediately
    # This provides essential visual feedback for precise piece placement
    if (-not $active) { return $null }
    
    # Create ghost piece as clone to avoid modifying active piece
    $ghost = $active.CloneMoved(0,0,0)

    # Get piece mask once to avoid repeated lookups in tight loop
    $mask = $global:TetrominoMasks[$ghost.Id][$ghost.Rotation % 4]

    # Optimized drop distance calculation using bitwise operations
    # This replaces slow iterative collision checking with direct bit manipulation
    $minDrop = $board.Height  # Start with maximum possible distance

    for ($i = 0; $i -lt 4; $i++) {
        $rowBits = $mask[$i]
        if ($rowBits -eq 0) { continue }  # Skip empty mask rows

        $yy = $ghost.Y + $i
        
        # Calculate shifted mask once per row
        if ($ghost.X -lt 0) {
            $shifted = $rowBits -shr (-$ghost.X)
        } else {
            $shifted = $rowBits -shl $ghost.X
        }

        # Fast collision detection by scanning down from current position
        $dropDistance = 0
        while ($yy + $dropDistance + 1 -lt $board.Height) {
            $checkY = $yy + $dropDistance + 1
            if ($checkY -ge 0) {
                # Use bitwise AND for instant collision detection
                if (($board.Rows[$checkY] -band $shifted) -ne 0) { break }
            }
            $dropDistance++
        }
        
        # Track minimum drop distance across all piece parts
        if ($dropDistance -lt $minDrop) { $minDrop = $dropDistance }
    }

    # Position ghost at calculated landing point
    $ghost.Y += $minDrop
    return $ghost
}