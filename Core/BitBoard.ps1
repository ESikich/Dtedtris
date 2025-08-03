# === BITBOARD CLASS ===

class BitBoard {
    [int] $Width = 10
    [int] $Height = 22
    [System.UInt16[]] $Rows
    [string[,]] $Ids

    BitBoard() {
        $this.Rows = @(0) * $this.Height
        $this.Ids = [string[,]]::new($this.Height, $this.Width)
    }

    [bool] IsInside([int]$x, [int]$y) {
        return $x -ge 0 -and $x -lt $this.Width -and $y -ge 0 -and $y -lt $this.Height
    }

    [bool] CanPlaceMask([int[]]$mask, [int]$x, [int]$y) {
        for ($i = 0; $i -lt 4; $i++) {
            $rowBits = $mask[$i]
            if ($rowBits -eq 0) { continue }           # empty strip row – skip

            $yy = $y + $i
            if ($yy -ge $this.Height) { return $false } # below floor

            # ---------- horizontal shift ----------
            if ($x -lt 0) {
                $shift = -$x

                # bits that would fall off the left edge?
                if (($rowBits -band ((1 -shl $shift) - 1)) -ne 0) { return $false }

                $shifted = $rowBits -shr $shift
            }
            else {
                $shifted = $rowBits -shl $x

                # any bit past column 9?
                if ($shifted -gt 0x3FF) { return $false }
            }

            # ---------- collision with settled blocks ----------
            if ($yy -ge 0) {
                if (($this.Rows[$yy] -band $shifted) -ne 0) { return $false }
            }
        }

        return $true
    }

    [void] PlaceMask([int[]]$mask, [int]$x, [int]$y, [string]$id) {
        for ($i = 0; $i -lt 4; $i++) {
            $yy = $y + $i
            if ($yy -lt 0 -or $yy -ge $this.Height) { continue }

            # ------- shift mask row into board columns -------
            if ($x -lt 0) {
                $shifted = $mask[$i] -shr (-$x)      # flush-left cases
            } else {
                $shifted = $mask[$i] -shl  $x        # normal / right side
            }

            if ($shifted -eq 0) { continue }         # nothing to place this row

            # ------- stamp bits into playfield -------
            $this.Rows[$yy] = $this.Rows[$yy] -bor $shifted

            # ------- write colour / id map -------
            for ($bit = 0; $bit -lt $this.Width; $bit++) {
                if ($shifted -band (1 -shl $bit)) {
                    $this.Ids[$yy, $bit] = $id
                }
            }
        }
    }

    [int] ClearLines() {
        $newRows = @(0) * $this.Height
        $newIds = [string[,]]::new($this.Height, $this.Width)
        $w = $this.Height - 1
        $cleared = 0
        for ($r = $this.Height - 1; $r -ge 0; $r--) {
            if ($this.Rows[$r] -eq 0x3FF) {
                $cleared++
                continue
            }
            $newRows[$w] = $this.Rows[$r]
            for ($c = 0; $c -lt $this.Width; $c++) {
                $newIds[$w, $c] = $this.Ids[$r, $c]
            }
            $w--
        }
        $this.Rows = $newRows
        $this.Ids = $newIds
        return $cleared
    }

    [int[]] GetFullLines() {
        $lines = @()
        for ($r = 0; $r -lt $this.Height; $r++) {
            if ($this.Rows[$r] -eq 0x3FF) {
                $lines += $r
            }
        }
        return $lines
    }
}

# === GHOST PIECE CALCULATION ===
function Get-GhostPieceFrom([BitBoard]$board, [Tetromino]$active, [string[]]$ids) {
    if (-not $active) { return $null }
    
    # clone once; we'll just adjust Y
    $ghost = $active.CloneMoved(0,0,0)

    # pre‑fetch the 4‑row piece mask we'll use many times
    $mask = $global:TetrominoMasks[$ghost.Id][$ghost.Rotation % 4]

    # ----------------------------------------------------
    #   Compute "drop distance" with bit tricks
    # ----------------------------------------------------
    $drop = $board.Height    # start with a very large distance

    for ($i = 0; $i -lt 4; $i++) {
        $rowBits = $mask[$i]
        if ($rowBits -eq 0) { continue }         # empty stripe row

        $yy = $ghost.Y + $i
        if ($ghost.X -lt 0) {
            $shifted = $rowBits -shr -$ghost.X
        } else {
            $shifted = $rowBits -shl $ghost.X
        }

        # Scan downward until collision using bit masks only
        $d = 0
        while ($yy + $d + 1 -lt $board.Height) {
            $checkY = $yy + $d + 1
            if ($checkY -ge 0) {
                if (($board.Rows[$checkY] -band $shifted) -ne 0) { break }
            }
            $d++
        }
        if ($d -lt $drop) { $drop = $d }
    }

    $ghost.Y += $drop
    return $ghost
}