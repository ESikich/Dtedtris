# === GAME ENGINE ===

class GameEngine {
    [GameContext]   $Ctx
    [string[]]      $Bag = @()
    [int]           $GravityAccumulator = 0
    [int]           $MsPerGravity       = $script:GRAVITY_INTERVALS[0]
    [int]           $LockDelay          = $script:LOCK_DELAY_MS
    [Nullable[int]] $LockStartedAt      = $null
    [bool]          $LockDelayActive    = $false
    [int]           $LockResets         = 0
    [int]           $LockResetLimit     = $script:LOCK_RESET_LIMIT
    [int]           $LFSR
    [int]           $PrevIndex          = -1

    # ghost cache
    [Tetromino]     $GhostCache = $null
    [string]        $GhostKey   = ''

    GameEngine([GameContext]$ctx) {
        $this.Ctx = $ctx
        $this.LFSR = Get-Random -Minimum 1 -Maximum 128  # Initial seed (non-zero)
    }

    [bool] CanPlace([Tetromino]$p) {
        $id = $p.Id
        $rot = $p.Rotation % 4
        $mask = $global:TetrominoMasks[$id][$rot]
        return $this.Ctx.Board.CanPlaceMask($mask, $p.X, $p.Y)
    }

    [bool] IsGrounded() {
        if (-not $this.Ctx.Active) { return $false }
        return -not $this.CanPlace($this.Ctx.Active.CloneMoved(0, 1, 0))
    }

    [string] GetNextTetrominoId() {
        # Step 1: Advance LFSR (7-bit)
        $bit0 = $this.LFSR -band 1
        $bit1 = ($this.LFSR -shr 1) -band 1
        $newBit = $bit0 -bxor $bit1
        $this.LFSR = ($this.LFSR -shr 1) -bor ($newBit -shl 6)

        if ($this.LFSR -eq 0) {
            $this.LFSR = 0x1F  # reset if stuck (never zero in real LFSR)
        }

        # Step 2: Get a candidate index
        $index = $this.LFSR % 7

        # NES retry rule: If same as previous, pick again (once)
        if ($index -eq $this.PrevIndex) {
            $this.LFSR = ($this.LFSR -shr 1) -bor (($this.LFSR -bxor ($this.LFSR -shr 1)) -shl 6)
            if ($this.LFSR -eq 0) {
                $this.LFSR = 0x1F
            }
            $index = $this.LFSR % 7
        }

        $this.PrevIndex = $index
        return $this.Ctx.Ids[$index]
    }

    [GameState] TakeSnapshot() {
        $next = ''
        if ($this.Ctx.NextQueue.Count -gt 0) {
            $next = $this.Ctx.NextQueue[0]
        }

        $ghost = $this.GetGhostCached()

        return [GameState]::new(
            $this.Ctx.Board,
            $this.Ctx.Active,
            $ghost,
            $next,
            $this.Ctx.Score,
            $this.Ctx.Lines,
            $this.Ctx.Level,
            $this.Ctx.Paused,
            $this.Ctx.GameOver,
            $this.Ctx.PieceCounts
        )
    }

    [GameState] Update([int]$dt) {
        if ($this.Ctx.GameOver) { return $null }

        $changed = $false
        $this.GravityAccumulator += $dt
        $this.MsPerGravity = $this.Ctx.GravityIntervals[
            [math]::Min($this.Ctx.Level, $this.Ctx.GravityIntervals.Count - 1)
        ]

        if ($this.GravityAccumulator -ge $this.MsPerGravity) {
            $this.GravityAccumulator -= $this.MsPerGravity

            if ($this.TryMove(0, 1, 0)) {
                $this.LockDelayActive = $false
                $this.LockResets      = 0
                $this.LockStartedAt   = $null
                $changed = $true
            } else {
                $now = [Environment]::TickCount

                if (-not $this.LockDelayActive) {
                    $this.LockDelayActive = $true
                    $this.LockStartedAt   = $now
                    $changed = $true
                } elseif (($null -ne $this.LockStartedAt) -and ($now - $this.LockStartedAt) -ge $this.LockDelay) {
                    $this.ForceLock()
                    $changed = $true
                }
            }
        }

        if ($changed) {
            return $this.TakeSnapshot()
        }

        return $null
    }

