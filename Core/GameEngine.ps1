# === GAME ENGINE ===

class GameEngine {
    [GameContext]   $Ctx
    [string[]]      $Bag = @()
    [int]           $GravityAccumulator = 0
    [int]           $MsPerGravity       = 800  # Start at level 0 speed
    [int]           $LockDelay          = 500  # Default lock delay in ms
    [Nullable[int]] $LockStartedAt      = $null
    [bool]          $LockDelayActive    = $false
    [int]           $LockResets         = 0
    [int]           $LockResetLimit     = 2    # Maximum lock resets allowed
    [int]           $LFSR
    [int]           $PrevIndex          = -1

    # Ghost piece caching - avoid recalculating when piece hasn't moved
    [Tetromino]     $GhostCache = $null
    [string]        $GhostKey   = ''

    # Configuration dependencies
    [GameConfig]    $Config
    [hashtable]     $TetrominoMasks
    [hashtable]     $TetrominoKicks

    GameEngine([GameContext]$ctx, [GameConfig]$config, [hashtable]$masks, [hashtable]$kicks) {
        $this.Ctx = $ctx
        $this.Config = $config
        $this.TetrominoMasks = $masks
        $this.TetrominoKicks = $kicks
        $this.LFSR = Get-Random -Minimum 1 -Maximum 128  # Ensure non-zero seed for LFSR
        
        # Initialize timing values from config
        $this.LockDelay = $config.LOCK_DELAY_MS
        $this.LockResetLimit = $config.LOCK_RESET_LIMIT
    }

    # Backward compatibility constructor that matches original signature
    GameEngine([GameContext]$ctx) {
        $this.Ctx = $ctx
        $this.Config = $Global:GameConfig
        $this.TetrominoMasks = $global:TetrominoMasks
        $this.TetrominoKicks = $global:TetrominoKicks
        $this.LFSR = Get-Random -Minimum 1 -Maximum 128
        
        # Initialize timing values from global config
        $this.LockDelay = $script:LOCK_DELAY_MS
        $this.LockResetLimit = $script:LOCK_RESET_LIMIT
    }

    [bool] CanPlace([Tetromino]$piece) {
        $id = $piece.Id
        $rot = $piece.Rotation % 4
        $mask = $this.TetrominoMasks[$id][$rot]
        return $this.Ctx.Board.CanPlaceMask($mask, $piece.X, $piece.Y)
    }

    [bool] IsGrounded() {
        if (-not $this.Ctx.Active) { return $false }
        # Test if piece would collide one row down
        return -not $this.CanPlace($this.Ctx.Active.CloneMoved(0, 1, 0))
    }

