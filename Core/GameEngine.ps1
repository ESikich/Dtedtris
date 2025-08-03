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

    # Ghost piece caching for performance optimization
    [Tetromino]     $GhostCache = $null
    [string]        $GhostKey   = ''
    
    # Performance optimization: reduce object allocation overhead
    hidden [hashtable] $_TempPieceCache = @{}
    hidden [System.Collections.Generic.Dictionary[string,bool]] $_CollisionCache
    hidden [int] $_LastSnapshotHash = 0

    GameEngine([GameContext]$ctx) {
        $this.Ctx = $ctx
        # Seed LFSR with non-zero value to ensure proper NES-style randomization
        $this.LFSR = Get-Random -Minimum 1 -Maximum 128
        
        # Initialize performance optimization structures
        $this._CollisionCache = [System.Collections.Generic.Dictionary[string,bool]]::new()
    }

    [bool] CanPlace([Tetromino]$p) {
        # Collision detection is called frequently during movement and rotation
        # Cache results for identical pieces to avoid redundant calculations
        $cacheKey = "$($p.Id):$($p.X):$($p.Y):$($p.Rotation % 4)"
        
        if ($this._CollisionCache.ContainsKey($cacheKey)) {
            return $this._CollisionCache[$cacheKey]
        }
        
        $id = $p.Id
        $rot = $p.Rotation % 4
        $mask = $global:TetrominoMasks[$id][$rot]
        $result = $this.Ctx.Board.CanPlaceMask($mask, $p.X, $p.Y)
        
        # Cache result for future identical queries to improve DAS performance
        $this._CollisionCache[$cacheKey] = $result
        
        return $result
    }

    [bool] IsGrounded() {
        # Check if active piece would collide if moved down one row
        # This determines when lock delay should activate
        if (-not $this.Ctx.Active) { return $false }
        return -not $this.CanPlace($this.Ctx.Active.CloneMoved(0, 1, 0))
    }

    [string] GetNextTetrominoId() {
        # NES Tetris randomization algorithm using 7-bit Linear Feedback Shift Register
        # This maintains authentic gameplay feel while preventing obvious patterns
        
        # Step 1: Advance LFSR using taps at positions 1 and 0 (standard 7-bit polynomial)
        $bit0 = $this.LFSR -band 1
        $bit1 = ($this.LFSR -shr 1) -band 1
        $newBit = $bit0 -bxor $bit1
        $this.LFSR = ($this.LFSR -shr 1) -bor ($newBit -shl 6)

        # Prevent LFSR from getting stuck in all-zeros state
        if ($this.LFSR -eq 0) {
            $this.LFSR = 0x1F  # Reset to known good state
        }

        # Step 2: Map LFSR output to piece index (modulo 7 for seven piece types)
        $index = $this.LFSR % 7

        # NES retry rule: if same as previous piece, advance LFSR once more
        # This reduces immediate repeats while maintaining randomness
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
        # Create immutable game state for rendering system
        # Only create new snapshot if game state has actually changed
        $next = ''
        if ($this.Ctx.NextQueue.Count -gt 0) {
            $next = $this.Ctx.NextQueue[0]
        }

        # Efficient ghost piece calculation with caching
        $ghost = $this.GetGhostCached()

        # Generate hash to detect state changes and avoid unnecessary snapshots
        $stateHash = "$($this.Ctx.Score):$($this.Ctx.Lines):$($this.Ctx.Level):$($this.Ctx.Active.X):$($this.Ctx.Active.Y):$($this.Ctx.Active.Rotation)".GetHashCode()
        
        # Return cached snapshot if nothing meaningful has changed
        if ($stateHash -eq $this._LastSnapshotHash -and -not $this.Ctx.GameOver) {
            return $null
        }
        
        $this._LastSnapshotHash = $stateHash

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
        # Main game logic update cycle - gravity, lock delay, line clearing
        if ($this.Ctx.GameOver) { return $null }

        $changed = $false
        $this.GravityAccumulator += $dt
        
        # Gravity speed increases with level for authentic Tetris progression
        $this.MsPerGravity = $this.Ctx.GravityIntervals[
            [math]::Min($this.Ctx.Level, $this.Ctx.GravityIntervals.Count - 1)
        ]

        # Apply gravity when accumulator exceeds threshold
        if ($this.GravityAccumulator -ge $this.MsPerGravity) {
            $this.GravityAccumulator -= $this.MsPerGravity

            # Attempt to move piece down due to gravity
            if ($this.TryMove(0, 1, 0)) {
                # Piece moved successfully - reset lock delay system
                $this.LockDelayActive = $false
                $this.LockResets      = 0
                $this.LockStartedAt   = $null
                $changed = $true
            } else {
                # Piece cannot move down - initiate or check lock delay
                $now = [Environment]::TickCount

                if (-not $this.LockDelayActive) {
                    # Start lock delay timer to give player time for final adjustments
                    $this.LockDelayActive = $true
                    $this.LockStartedAt   = $now
                    $changed = $true
                } elseif (($null -ne $this.LockStartedAt) -and ($now - $this.LockStartedAt) -ge $this.LockDelay) {
                    # Lock delay expired - force piece placement
                    $this.ForceLock()
                    $changed = $true
                }
            }
        }

        # Clear collision cache periodically to prevent memory bloat during long games
        if ($this._CollisionCache.Count -gt 1000) {
            $this._CollisionCache.Clear()
        }

        if ($changed) {
            return $this.TakeSnapshot()
        }

        return $null
    }

    [bool] TryMove([int]$dx, [int]$dy, [int]$dr) {
        # Attempt to move/rotate the active piece with collision detection
        $next = $this.Ctx.Active.CloneMoved($dx, $dy, $dr)
        if (-not $this.CanPlace($next)) { return $false }

        $this.Ctx.Active = $next

        # Lock delay reset system: allow limited resets when piece moves while grounded
        # This prevents infinite lock delay while allowing skilled maneuvering
        if ($this.LockDelayActive -and $this.IsGrounded() -and
            $this.LockResets -lt $this.LockResetLimit) {

            # Reset lock timer but track number of resets to prevent abuse
            $this.LockStartedAt = [Environment]::TickCount
            $this.LockResets++
        }

        return $true
    }

    [bool] TryRotateWithWallKick([Tetromino]$piece, [int]$dir) {
        # Super Rotation System (SRS) wall kicks allow rotations near walls/floor
        # Different kick tables for I-piece vs other pieces maintain standard gameplay
        $old = $piece.Rotation % 4
        $new = ($old + $dir) % 4
        $key = "${old}_${new}"

        # I-piece uses special kick table due to its unique 4x1 shape
        $table = if ($piece.Id -eq 'I') {
            $global:TetrominoKicks.I[$key]
        } else {
            $global:TetrominoKicks.Default[$key]
        }

        # Test each kick offset in priority order until one succeeds
        foreach ($kick in $table) {
            $test = $piece.CloneMoved($kick.X, $kick.Y, $dir)
            if ($this.CanPlace($test)) {
                $this.Ctx.Active = $test

                # Reset lock delay on successful rotation to reward skilled play
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
        # Spawn next piece and prepare subsequent piece in queue
        if (-not $this.Ctx.NextQueue) {
            $this.Ctx.NextQueue = @($this.GetNextTetrominoId())
        }

        $id = $this.Ctx.NextQueue[0]
        $this.Ctx.NextQueue = ,($this.GetNextTetrominoId())

        # Track piece statistics for player reference
        if (-not $this.Ctx.PieceCounts.ContainsKey($id)) {
            $this.Ctx.PieceCounts[$id] = 0
        }
        $this.Ctx.PieceCounts[$id]++

        # Center piece horizontally using precomputed dimensions
        # This ensures consistent spawn behavior across all piece types
        $dim = $global:TetrominoDims[$id]
        $x   = [math]::Floor(($this.Ctx.Width - $dim.Width) / 2) - $dim.MinX

        $this.Ctx.Active = [Tetromino]::new(
            $id,
            $x,
            $script:SPAWN_Y_OFFSET,
            $global:TetrominoKicks
        )

        # Game over detection: piece cannot spawn due to collision
        if (-not $this.CanPlace($this.Ctx.Active)) {
            $this.Ctx.GameOver = $true
        } elseif ($this.TryMove(0, 1, 0)) {
            # Attempt initial soft drop to improve piece placement feel
            $null = $this.TryMove(0, -1, 0)
        } else {
            # Piece is immediately grounded - this indicates very high stack
            $this.Ctx.GameOver = $true
        }
        
        # Clear collision cache after spawn to ensure fresh calculations for new piece
        $this._CollisionCache.Clear()
    }

    [void] ForceLock() {
        # Lock active piece into board and handle line clearing
        if (-not $this.Ctx.Active) { return }

        $id = $this.Ctx.Active.Id
        $rot = $this.Ctx.Active.Rotation % 4
        $mask = $global:TetrominoMasks[$id][$rot]

        # Place piece permanently into game board
        $this.Ctx.Board.PlaceMask($mask, $this.Ctx.Active.X, $this.Ctx.Active.Y, $id)

        # Step 1: Identify completed lines before clearing
        $fullLines = $this.Ctx.Board.GetFullLines()

        # Step 2: Visual feedback for line clears enhances player satisfaction
        if ($fullLines.Count -gt 0 -and $script:app -and $script:app.Renderer) {
            $script:app.Renderer.FlashLines($fullLines, 4, 32)  # Flash count, duration per flash
        }

        # Step 3: Remove completed lines and update score/level
        $cleared = $this.Ctx.Board.ClearLines()
        if ($cleared -gt 0) {
            $this.Ctx.Lines += $cleared
            # Level progression every 10 lines cleared (standard Tetris)
            $this.Ctx.Level = [math]::Floor($this.Ctx.Lines / $script:LINES_PER_LEVEL)
            # Scoring system: more lines cleared simultaneously = exponentially higher score
            $this.Ctx.Score += $script:LINE_CLEAR_SCORES[$cleared] * ($this.Ctx.Level + 1)
        }

        # Spawn next piece and reset lock delay system
        $this.Spawn()
        $this.LockDelayActive = $false
        $this.LockStartedAt   = $null
        $this.LockResets      = 0
    }

    [string] MakeGhostKey([Tetromino]$piece) {
        # Generate cache key for ghost piece calculation
        # Format ensures unique keys for each piece state
        return "{0}:{1}:{2}:{3}" -f $piece.Id, $piece.X, $piece.Y, ($piece.Rotation % 4)
    }

    [Tetromino] GetGhostCached() {
        # Ghost piece shows where active piece will land if dropped immediately
        # Caching prevents expensive recalculation when piece hasn't moved
        $active = $this.Ctx.Active
        if (-not $active) { return $null }

        $newKey = $this.MakeGhostKey($active)

        # Only recalculate ghost position when active piece has moved or rotated
        if ($this.GhostKey -ne $newKey) {
            $this.GhostCache = Get-GhostPieceFrom -board $this.Ctx.Board -active $active -ids $this.Ctx.Ids
            $this.GhostKey   = $newKey
        }

        return $this.GhostCache
    }

    # Performance monitoring for optimization tuning
    [hashtable] GetEngineStats() {
        return @{
            CollisionCacheSize = $this._CollisionCache.Count
            LockDelayActive = $this.LockDelayActive
            LockResets = $this.LockResets
            CurrentLevel = $this.Ctx.Level
            GravityInterval = $this.MsPerGravity
        }
    }

    # Debug helper for analyzing performance bottlenecks
    [void] ClearPerformanceCaches() {
        $this._CollisionCache.Clear()
        $this.GhostCache = $null
        $this.GhostKey = ''
    }
}