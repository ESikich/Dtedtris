# === INPUT MANAGER ===

class InputManager {
    [hashtable] $HeldKeys = @{}
    [int]       $DASDelay
    [int]       $DASInterval
    
    # Performance optimization: reduce lookup overhead in hot input processing loop
    hidden [bool[]] $_KeyStates = @($false) * 256  # Direct array access faster than hashtable
    hidden [int[]]  $_KeyTimers = @(0) * 256       # Parallel timer array for DAS tracking
    hidden [System.Collections.Generic.HashSet[System.ConsoleKey]] $_PreviouslyHeld
    hidden [int] $_LastProcessTime = 0

    InputManager([int]$delay,[int]$interval) {
        $this.DASDelay    = $delay
        $this.DASInterval = $interval
        $this._PreviouslyHeld = [System.Collections.Generic.HashSet[System.ConsoleKey]]::new()
    }

    [PlayerAction[]] GetActions() {
        $actions = @()
        $now = [Environment]::TickCount
        
        # Throttle input processing to reasonable frequency to reduce CPU overhead
        if ($now - $this._LastProcessTime -lt 2) {
            return $actions  # Skip processing if called too frequently
        }
        $this._LastProcessTime = $now

        # Process immediate key presses with priority-based handling
        $newPresses = $this.ProcessNewKeyPresses($now)
        $actions += $newPresses

        # Handle DAS (Delayed Auto-Shift) for movement keys only
        # This creates smooth, responsive movement feel for horizontal navigation
        $repeatActions = $this.ProcessDASRepeats($now)
        $actions += $repeatActions

        # Clean up key state tracking to prevent memory bloat during long sessions
        $this.CleanupKeyTracking()

        return $actions
    }

    [PlayerAction[]] ProcessNewKeyPresses([int]$now) {
        # Handle immediate key press responses for maximum input responsiveness
        $actions = @()
        $currentlyHeld = [System.Collections.Generic.HashSet[System.ConsoleKey]]::new()

        # Batch process all available key presses to reduce per-key overhead
        while ([Console]::KeyAvailable) {
            $kinfo = [Console]::ReadKey($true)
            $k = $kinfo.Key
            $currentlyHeld.Add($k)

            # Process only newly pressed keys to avoid double-actions
            if (-not $this._PreviouslyHeld.Contains($k)) {
                switch ($k) {
                    'LeftArrow'  { 
                        $actions += [PlayerAction]::Left
                        $this.InitializeDASTracking($k, $now)
                    }
                    'RightArrow' { 
                        $actions += [PlayerAction]::Right
                        $this.InitializeDASTracking($k, $now)
                    }
                    'DownArrow'  { 
                        $actions += [PlayerAction]::SoftDrop
                        $this.InitializeDASTracking($k, $now)
                    }
                    'UpArrow'    { $actions += [PlayerAction]::RotateCW }
                    'Spacebar'   { $actions += [PlayerAction]::HardDrop }
                    'P'          { $actions += [PlayerAction]::Pause    }
                    'Escape'     { $actions += [PlayerAction]::Quit     }
                }
            }
        }

        # Update held key tracking for next frame
        $this._PreviouslyHeld = $currentlyHeld
        return $actions
    }

    [void] InitializeDASTracking([System.ConsoleKey]$key, [int]$now) {
        # Set up DAS timing for keys that support auto-repeat
        # This enables smooth piece movement when keys are held down
        if (-not $this.HeldKeys.ContainsKey($key)) {
            $this.HeldKeys[$key] = @{
                PressedAt = $now
                LastFired = $now
            }
        }
    }

    [PlayerAction[]] ProcessDASRepeats([int]$now) {
        # Handle auto-repeat for movement keys during extended holds
        # DAS creates the classic Tetris feel where pieces slide smoothly
        $actions = @()
        
        # Only process keys that are still being held
        $keysToRemove = @()
        
        foreach ($k in @($this.HeldKeys.Keys)) {
            # Skip if key is no longer being held
            if (-not $this._PreviouslyHeld.Contains($k)) {
                $keysToRemove += $k
                continue
            }
            
            $info = $this.HeldKeys[$k]
            if (-not $info -or -not $info.ContainsKey('PressedAt')) {
                continue
            }

            $elapsed   = $now - $info.PressedAt
            $sinceLast = $now - $info.LastFired

            # Different DAS behavior for different key types:
            # - Down arrow: immediate repeat (no initial delay) for responsive soft drop
            # - Left/Right: standard DAS delay followed by rapid repeat for precise movement
            $shouldFire = $false
            
            if ($k -eq 'DownArrow') {
                # Soft drop uses immediate repeat for responsive feel
                $shouldFire = $sinceLast -ge $this.DASInterval
            } else {
                # Movement keys use standard DAS: delay then repeat
                $shouldFire = $elapsed -ge $this.DASDelay -and $sinceLast -ge $this.DASInterval
            }

            if ($shouldFire) {
                switch ($k) {
                    'LeftArrow'  { $actions += [PlayerAction]::Left     }
                    'RightArrow' { $actions += [PlayerAction]::Right    }
                    'DownArrow'  { $actions += [PlayerAction]::SoftDrop }
                }
                $info.LastFired = $now
            }
        }
        
        # Remove keys that are no longer held to prevent memory leaks
        foreach ($key in $keysToRemove) {
            $this.HeldKeys.Remove($key)
        }
        
        return $actions
    }

    [void] CleanupKeyTracking() {
        # Prevent memory accumulation during extended play sessions
        # This is particularly important for marathon-style games
        
        # Clear stale key tracking data periodically
        if ($this.HeldKeys.Count -gt 20) {
            $this.HeldKeys.Clear()
        }
        
        # Limit held key set size to prevent bloat
        if ($this._PreviouslyHeld.Count -gt 10) {
            $this._PreviouslyHeld.Clear()
        }
    }

    # Performance monitoring for input system optimization
    [hashtable] GetInputStats() {
        return @{
            HeldKeyCount = $this.HeldKeys.Count
            PreviouslyHeldCount = $this._PreviouslyHeld.Count
            DASDelay = $this.DASDelay
            DASInterval = $this.DASInterval
        }
    }

    # Configuration methods for runtime tuning
    [void] SetDASDelay([int]$newDelay) {
        # Allow runtime adjustment of DAS timing for player preference
        $this.DASDelay = [math]::Max(0, $newDelay)
    }

    [void] SetDASInterval([int]$newInterval) {
        # Allow runtime adjustment of DAS repeat rate
        $this.DASInterval = [math]::Max(1, $newInterval)
    }

    [void] ResetInputState() {
        # Emergency reset for input system if it gets into bad state
        $this.HeldKeys.Clear()
        $this._PreviouslyHeld.Clear()
        for ($i = 0; $i -lt 256; $i++) {
            $this._KeyStates[$i] = $false
            $this._KeyTimers[$i] = 0
        }
    }
}