    [bool] TryMove([int]$dx, [int]$dy, [int]$dr) {
        $next = $this.Ctx.Active.CloneMoved($dx, $dy, $dr)
        if (-not $this.CanPlace($next)) { return $false }

        $this.Ctx.Active = $next

        if ($this.LockDelayActive -and $this.IsGrounded() -and
            $this.LockResets -lt $this.LockResetLimit) {

            # Cache time
            $this.LockStartedAt = [Environment]::TickCount
            $this.LockResets++
        }

        return $true
    }

    [bool] TryRotateWithWallKick([Tetromino]$piece, [int]$dir) {
        $old = $piece.Rotation % 4
        $new = ($old + $dir) % 4
        $key = "${old}_${new}"

        $table = if ($piece.Id -eq 'I') {
            $global:TetrominoKicks.I[$key]
        } else {
            $global:TetrominoKicks.Default[$key]
        }

        foreach ($kick in $table) {
            $test = $piece.CloneMoved($kick.X, $kick.Y, $dir)
            if ($this.CanPlace($test)) {
                $this.Ctx.Active = $test

                if ($this.LockDelayActive -and $this.IsGrounded() -and
                    $this.LockResets -lt $this.LockResetLimit) {

                    $this.LockStartedAt = [Environment]::TickCount
                    $this.LockResets++
                }

                return $true
            }
        }

        return $false
    }

    [void] Spawn() {
        if (-not $this.Ctx.NextQueue) {
            $this.Ctx.NextQueue = @($this.GetNextTetrominoId())
        }

        $id = $this.Ctx.NextQueue[0]
        $this.Ctx.NextQueue = ,($this.GetNextTetrominoId())

        # Increment piece count
        if (-not $this.Ctx.PieceCounts.ContainsKey($id)) {
            $this.Ctx.PieceCounts[$id] = 0
        }
        $this.Ctx.PieceCounts[$id]++

        # --- X centering (precomputed) ---
        $dim = $global:TetrominoDims[$id]
        $x   = [math]::Floor(($this.Ctx.Width - $dim.Width) / 2) - $dim.MinX

        $this.Ctx.Active = [Tetromino]::new(
            $id,
            $x,
            $script:SPAWN_Y_OFFSET,
            $global:TetrominoKicks
        )

        if (-not $this.CanPlace($this.Ctx.Active)) {
            $this.Ctx.GameOver = $true
        } elseif ($this.TryMove(0, 1, 0)) {
            $null = $this.TryMove(0, -1, 0)
        } else {
            $this.Ctx.GameOver = $true
        }
    }

    [void] ForceLock() {
        if (-not $this.Ctx.Active) { return }

        $id = $this.Ctx.Active.Id
        $rot = $this.Ctx.Active.Rotation % 4
        $mask = $global:TetrominoMasks[$id][$rot]

        $this.Ctx.Board.PlaceMask($mask, $this.Ctx.Active.X, $this.Ctx.Active.Y, $id)

        # Step 1: Detect full lines
        $fullLines = $this.Ctx.Board.GetFullLines()

        # Step 2: Flash them if any
        if ($fullLines.Count -gt 0 -and $script:app -and $script:app.Renderer) {
            $script:app.Renderer.FlashLines($fullLines, 4, 32)  # X flickers, Y ms
        }

        # Step 3: Clear them and apply scoring
        $cleared = $this.Ctx.Board.ClearLines()
        if ($cleared -gt 0) {
            $this.Ctx.Lines += $cleared
            $this.Ctx.Level = [math]::Floor($this.Ctx.Lines / $script:LINES_PER_LEVEL)
            $this.Ctx.Score += $script:LINE_CLEAR_SCORES[$cleared] * ($this.Ctx.Level + 1)
        }

        $this.Spawn()
        $this.LockDelayActive = $false
        $this.LockStartedAt   = $null
        $this.LockResets      = 0
    }

    [string] MakeGhostKey([Tetromino]$piece) {
        return "{0}:{1}:{2}:{3}" -f $piece.Id, $piece.X, $piece.Y, ($piece.Rotation % 4)
    }

    [Tetromino] GetGhostCached() {
        $active = $this.Ctx.Active
        #if (-not $active) { return $null }

        $newKey = $this.MakeGhostKey($active)

        if ($this.GhostKey -ne $newKey) {
            $this.GhostCache = Get-GhostPieceFrom -board $this.Ctx.Board -active $active -ids $this.Ctx.Ids
            $this.GhostKey   = $newKey
        }

        return $this.GhostCache
    }
}