    [string] GetNextTetrominoId() {
        # NES-style 7-bit LFSR with tap bits at positions 6 and 5
        $bit0 = $this.LFSR -band 1
        $bit1 = ($this.LFSR -shr 1) -band 1
        $newBit = $bit0 -bxor $bit1
        $this.LFSR = ($this.LFSR -shr 1) -bor ($newBit -shl 6)

        # Prevent LFSR from getting stuck at zero
        if ($this.LFSR -eq 0) {
            $this.LFSR = 0x1F
        }

        $index = $this.LFSR % 7

        # NES retry rule: if same as previous piece, generate once more
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

    [GameState] Update([int]$deltaTime) {
        if ($this.Ctx.GameOver) { return $null }

        $stateChanged = $false
        $this.GravityAccumulator += $deltaTime
        
        # Update gravity speed based on current level
        $levelIndex = [math]::Min($this.Ctx.Level, $this.Ctx.GravityIntervals.Count - 1)
        $this.MsPerGravity = $this.Ctx.GravityIntervals[$levelIndex]

        if ($this.GravityAccumulator -ge $this.MsPerGravity) {
            $this.GravityAccumulator -= $this.MsPerGravity

            if ($this.TryMove(0, 1, 0)) {
                # Piece fell successfully - reset lock delay
                $this.ResetLockDelay()
                $stateChanged = $true
            } else {
                # Piece hit something - start or check lock delay
                $now = [Environment]::TickCount

                if (-not $this.LockDelayActive) {
                    $this.StartLockDelay($now)
                    $stateChanged = $true
                } elseif ($this.IsLockDelayExpired($now)) {
                    $this.ForceLock()
                    $stateChanged = $true
                }
            }
        }

        return $stateChanged ? $this.TakeSnapshot() : $null
    }

    [bool] TryMove([int]$dx, [int]$dy, [int]$dr) {
        $next = $this.Ctx.Active.CloneMoved($dx, $dy, $dr)
        if (-not $this.CanPlace($next)) { return $false }

        $this.Ctx.Active = $next

        # Reset lock delay if piece can still move down and we haven't exceeded reset limit
        if ($this.LockDelayActive -and $this.IsGrounded() -and
            $this.LockResets -lt $this.LockResetLimit) {
            $this.LockStartedAt = [Environment]::TickCount
            $this.LockResets++
        }

        return $true
    }

    [bool] TryRotateWithWallKick([Tetromino]$piece, [int]$direction) {
        $oldRotation = $piece.Rotation % 4
        $newRotation = ($oldRotation + $direction) % 4
        $kickKey = "${oldRotation}_${newRotation}"

        # I-piece has different wall kick data than other pieces
        $kickTable = if ($piece.Id -eq 'I') {
            $this.TetrominoKicks.I[$kickKey]
        } else {
            $this.TetrominoKicks.Default[$kickKey]
        }

        # Try each wall kick offset in sequence
        foreach ($kick in $kickTable) {
            $testPiece = $piece.CloneMoved($kick.X, $kick.Y, $direction)
            if ($this.CanPlace($testPiece)) {
                $this.Ctx.Active = $testPiece

                # Reset lock delay for successful rotation
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
        # Ensure we have a next piece queued
        if (-not $this.Ctx.NextQueue) {
            $this.Ctx.NextQueue = @($this.GetNextTetrominoId())
        }

        $id = $this.Ctx.NextQueue[0]
        $this.Ctx.NextQueue = ,($this.GetNextTetrominoId())

        # Track piece statistics
        if (-not $this.Ctx.PieceCounts.ContainsKey($id)) {
            $this.Ctx.PieceCounts[$id] = 0
        }
        $this.Ctx.PieceCounts[$id]++

        # Center piece horizontally using precomputed dimensions
        $dimensions = $this.Config.TetrominoDims[$id]
        $centerX = [math]::Floor(($this.Ctx.Width - $dimensions.Width) / 2) - $dimensions.MinX

        $this.Ctx.Active = [Tetromino]::new(
            $id,
            $centerX,
            $this.Config.SPAWN_Y_OFFSET,
            $this.TetrominoKicks
        )

        # Test for game over conditions
        if (-not $this.CanPlace($this.Ctx.Active)) {
            $this.Ctx.GameOver = $true
        } elseif ($this.TryMove(0, 1, 0)) {
            # Piece can fall, move it back up to proper spawn position
            $null = $this.TryMove(0, -1, 0)
        } else {
            # Piece can't fall from spawn - game over
            $this.Ctx.GameOver = $true
        }
    }

    [void] ForceLock() {
        if (-not $this.Ctx.Active) { return }

        $id = $this.Ctx.Active.Id
        $rot = $this.Ctx.Active.Rotation % 4
        $mask = $this.TetrominoMasks[$id][$rot]

        $this.Ctx.Board.PlaceMask($mask, $this.Ctx.Active.X, $this.Ctx.Active.Y, $id)

        # Handle line clearing with visual feedback
        $fullLines = $this.Ctx.Board.GetFullLines()
        if ($fullLines.Count -gt 0) {
            $this.FlashFullLines($fullLines)
        }

        $linesCleared = $this.Ctx.Board.ClearLines()
        if ($linesCleared -gt 0) {
            $this.UpdateScoreAndLevel($linesCleared)
        }

        $this.Spawn()
        $this.ResetLockDelay()
    }

    # Private helper methods for lock delay management
    [void] StartLockDelay([int]$currentTime) {
        $this.LockDelayActive = $true
        $this.LockStartedAt = $currentTime
    }

    [void] ResetLockDelay() {
        $this.LockDelayActive = $false
        $this.LockStartedAt = $null
        $this.LockResets = 0
    }

    [bool] IsLockDelayExpired([int]$currentTime) {
        return ($null -ne $this.LockStartedAt) -and 
               ($currentTime - $this.LockStartedAt) -ge $this.LockDelay
    }

    [void] FlashFullLines([int[]]$lineIndices) {
        # Only flash if we have a renderer available
        if ($script:app -and $script:app.Renderer) {
            $script:app.Renderer.FlashLines($lineIndices, 4, 32)
        }
    }

    [void] UpdateScoreAndLevel([int]$linesCleared) {
        $this.Ctx.Lines += $linesCleared
        $this.Ctx.Level = [math]::Floor($this.Ctx.Lines / $this.Config.LINES_PER_LEVEL)
        
        # Apply scoring formula: base score × (level + 1)
        $baseScore = $this.Config.LINE_CLEAR_SCORES[$linesCleared]
        $this.Ctx.Score += $baseScore * ($this.Ctx.Level + 1)
    }

    [string] MakeGhostKey([Tetromino]$piece) {
        # Create cache key from piece position and rotation
        return "{0}:{1}:{2}:{3}" -f $piece.Id, $piece.X, $piece.Y, ($piece.Rotation % 4)
    }

    [Tetromino] GetGhostCached() {
        $active = $this.Ctx.Active
        if (-not $active) { return $null }

        $newKey = $this.MakeGhostKey($active)

        # Only recalculate ghost if piece has moved
        if ($this.GhostKey -ne $newKey) {
            $this.GhostCache = Get-GhostPieceFrom -board $this.Ctx.Board -active $active -ids $this.Ctx.Ids
            $this.GhostKey = $newKey
        }

        return $this.GhostCache
    }
}